import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

void checkTransfer(bool Function()? isCanceled) {
  if (isCanceled?.call() ?? false) throw StateError('传输已取消');
}

Future<void> closeResponse(http.StreamedResponse response) async {
  await response.stream.listen((_) {}).cancel();
}

/// Follow redirects explicitly so cookies are rebuilt for each destination.
Future<({http.StreamedResponse response, Uri uri})> downloadRequest(
  http.Client client,
  Uri uri,
  Map<String, String> Function(Uri) headers, {
  bool Function()? isCanceled,
}) async {
  for (var hop = 0; hop < 6; hop++) {
    checkTransfer(isCanceled);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('下载地址必须使用 HTTPS');
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers.addAll(headers(uri));
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 60));
    if (isCanceled?.call() ?? false) {
      await closeResponse(response);
      checkTransfer(isCanceled);
    }
    if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
      final location = response.headers['location'];
      await closeResponse(response);
      if (location == null) throw StateError('下载重定向缺少 Location');
      uri = uri.resolve(location);
      continue;
    }
    if (response.statusCode == 210 ||
        (response.statusCode == 200 &&
            (response.headers['content-type'] ?? '').contains(
              'application/json',
            ))) {
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        checkTransfer(isCanceled);
        if (bytes.length + chunk.length > 65536) throw StateError('下载重定向响应过大');
        bytes.addAll(chunk);
      }
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final data = body['data'];
      final location =
          (data is Map ? data['redirect_url'] : null) ?? body['redirect_url'];
      if (location is! String || location.isEmpty) {
        throw StateError('下载重定向缺少地址');
      }
      uri = uri.resolve(location);
      continue;
    }
    return (response: response, uri: uri);
  }
  throw StateError('下载重定向次数过多');
}

Future<int> probeDownloadSize(
  http.Client client,
  Uri uri,
  Map<String, String> Function(Uri) headers, {
  bool Function()? isCanceled,
}) async {
  final result = await downloadRequest(
    client,
    uri,
    (u) => {...headers(u), 'Range': 'bytes=0-0'},
    isCanceled: isCanceled,
  );
  try {
    final response = result.response;
    if (response.statusCode == 206) {
      final match = RegExp(
        r'^bytes 0-0/(\d+)$',
      ).firstMatch(response.headers['content-range'] ?? '');
      if (match != null) return int.parse(match[1]!);
    }
    if (response.statusCode == 416 &&
        response.headers['content-range'] == 'bytes */0') {
      return 0;
    }
    if (response.statusCode == 200 && response.contentLength != null) {
      return response.contentLength!;
    }
    throw StateError('无法确认下载文件大小 (HTTP ${response.statusCode})');
  } finally {
    await closeResponse(result.response);
  }
}

/// Bounded network chunks, a serialized writer, and strict byte-range checks.
Future<void> downloadRanges({
  required http.Client client,
  required Uri uri,
  required Map<String, String> Function(Uri) headers,
  required File file,
  required int total,
  required Set<int> blocks,
  required Object Function(String) invalid,
  int chunkSize = 1024 * 1024,
  int concurrency = 1,
  Future<Uri> Function()? refreshUri,
  bool Function()? isCanceled,
  void Function(int, int?)? onProgress,
  void Function(int, Set<int>)? onBlocks,
}) async {
  if (total < 0) throw invalid('文件大小无效');
  checkTransfer(isCanceled);
  final count = (total + chunkSize - 1) ~/ chunkSize;
  final length = await file.length();
  blocks.removeWhere(
    (i) => i < 0 || i >= count || min((i + 1) * chunkSize, total) > length,
  );
  final raf = await file.open(
    mode: blocks.isEmpty ? FileMode.write : FileMode.writeOnlyAppend,
  );
  var next = 0;
  var received = blocks.fold<int>(
    0,
    (sum, i) => sum + min(chunkSize, total - i * chunkSize),
  );
  Future<void> writer = Future<void>.value();
  Object? error;
  final inFlight = <int, int>{};
  void reportProgress() {
    onProgress?.call(
      min(
        total,
        received + inFlight.values.fold<int>(0, (sum, bytes) => sum + bytes),
      ),
      total,
    );
  }

  bool stopped() => error != null || (isCanceled?.call() ?? false);
  Future<Uint8List> readRange(int start, int end) async {
    var currentUri = uri;
    for (var attempt = 0; attempt < 3; attempt++) {
      checkTransfer(stopped);
      try {
        final result = await downloadRequest(
          client,
          currentUri,
          (u) => {...headers(u), 'Range': 'bytes=$start-$end'},
          isCanceled: stopped,
        );
        final response = result.response;
        final expected = end - start + 1;
        final range = response.headers['content-range'];
        final valid =
            response.statusCode == 206
                ? range == 'bytes $start-$end/$total'
                : response.statusCode == 200 && start == 0 && expected == total;
        if (!valid) {
          await closeResponse(response);
          throw invalid('分片范围不匹配 (HTTP ${response.statusCode}) @ $start');
        }
        final builder = BytesBuilder(copy: false);
        var byteCount = 0;
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          checkTransfer(stopped);
          if (byteCount + chunk.length > expected) {
            throw invalid('分片超出请求范围 @ $start');
          }
          builder.add(chunk);
          byteCount += chunk.length;
          inFlight[start] = byteCount;
          reportProgress();
        }
        if (byteCount != expected) {
          throw invalid('分片数据不完整 @ $start: $byteCount/$expected');
        }
        return builder.takeBytes();
      } catch (_) {
        inFlight.remove(start);
        if (!stopped()) reportProgress();
        if (stopped() || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        checkTransfer(stopped);
        if (refreshUri != null) currentUri = await refreshUri();
      }
    }
    throw invalid('分片重试失败');
  }

  try {
    await raf.truncate(total);
    onProgress?.call(received, total);
    Future<void> worker() async {
      try {
        while (!stopped()) {
          final index = next++;
          if (index >= count) return;
          if (blocks.contains(index)) continue;
          final start = index * chunkSize;
          final end = min(start + chunkSize, total) - 1;
          final expected = end - start + 1;
          final bytes = await readRange(start, end);
          final write = writer.then((_) async {
            checkTransfer(stopped);
            await raf.setPosition(start);
            await raf.writeFrom(bytes);
            blocks.add(index);
            inFlight.remove(start);
            received += expected;
            onBlocks?.call(received, blocks);
            reportProgress();
          });
          writer = write.catchError((Object _) {});
          await write;
        }
      } catch (e) {
        error ??= e;
      }
    }

    await Future.wait(
      List.generate(max(1, min(concurrency, 8)), (_) => worker()),
    );
    await writer;
    if (error != null) throw error!;
    checkTransfer(isCanceled);
    if (blocks.length != count || received != total) throw invalid('下载数据不完整');
    await raf.flush();
  } finally {
    await raf.close();
  }
}
