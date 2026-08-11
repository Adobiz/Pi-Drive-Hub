import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_pan/providers/quark/quark_api.dart';
import 'package:pi_pan/providers/quark/quark_auth.dart';

void main() {
  const chunkSize = 8 * 1024 * 1024;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pi_pan_quark_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('文件大小为分片整数倍时不会请求越界分片', () async {
    final ranges = <String>[];
    final client = MockClient((request) async {
      if (request.url.host == 'drive.quark.cn') {
        return http.Response(
          '{"code":0,"data":[{"download_url":"https://download.test/file"}]}',
          200,
        );
      }

      final range = _rangeHeader(request)!;
      ranges.add(range);
      if (range == 'bytes=0-0' && ranges.length == 1) {
        return http.Response.bytes(
          const [0],
          206,
          headers: {'content-range': 'bytes 0-0/$chunkSize'},
        );
      }
      expect(range, 'bytes=0-${chunkSize - 1}');
      return http.Response.bytes(
        Uint8List(chunkSize),
        206,
        headers: {'content-range': 'bytes 0-${chunkSize - 1}/$chunkSize'},
      );
    });
    final api = QuarkApi(auth: QuarkAuthProvider(), client: client);
    final output = '${tempDir.path}/exact-chunk.bin';

    await api.download('fid', output);

    expect(ranges, ['bytes=0-0', 'bytes=0-${chunkSize - 1}']);
    expect(await File(output).length(), chunkSize);
  });

  test('分片连接失败后刷新直链并重试', () async {
    var downloadUrlCalls = 0;
    var chunkCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'drive.quark.cn') {
        downloadUrlCalls++;
        return http.Response(
          '{"code":0,"data":[{"download_url":"https://download.test/file-$downloadUrlCalls"}]}',
          200,
        );
      }

      final range = _rangeHeader(request);
      if (range == 'bytes=0-0') {
        return http.Response.bytes(
          const [0],
          206,
          headers: {'content-range': 'bytes 0-0/4'},
        );
      }
      chunkCalls++;
      if (chunkCalls == 1) {
        throw http.ClientException('connection closed');
      }
      return http.Response.bytes(
        const [1, 2, 3, 4],
        206,
        headers: {'content-range': 'bytes 0-3/4'},
      );
    });
    final api = QuarkApi(auth: QuarkAuthProvider(), client: client);
    final output = '${tempDir.path}/retry.bin';

    await api.download('fid', output);

    expect(downloadUrlCalls, 2);
    expect(chunkCalls, 2);
    expect(await File(output).readAsBytes(), [1, 2, 3, 4]);
  });

  test('续传会定位覆盖分片而不是追加到文件末尾', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'drive.quark.cn') {
        return http.Response(
          '{"code":0,"data":[{"download_url":"https://download.test/file"}]}',
          200,
        );
      }

      final range = _rangeHeader(request);
      if (range == 'bytes=0-0') {
        return http.Response.bytes(
          const [0],
          206,
          headers: {'content-range': 'bytes 0-0/${chunkSize + 4}'},
        );
      }
      expect(range, 'bytes=$chunkSize-${chunkSize + 3}');
      return http.Response.bytes(
        const [7, 8, 9, 10],
        206,
        headers: {
          'content-range': 'bytes $chunkSize-${chunkSize + 3}/${chunkSize + 4}',
        },
      );
    });
    final api = QuarkApi(auth: QuarkAuthProvider(), client: client);
    final output = '${tempDir.path}/resume.bin';
    await File(output).writeAsBytes(Uint8List(chunkSize + 4));

    await api.download('fid', output, completedBlocks: {0});

    final file = File(output);
    expect(await file.length(), chunkSize + 4);
    final raf = await file.open();
    await raf.setPosition(chunkSize);
    expect(await raf.read(4), [7, 8, 9, 10]);
    await raf.close();
  });

  test('本地半成品不存在时会丢弃过期续传记录', () async {
    var chunkCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'drive.quark.cn') {
        return http.Response(
          '{"code":0,"data":[{"download_url":"https://download.test/file"}]}',
          200,
        );
      }

      final range = _rangeHeader(request);
      if (range == 'bytes=0-0') {
        return http.Response.bytes(
          const [0],
          206,
          headers: {'content-range': 'bytes 0-0/4'},
        );
      }
      chunkCalls++;
      expect(range, 'bytes=0-3');
      return http.Response.bytes(
        const [4, 3, 2, 1],
        206,
        headers: {'content-range': 'bytes 0-3/4'},
      );
    });
    final api = QuarkApi(auth: QuarkAuthProvider(), client: client);
    final output = '${tempDir.path}/missing-resume.bin';
    final completedBlocks = <int>{0};

    await api.download('fid', output, completedBlocks: completedBlocks);

    expect(chunkCalls, 1);
    expect(completedBlocks, {0});
    expect(await File(output).readAsBytes(), [4, 3, 2, 1]);
  });
}

String? _rangeHeader(http.BaseRequest request) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == 'range') return entry.value;
  }
  return null;
}
