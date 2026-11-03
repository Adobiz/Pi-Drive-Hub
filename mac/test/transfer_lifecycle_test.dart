import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_pan/core/state/download_manager.dart';
import 'package:pi_pan/core/state/upload_manager.dart';
import 'package:pi_pan/core/transfer/cancellation.dart';
import 'package:pi_pan/core/transfer/download_destination.dart';
import 'package:pi_pan/core/transfer/range_download.dart';
import 'package:pi_pan/providers/baidu_client/cookie_jar.dart';
import 'package:pi_pan/providers/pan123/pan123_provider.dart';
import 'package:pi_pan/providers/quark/quark_api.dart';
import 'package:pi_pan/providers/quark/quark_auth.dart';
import 'release_safety_test.dart'
    show FakeDrive, Fake123Auth, tick, validBaiduApi;

class AbortingTransport extends http.BaseClient {
  final entered = Completer<void>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request, isA<http.Abortable>());
    entered.complete();
    await (request as http.Abortable).abortTrigger;
    throw http.RequestAbortedException(request.url);
  }

  @override
  void close() {}
}

void main() {
  test(
    'Cancellation survives nested clients and aborts an in-flight request',
    () async {
      final transport = AbortingTransport();
      final token = TransferCancellation();
      final client = TransferClient(
        TransferClient(TransferClient(transport), token),
      );
      final request = client.get(Uri.parse('https://example.com'));
      final assertion = expectLater(
        request,
        throwsA(isA<http.RequestAbortedException>()),
      );
      await transport.entered.future;
      token.cancel();
      await assertion;
    },
  );
  test(
    'Multipart proxy preserves body, boundary, and content length',
    () async {
      final transport = MockClient((request) async {
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );
        expect(request.body, contains('sample-data'));
        expect(request.body, contains('name="file"'));
        expect(request.contentLength, request.bodyBytes.length);
        return http.Response('ok', 200);
      });
      final client = TransferClient(
        TransferClient(transport),
        TransferCancellation(),
      );
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://example.com'),
      )..files.add(http.MultipartFile.fromString('file', 'sample-data'));
      expect((await client.send(request)).statusCode, 200);
    },
  );
  test('Legacy cookie migration is scoped to the service and HTTPS', () {
    final jar = CookieJar(origin: Uri.parse('https://baidu.com'))
      ..loadMap({'BDUSS': 'fake'});
    expect(jar.headerFor(Uri.parse('https://pan.baidu.com/')), 'BDUSS=fake');
    expect(jar.headerFor(Uri.parse('https://baidu.com.evil.test/')), '');
    expect(jar.headerFor(Uri.parse('http://pan.baidu.com/')), '');
  });
  test(
    'Restored cookies retain host-only, path, and expiration restrictions',
    () {
      final jar = CookieJar(origin: Uri.parse('https://quark.cn'));
      jar.setCookies([
        'session=fake; Path=/api; Secure; Max-Age=3600',
      ], responseOrigin: Uri.parse('https://pan.quark.cn/api/login'));
      final restored = CookieJar(origin: Uri.parse('https://quark.cn'))
        ..loadMap(jar.toMap());
      expect(
        restored.headerFor(Uri.parse('https://pan.quark.cn/api/file')),
        'session=fake',
      );
      expect(restored.headerFor(Uri.parse('https://pan.quark.cn/apix')), '');
      expect(
        restored.headerFor(Uri.parse('https://drive.quark.cn/api/file')),
        '',
      );
      jar.setCookies([
        'session=gone; Path=/api; Max-Age=0',
      ], responseOrigin: Uri.parse('https://pan.quark.cn/api/login'));
      expect(jar.headerFor(Uri.parse('https://pan.quark.cn/api/file')), '');
    },
  );
  test(
    'Download redirect rebuilds cookies and never forwards them to unrelated hosts',
    () async {
      final jar = CookieJar(origin: Uri.parse('https://baidu.com'))
        ..loadMap({'BDUSS': 'fake'});
      final seen = <String>[];
      final client = TransferClient(
        MockClient((request) async {
          seen.add(request.headers['cookie'] ?? '');
          if (request.url.host == 'pan.baidu.com') {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://unrelated.example/file'},
            );
          }
          return http.Response('ok', 200);
        }),
      );
      final result = await downloadRequest(
        client,
        Uri.parse('https://pan.baidu.com/file'),
        (uri) => {'Cookie': jar.headerFor(uri)},
      );
      await closeResponse(result.response);
      expect(seen, ['BDUSS=fake', '']);
    },
  );
  test('Canceled tasks do not delete an existing user file', () async {
    final dir = await Directory.systemTemp.createTemp('pi-existing-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/file')..writeAsStringSync('keep');
    final drive = FakeDrive('a');
    final manager = DownloadManager();
    manager.add(drive, '/file', dir.path, 'file');
    manager.remove(manager.tasks.single.id);
    drive.downloads.single.end.complete();
    await tick();
    expect(file.readAsStringSync(), 'keep');
  });
  test(
    'Pause/resume waits for the old operation even when extra slots are available',
    () async {
      final drive = FakeDrive('a');
      final manager = UploadManager()..maxConcurrent = 3;
      manager.add(drive, '/file', '/');
      final task = manager.tasks.single;
      manager.pause(task.id);
      manager.resume(task.id);
      expect(drive.uploads.length, 1);
      expect(() => drive.uploads.first.progress!(1, 2), throwsStateError);
      drive.uploads.first.end.complete();
      await tick();
      expect(drive.uploads.length, 2);
      manager.pause(task.id);
      drive.uploads.last.end.complete();
      await tick();
    },
  );
  test('Paused uploads stay paused when another upload finishes', () async {
    final drive = FakeDrive('a');
    final manager = UploadManager()..maxConcurrent = 2;
    manager.add(drive, '/a', '/');
    await tick();
    manager.add(drive, '/b', '/');
    manager.pause(manager.tasks.first.id);
    drive.uploads.first.end.complete();
    drive.uploads.last.end.complete();
    await tick();
    expect(drive.uploads.length, 2);
    expect(manager.tasks.first.status, UploadStatus.paused);
  });
  test(
    'Exclusive publication preserves a file created while downloading',
    () async {
      final dir = await Directory.systemTemp.createTemp('pi-final-race-');
      addTearDown(() => dir.delete(recursive: true));
      final blocks = <int>{};
      final target = await DownloadDestination.open('${dir.path}/file', blocks);
      await target.partial.writeAsString('new');
      await target.destination.writeAsString('user');
      expect(target.complete, throwsA(isA<FileSystemException>()));
      expect(await target.destination.readAsString(), 'user');
      DownloadDestination.discard(blocks);
    },
  );
  test(
    'Interrupted download resumes from its private partial file with valid bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('pi-resume-');
      addTearDown(() => dir.delete(recursive: true));
      final content = List<int>.generate(800000, (i) => (i ~/ 262144) + 1);
      final blocks = <int>{};
      var canceled = false;
      await expectLater(
        validBaiduApi(content).download(
          '/file',
          '${dir.path}/file',
          completedBlocks: blocks,
          isCanceled: () => canceled,
          onBlocks: (_, _) {
            canceled = true;
          },
        ),
        throwsStateError,
      );
      expect(blocks, {0});
      expect(File('${dir.path}/file').existsSync(), false);
      await validBaiduApi(
        content,
      ).download('/file', '${dir.path}/file', completedBlocks: blocks);
      expect(await File('${dir.path}/file').readAsBytes(), content);
      expect(await dir.list().length, 1);
    },
  );
  test(
    '123 search operations use hit IDs even with equal names in different directories',
    () async {
      final deleted = <int>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/file/trash')) {
          final body = jsonDecode(request.body) as Map;
          deleted.add(
            (body['fileTrashInfoList'] as List).single['FileId'] as int,
          );
          return http.Response('{"code":0}', 200);
        }
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'InfoList': [
                {'FileId': 11, 'FileName': 'same', 'Type': 0},
                {'FileId': 22, 'FileName': 'same', 'Type': 0},
              ],
            },
          }),
          200,
        );
      });
      final provider = Pan123Provider(auth: Fake123Auth(), client: client);
      final hits = await provider.search('same');
      expect(hits.map((f) => f.path).toSet().length, 2);
      await provider.delete(hits[0].path);
      await provider.delete(hits[1].path);
      expect(deleted, [11, 22]);
      provider.clearSession();
      await expectLater(provider.delete(hits[0].path), throwsStateError);
    },
  );
  test('Quark rejects a bad range without publishing a final file', () async {
    final dir = await Directory.systemTemp.createTemp('pi-quark-range-');
    addTearDown(() => dir.delete(recursive: true));
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/file/download')) {
        return http.Response(
          '{"code":0,"data":[{"download_url":"https://cdn.example/file"}]}',
          200,
        );
      }
      if (request.headers['Range'] == 'bytes=0-0') {
        return http.Response.bytes(
          [0],
          206,
          headers: {'content-range': 'bytes 0-0/100'},
        );
      }
      return http.Response.bytes(
        [1],
        206,
        headers: {'content-range': 'bytes 0-0/100'},
      );
    });
    final api = QuarkApi(auth: QuarkAuthProvider(), client: client);
    await expectLater(
      api.download('fid', '${dir.path}/file'),
      throwsA(isA<QuarkApiException>()),
    );
    expect(File('${dir.path}/file').existsSync(), false);
    expect(await dir.list().length, 0);
  });
}
