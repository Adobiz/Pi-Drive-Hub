import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'download_manager.dart';
import 'upload_manager.dart';

/// A rolling minute of actual transferred bytes, sampled independently of UI.
/// Deltas are captured on every manager notification, including completion and
/// removal, so list changes cannot reset the session totals or invent speed.
class TransferMonitor extends ChangeNotifier {
  final DownloadManager downloads;
  final UploadManager uploads;
  final DateTime Function() _now;
  final Map<String, int> _previous = {};
  final Map<String, int> _pending = {};
  final Map<String, double> _taskRates = {};
  final List<Map<String, Object>> _history = [];
  late DateTime _lastSample;
  Timer? _timer;
  Timer? _publishTimer;
  bool _disposed = false;
  int downloaded = 0;
  int uploaded = 0;
  double downloadRate = 0;
  double uploadRate = 0;

  TransferMonitor({
    required this.downloads,
    required this.uploads,
    DateTime Function()? now,
    bool startTimer = true,
  }) : _now = now ?? DateTime.now {
    _lastSample = _now();
    // Attaching to an existing queue establishes a baseline, not a speed spike.
    _capture(baseline: true);
    downloads.addListener(_changed);
    uploads.addListener(_changed);
    if (startTimer) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => sample());
    }
  }

  void _capture({bool baseline = false}) {
    final current = <String, int>{
      for (final task in downloads.tasks) 'download:${task.id}': task.received,
      for (final task in uploads.tasks) 'upload:${task.id}': task.sent,
    };
    current.forEach((key, bytes) {
      final before = _previous[key] ?? 0;
      final delta = baseline ? 0 : math.max(0, bytes - before);
      if (delta > 0) {
        _pending[key] = (_pending[key] ?? 0) + delta;
        if (key.startsWith('download:')) {
          downloaded += delta;
        } else {
          uploaded += delta;
        }
      }
      _previous[key] = bytes;
    });
    _previous.removeWhere((key, _) => !current.containsKey(key));
  }

  void _changed() {
    _capture();
    // Coalesce chunk callbacks; the one-second sampler owns chart timing.
    _publishTimer ??= Timer(const Duration(milliseconds: 100), () {
      _publishTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void sample() {
    if (_disposed) return;
    _capture();
    final now = _now();
    final seconds = now.difference(_lastSample).inMicroseconds / 1000000;
    if (seconds <= 0) return;
    _lastSample = now;
    var down = 0;
    var up = 0;
    _taskRates.clear();
    _pending.forEach((key, bytes) {
      _taskRates[key] = bytes / seconds;
      if (key.startsWith('download:')) {
        down += bytes;
      } else {
        up += bytes;
      }
    });
    _pending.clear();
    downloadRate = down / seconds;
    uploadRate = up / seconds;
    _history.add({
      'time': now.millisecondsSinceEpoch,
      'download': downloadRate,
      'upload': uploadRate,
    });
    _history.removeWhere(
      (point) =>
          (point['time'] as int) <
          now.subtract(const Duration(seconds: 60)).millisecondsSinceEpoch,
    );
    // Keep storage bounded even if a custom clock samples more than once/sec.
    if (_history.length > 61) _history.removeRange(0, _history.length - 61);
    notifyListeners();
  }

  Map<String, Object> snapshot() {
    final tasks = <Map<String, Object?>>[
      for (final task in downloads.tasks)
        {
          'id': task.id,
          'kind': 'download',
          'name': task.name,
          'provider': task.provider.displayName,
          'status': task.status.name,
          'done': task.received,
          'total': task.total,
          'speed':
              task.status == DownloadStatus.downloading
                  ? (_taskRates['download:${task.id}'] ?? 0)
                  : 0,
        },
      for (final task in uploads.tasks)
        {
          'id': task.id,
          'kind': 'upload',
          'name': task.name,
          'provider': task.provider.displayName,
          'status': task.status.name,
          'done': task.sent,
          'total': task.total,
          'speed':
              task.status == UploadStatus.uploading
                  ? (_taskRates['upload:${task.id}'] ?? 0)
                  : 0,
        },
    ];
    int rank(Map<String, Object?> task) => switch (task['status']) {
      'downloading' || 'uploading' => 0,
      'queued' => 1,
      'paused' => 2,
      'failed' => 3,
      _ => 4,
    };
    tasks.sort((a, b) => rank(a).compareTo(rank(b)));
    int count(Set<String> statuses) =>
        tasks.where((t) => statuses.contains(t['status'])).length;
    final visible = tasks.where((t) => rank(t) < 4).take(12).toList();
    return {
      'timestamp': _lastSample.millisecondsSinceEpoch,
      'downloadRate': downloadRate,
      'uploadRate': uploadRate,
      'downloaded': downloaded,
      'uploaded': uploaded,
      'peak': _history.fold<double>(
        0,
        (peak, p) => math.max(peak, (p['download'] as double)),
      ),
      'active': count({'downloading', 'uploading'}),
      'queued': count({'queued'}),
      'paused': count({'paused'}),
      'failed': count({'failed'}),
      'completed': count({'done'}),
      'tasks': visible,
      'history': List<Map<String, Object>>.of(_history),
    };
  }

  void act(String action, {String? kind, String? id}) {
    if (action == 'pauseAll' || action == 'resumeAll') {
      final resume = action == 'resumeAll';
      for (final task in downloads.tasks.toList()) {
        resume ? downloads.resume(task.id) : downloads.pause(task.id);
      }
      for (final task in uploads.tasks.toList()) {
        resume ? uploads.resume(task.id) : uploads.pause(task.id);
      }
    } else if (id != null && (action == 'pause' || action == 'resume')) {
      if (kind == 'download') {
        action == 'pause' ? downloads.pause(id) : downloads.resume(id);
      } else if (kind == 'upload') {
        action == 'pause' ? uploads.pause(id) : uploads.resume(id);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _publishTimer?.cancel();
    downloads.removeListener(_changed);
    uploads.removeListener(_changed);
    super.dispose();
  }
}
