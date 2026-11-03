// Release audit: regression expectations. No real accounts or network requests.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_pan/core/models/cloud_account.dart';
import 'package:pi_pan/core/models/cloud_file.dart';
import 'package:pi_pan/core/providers/cloud_provider.dart';
import 'package:pi_pan/core/state/download_manager.dart';
import 'package:pi_pan/core/state/upload_manager.dart';
import 'package:pi_pan/providers/baidu_client/baidu_client_api.dart';
import 'package:pi_pan/providers/baidu_client/baidu_client_auth.dart';
import 'package:pi_pan/providers/baidu_client/cookie_jar.dart';
import 'package:pi_pan/providers/pan123/pan123_api.dart';
import 'package:pi_pan/providers/pan123/pan123_auth.dart';

class PendingCall {
  final String path;
  final TransferProgress? progress;
  final Completer<void> end = Completer<void>();
  PendingCall(this.path, this.progress);
}

class FakeDrive extends CloudProvider {
  @override
  final String id;
  FakeDrive(this.id);
  final uploads = <PendingCall>[];
  final downloads = <PendingCall>[];
  @override
  String get displayName => id;
  @override
  void clearSession() {}
  @override
  Future<CloudAccount> getAccountInfo() async =>
      CloudAccount(providerId: id, displayName: id);
  @override
  Future<List<CloudFile>> list(String path) async => [];
  @override
  Future<CloudFile> createFolder(String parentPath, String name) =>
      throw UnimplementedError();
  @override
  Future<void> rename(String path, String newName) async {}
  @override
  Future<void> delete(String path) async {}
  @override
  Future<void> upload(
    String localPath,
    String remoteDir, {
    TransferProgress? onProgress,
    TransferCancellation? cancellation,
    bool Function()? isCanceled,
  }) {
    final call = PendingCall(localPath, onProgress);
    uploads.add(call);
    return call.end.future;
  }

  @override
  Future<void> download(
    String remotePath,
    String localDir, {
    TransferProgress? onProgress,
    TransferCancellation? cancellation,
    bool Function()? isCanceled,
    Set<int>? completedBlocks,
    void Function(int, Set<int>)? onBlocks,
  }) {
    final call = PendingCall(remotePath, onProgress);
    downloads.add(call);
    return call.end.future;
  }
}

