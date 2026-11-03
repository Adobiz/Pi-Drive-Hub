import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_pan/core/transfer/range_download.dart';

void main() {
  test(
    'A transient CDN error retries a range and writes only verified bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('pi-range-retry-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File('${dir.path}/part').create();
      var attempts = 0;
      final client = MockClient((request) async {
        if (++attempts == 1) {
          return http.Response('unavailable', 503);
        }
        return http.Response.bytes(
          [1, 2, 3, 4],
          206,
          headers: {'content-range': 'bytes 0-3/4'},
        );
      });
      await downloadRanges(
        client: client,
        uri: Uri.parse('https://cdn.example/file'),
        headers: (_) => {},
        file: file,
        total: 4,
        blocks: {},
        invalid: StateError.new,
      );
      expect(attempts, 2);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
    },
  );
  test(
    'Empty-file range probe accepts a zero-length range rejection',
    () async {
      final client = MockClient(
        (_) async =>
            http.Response('', 416, headers: {'content-range': 'bytes */0'}),
      );
      expect(
        await probeDownloadSize(
          client,
          Uri.parse('https://cdn.example/empty'),
          (_) => {},
        ),
        0,
      );
    },
  );
  test(
    'Download redirects reject insecure targets before contacting them',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(
          '',
          302,
          headers: {'location': 'http://unrelated.example/file'},
        );
      });
      await expectLater(
        downloadRequest(
          client,
          Uri.parse('https://cdn.example/file'),
          (_) => {},
        ),
        throwsStateError,
      );
      expect(requests, 1);
    },
  );
}
