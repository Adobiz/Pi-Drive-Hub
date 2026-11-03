import 'package:flutter_test/flutter_test.dart';
import 'package:pi_pan/core/state/download_manager.dart';
import 'package:pi_pan/core/state/upload_manager.dart';
import 'package:pi_pan/core/state/transfer_monitor.dart';
import 'release_safety_test.dart' show FakeDrive, tick;

void main() {
  late DownloadManager downloads;
  late UploadManager uploads;
  late FakeDrive drive;
  late DateTime now;
  late TransferMonitor monitor;
  setUp(() {
    downloads = DownloadManager();
    uploads = UploadManager();
    drive = FakeDrive('test');
    now = DateTime(2026, 11, 2);
    monitor = TransferMonitor(
      downloads: downloads,
      uploads: uploads,
      now: () => now,
      startTimer: false,
    );
  });
  tearDown(() => monitor.dispose());

  test(
    'Rates use elapsed time and return to zero when no new bytes arrive',
    () {
      downloads.add(drive, '/file', '/tmp', 'file');
      downloads.tasks.single.received = 8192;
      now = now.add(const Duration(seconds: 2));
      monitor.sample();
      expect(monitor.downloadRate, 4096);
      expect(monitor.downloaded, 8192);
      now = now.add(const Duration(seconds: 1));
      monitor.sample();
      expect(monitor.downloadRate, 0);
      expect(monitor.downloaded, 8192);
    },
  );
  test('Upload and download bytes have independent counters', () {
    downloads.add(drive, '/file', '/tmp', 'file');
    uploads.add(drive, '/tmp/other', '/');
    downloads.tasks.single.received = 2048;
    uploads.tasks.single.sent = 1024;
    now = now.add(const Duration(seconds: 1));
    monitor.sample();
    expect(monitor.snapshot()['downloadRate'], 2048.0);
    expect(monitor.snapshot()['uploadRate'], 1024.0);
  });
  test('Completion and task removal preserve sampled session bytes', () async {
    downloads.add(drive, '/file', '/tmp', 'file');
    final task = downloads.tasks.single;
    task.received = 1000;
    drive.downloads.single.end.complete();
    await tick();
    downloads.remove(task.id);
    now = now.add(const Duration(seconds: 1));
    monitor.sample();
    expect(monitor.downloaded, 1000);
    expect(monitor.downloadRate, 1000);
    expect(monitor.snapshot()['tasks'], isEmpty);
  });
  test(
    'A reset progress counter cannot produce negative speed or a huge spike',
    () {
      uploads.add(drive, '/tmp/file', '/');
      uploads.tasks.single.sent = 2048;
      now = now.add(const Duration(seconds: 1));
      monitor.sample();
      uploads.tasks.single.sent = 0;
      now = now.add(const Duration(seconds: 1));
      monitor.sample();
      expect(monitor.uploadRate, 0);
      uploads.tasks.single.sent = 512;
      now = now.add(const Duration(seconds: 1));
      monitor.sample();
      expect(monitor.uploadRate, 512);
    },
  );
  test(
    'History contains only the rolling last minute, including idle samples',
    () {
      for (var i = 0; i < 90; i++) {
        now = now.add(const Duration(seconds: 1));
        monitor.sample();
      }
      final history = monitor.snapshot()['history'] as List;
      expect(history.length, 61);
      expect(
        (history.first as Map)['time'],
        now.subtract(const Duration(seconds: 60)).millisecondsSinceEpoch,
      );
      expect(history.every((p) => (p as Map)['download'] == 0.0), isTrue);
    },
  );
  test('Attaching to an existing queue establishes a zero-rate baseline', () {
    monitor.dispose();
    downloads.add(drive, '/file', '/tmp', 'file');
    downloads.tasks.single.received = 1000000;
    monitor = TransferMonitor(
      downloads: downloads,
      uploads: uploads,
      now: () => now,
      startTimer: false,
    );
    now = now.add(const Duration(seconds: 1));
    monitor.sample();
    expect(monitor.downloadRate, 0);
    expect(monitor.downloaded, 0);
  });
  test(
    'Dashboard actions pause and resume the correct task without restarting it',
    () {
      downloads.add(drive, '/one', '/tmp', 'one');
      uploads.add(drive, '/tmp/two', '/');
      final id = downloads.tasks.single.id;
      monitor.act('pause', kind: 'download', id: id);
      expect(downloads.tasks.single.status, DownloadStatus.paused);
      expect(uploads.tasks.single.status, UploadStatus.uploading);
      monitor.act('pauseAll');
      expect(uploads.tasks.single.status, UploadStatus.paused);
      monitor.act('resumeAll');
      expect(downloads.tasks.single.status, DownloadStatus.queued);
      expect(uploads.tasks.single.status, UploadStatus.queued);
      expect(drive.downloads.length, 1);
      expect(drive.uploads.length, 1);
    },
  );
  test(
    'Snapshot caps dashboard rows while preserving complete queue counts',
    () {
      for (var i = 0; i < 15; i++) {
        downloads.add(drive, '/$i', '/tmp', '$i');
      }
      final snapshot = monitor.snapshot();
      expect((snapshot['tasks'] as List).length, 12);
      expect(snapshot['active'], 1);
      expect(snapshot['queued'], 14);
    },
  );
}