class Fake123Auth extends Pan123AuthProvider {
  @override
  Future<String?> getAccessToken() async => 'fake-local-token';
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

BaiduClientApi validBaiduApi(List<int> content, {int concurrency = 1}) {
  final client = MockClient((req) async {
    if (req.url.queryParameters['method'] == 'uinfo') {
      return http.Response('{"uk":1}', 200);
    }
    if (req.url.queryParameters['method'] == 'locatedownload') {
      return http.Response(
        '{"urls":[{"encrypt":0,"url":"https://cdn.example/file"}]}',
        200,
      );
    }
    final range =
        RegExp(r'bytes=(\d+)-(\d*)').firstMatch(req.headers['Range']!)!;
    final start = int.parse(range[1]!);
    final end = range[2]!.isEmpty ? content.length - 1 : int.parse(range[2]!);
    return http.Response.bytes(
      content.sublist(start, end + 1),
      206,
      headers: {'content-range': 'bytes $start-$end/${content.length}'},
    );
  });
  return BaiduClientApi(auth: BaiduClientAuthProvider(), client: client)
    ..downloadConcurrency = concurrency;
}

void main() {
  test('Control: valid Baidu serial chunks preserve the file hash', () async {
    final dir = await Directory.systemTemp.createTemp('pi-valid-baidu-');
    addTearDown(() => dir.delete(recursive: true));
    final content = List<int>.generate(800000, (i) => (i ~/ 262144) + 1);
    await validBaiduApi(content).download('/file', '${dir.path}/file');
    expect(
      sha256.convert(await File('${dir.path}/file').readAsBytes()).toString(),
      sha256.convert(content).toString(),
    );
  });
  test('Valid Baidu parallel chunks must preserve the file hash', () async {
    final dir = await Directory.systemTemp.createTemp('pi-parallel-baidu-');
    addTearDown(() => dir.delete(recursive: true));
    final content = List<int>.generate(800000, (i) => (i ~/ 262144) + 1);
    await validBaiduApi(
      content,
      concurrency: 3,
    ).download('/file', '${dir.path}/file');
    expect(
      sha256.convert(await File('${dir.path}/file').readAsBytes()).toString(),
      sha256.convert(content).toString(),
    );
  });
  test('Control: valid 123 chunks preserve the file hash', () async {
    final dir = await Directory.systemTemp.createTemp('pi-valid-123-');
    addTearDown(() => dir.delete(recursive: true));
    final content = List<int>.generate(1500000, (i) => i % 127);
    final client = MockClient((req) async {
      if (req.url.path.endsWith('download_info')) {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {'DownloadUrl': 'https://cdn.example/file'},
          }),
          200,
        );
      }
      if (!req.headers.containsKey('Range')) {
        return http.Response.bytes(content, 200);
      }
      final range =
          RegExp(r'bytes=(\d+)-(\d*)').firstMatch(req.headers['Range']!)!;
      final start = int.parse(range[1]!);
      final end = range[2]!.isEmpty ? content.length - 1 : int.parse(range[2]!);
      return http.Response.bytes(
        content.sublist(start, end + 1),
        206,
        headers: {'content-range': 'bytes $start-$end/${content.length}'},
      );
    });
    final api = Pan123Api(auth: Fake123Auth(), client: client);
    await api.download(1, '', '', content.length, 0, '${dir.path}/file');
    expect(
      sha256.convert(await File('${dir.path}/file').readAsBytes()).toString(),
      sha256.convert(content).toString(),
    );
  });
  test(
    '123 direct binary download must preserve non-UTF8 file bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('pi-binary-123-');
      addTearDown(() => dir.delete(recursive: true));
      final content = [255, 216, 255, 224, 0, 1, 128];
      final client = MockClient((req) async {
        if (req.url.path.endsWith('download_info')) {
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {'DownloadUrl': 'https://cdn.example/file'},
            }),
            200,
          );
        }
        return http.Response.bytes(
          content,
          req.headers.containsKey('Range') ? 206 : 200,
          headers: {'content-range': 'bytes 0-6/7'},
        );
      });
      final api = Pan123Api(auth: Fake123Auth(), client: client);
      await api.download(1, '', '', content.length, 0, '${dir.path}/file');
      expect(await File('${dir.path}/file').readAsBytes(), content);
    },
  );
  test('Removing an upload must stop subsequent upload progress', () async {
    final drive = FakeDrive('a');
    final manager = UploadManager();
    manager.add(drive, '/tmp/a.txt', '/');
    manager.remove(manager.tasks.single.id);
    expect(() => drive.uploads.single.progress!(1, 2), throwsStateError);
  });
  test('Logout/cancelAll must stop subsequent upload progress', () async {
    final drive = FakeDrive('a');
    final manager = UploadManager();
    manager.add(drive, '/tmp/a.txt', '/');
    manager.cancelAll();
    expect(() => drive.uploads.single.progress!(1, 2), throwsStateError);
  });
  test(
    'Old upload completion must not route new account queue to old provider',
    () async {
      final a = FakeDrive('a');
      final b = FakeDrive('b');
      final manager = UploadManager()..maxConcurrent = 1;
      manager.add(a, '/tmp/old.txt', '/');
      manager.cancelAll();
      manager.add(b, '/tmp/new1.txt', '/');
      await tick();
      manager.add(b, '/tmp/new2.txt', '/');
      a.uploads.single.end.complete();
      await tick();
      expect(a.uploads.map((c) => c.path), ['/tmp/old.txt']);
    },
  );
  test(
    'Removing a download must not release its concurrency slot twice',
    () async {
      final drive = FakeDrive('a');
      final manager = DownloadManager();
      manager.add(drive, '/a', '/tmp', 'audit-missing-a');
      await tick();
      manager.add(drive, '/b', '/tmp', 'audit-missing-b');
      manager.remove(manager.tasks.first.id);
      await tick();
      manager.add(drive, '/c', '/tmp', 'audit-missing-c');
      drive.downloads.first.end.complete();
      await tick();
      expect(
        manager.tasks
            .where((t) => t.status == DownloadStatus.downloading)
            .length,
        1,
      );
    },
  );
  test(
    'Loaded authentication cookies must not be sent to an unrelated host',
    () {
      final jar = CookieJar()..loadMap({'BDUSS': 'fake-secret'});
      expect(
        jar.headerFor(Uri.parse('https://unrelated.example/file')),
        isEmpty,
      );
    },
  );
  test('Baidu must reject incomplete chunk responses', () async {
    final dir = await Directory.systemTemp.createTemp('pi-baidu-audit-');
    addTearDown(() => dir.delete(recursive: true));
    const total = 600000;
    final client = MockClient((req) async {
      if (req.url.queryParameters['method'] == 'uinfo') {
        return http.Response('{"uk":1}', 200);
      }
      if (req.url.queryParameters['method'] == 'locatedownload') {
        return http.Response(
          '{"urls":[{"encrypt":0,"url":"https://cdn.example/file"}]}',
          200,
        );
      }
      if (req.headers['Range'] == 'bytes=0-0') {
        return http.Response.bytes(
          [0],
          206,
          headers: {'content-range': 'bytes 0-0/$total'},
        );
      }
      return http.Response.bytes(
        [7],
        206,
        headers: {'content-range': 'bytes 0-0/$total'},
      );
    });
    final api = BaiduClientApi(auth: BaiduClientAuthProvider(), client: client);
    await expectLater(
      api.download('/file', '${dir.path}/file'),
      throwsA(isA<BaiduClientApiException>()),
    );
  });
  test('123 must reject incomplete chunk responses', () async {
    final dir = await Directory.systemTemp.createTemp('pi-123-audit-');
    addTearDown(() => dir.delete(recursive: true));
    const total = 2000000;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('download_info')) {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {'DownloadUrl': 'https://cdn.example/file'},
          }),
          200,
        );
      }
      if (req.headers.containsKey('Range')) {
        return http.Response.bytes([7], 206);
      }
      return http.Response.bytes(List<int>.filled(total, 0), 200);
    });
    final api = Pan123Api(auth: Fake123Auth(), client: client);
    await expectLater(
      api.download(1, '', '', total, 0, '${dir.path}/file'),
      throwsA(isA<Pan123ApiException>()),
    );
  });
  test(
    'Baidu must preserve a pre-existing destination file without overwrite consent',
    () async {
      final dir = await Directory.systemTemp.createTemp('pi-overwrite-audit-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/file');
      await file.writeAsString('original-user-data');
      final client = MockClient((req) async {
        if (req.url.queryParameters['method'] == 'uinfo') {
          return http.Response('{"uk":1}', 200);
        }
        if (req.url.queryParameters['method'] == 'locatedownload') {
          return http.Response(
            '{"urls":[{"encrypt":0,"url":"https://cdn.example/file"}]}',
            200,
          );
        }
        return http.Response.bytes(
          [7],
          206,
          headers: {'content-range': 'bytes 0-0/1'},
        );
      });
      final api = BaiduClientApi(
        auth: BaiduClientAuthProvider(),
        client: client,
      );
      try {
        await api.download('/file', file.path);
      } catch (_) {}
      expect(await file.readAsString(), 'original-user-data');
    },
  );
}
