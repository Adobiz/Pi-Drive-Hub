import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_pan/core/transfer/range_download.dart';

void main() {
  test(
    'Speed sampling receives progress inside a chunk, before the whole block is written',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pi-live-progress-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/part').create();
      final progress = <int>[];
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          206,
          contentLength: 4,
          headers: {'content-range': 'bytes 0-3/4'},
        ),
      );
      await downloadRanges(
        client: client,
        uri: Uri.parse('https://cdn.example/file'),
        headers: (_) => {},
        file: file,
        total: 4,
        blocks: {},
        invalid: StateError.new,
        onProgress: (bytes, _) => progress.add(bytes),
      );
      expect(progress, contains(2));
      expect(progress.last, 4);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
    },
  );
}
