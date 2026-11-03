/// 上传管理器：管理多个上传任务，支持暂停/继续/删除，实时更新进度。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../providers/cloud_provider.dart';

enum UploadStatus { queued, uploading, paused, done, failed, canceled }

class UploadTask {
  final String id;
  final String localPath;
  final String name;
  final String remoteDir;
  UploadStatus status = UploadStatus.queued;
  int sent = 0;
  int? total;
  String? error;

  DateTime _lastSample = DateTime.now();
  int _lastBytes = 0;
  double _speedBps = 0;

  /// 任务代数：暂停/继续递增，防止新旧线程并发

  late final CloudProvider provider;
  int generation = 0;
  TransferCancellation? cancellation;

  UploadTask({
    required this.id,
    required this.localPath,
    required this.name,
    required this.remoteDir,
  });

  double get progress {
    final t = total;
    if (t == null || t == 0) return 0;
    return (sent / t).clamp(0.0, 1.0);
  }

  double get speedBps => _speedBps;

  String get speedText {
    if (status != UploadStatus.uploading) return '';
    final s = _speedBps;
    if (s < 1024) return '${s.toStringAsFixed(0)} B/s';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB/s';
    return '${(s / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  String get statusText {
    switch (status) {
      case UploadStatus.queued:
        return '等待中';
      case UploadStatus.uploading:
        return '上传中 ${_fmt(sent)}${total != null ? ' / ${_fmt(total!)}' : ''}';
      case UploadStatus.paused:
        return '已暂停${sent > 0 ? '（${_fmt(sent)}）' : ''}';
      case UploadStatus.done:
        return '已完成';
      case UploadStatus.failed:
        return '失败: $error';
      case UploadStatus.canceled:
        return '已取消';
    }
  }

  bool updateProgress(int done, int? totalBytes) {
    final now = DateTime.now();
    final dt = now.difference(_lastSample).inMilliseconds;
    final delta = done - _lastBytes;
    if (dt >= 200 && delta >= 0) {
      _speedBps = delta / (dt / 1000.0);
      _lastSample = now;
      _lastBytes = done;
    }
    sent = done;
    total = totalBytes;
    return dt >= 200;
  }

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class UploadManager extends ChangeNotifier {
  final List<UploadTask> tasks = [];
  int maxConcurrent = 3;
  final Set<String> _running = {};
  final Map<String, Future<void>> _operations = {};
  int _nextId = 0;

  void add(CloudProvider provider, String localPath, String remoteDir) {
    final task = UploadTask(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
      localPath: localPath,
      name: File(localPath).uri.pathSegments.last,
      remoteDir: remoteDir,
    )..provider = provider;
    tasks.add(task);
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    for (final task in tasks) {
      if (_running.length >= maxConcurrent) break;
      if (task.status != UploadStatus.queued || _running.contains(task.id)) {
        continue;
      }
      _running.add(task.id);
      _operations[task.id] = _run(task);
    }
  }

  Future<void> _run(UploadTask task) async {
    final generation = task.generation;
    final cancellation = TransferCancellation();
    task.cancellation = cancellation;
    task.status = UploadStatus.uploading;
    bool current() =>
        tasks.contains(task) &&
        task.generation == generation &&
        !cancellation.isCanceled;
    void progress(int done, int? total) {
      if (!current()) throw StateError('传输已取消');
      if (task.updateProgress(done, total)) notifyListeners();
    }

    notifyListeners();
    try {
      await task.provider.upload(
        task.localPath,
        task.remoteDir,
        onProgress: progress,
        cancellation: cancellation,
        isCanceled: () => !current(),
      );
      if (current()) task.status = UploadStatus.done;
    } catch (e) {
      if (current()) {
        task.status = UploadStatus.failed;
        task.error = '$e';
      }
    } finally {
      cancellation.cancel();
      _running.remove(task.id);
      _operations.remove(task.id);
      notifyListeners();
      _schedule();
    }
  }

  void pause(String id) {
    final task = _byId(id);
    if (task == null ||
        (task.status != UploadStatus.uploading &&
            task.status != UploadStatus.queued)) {
      return;
    }
    task.generation++;
    task.cancellation?.cancel();
    task.status = UploadStatus.paused;
    notifyListeners();
  }

  void resume(String id) {
    final task = _byId(id);
    if (task == null || task.status != UploadStatus.paused) return;
    task.generation++;
    task.status = UploadStatus.queued;
    task.error = null;
    task.sent = 0;
    task.total = null;
    notifyListeners();
    _schedule();
  }

  void remove(String id) {
    final task = _byId(id);
    if (task == null) return;
    task.generation++;
    task.cancellation?.cancel();
    task.status = UploadStatus.canceled;
    tasks.remove(task);
    notifyListeners();
    _schedule();
  }

  UploadTask? _byId(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  void clearFinished() {
    final finished =
        tasks
            .where(
              (t) =>
                  t.status == UploadStatus.done ||
                  t.status == UploadStatus.failed ||
                  t.status == UploadStatus.canceled,
            )
            .toList();
    for (final task in finished) {
      remove(task.id);
    }
  }

  Future<void> cancelForProvider(CloudProvider provider) async {
    final owned =
        tasks.where((task) => identical(task.provider, provider)).toList();
    final pending = [
      for (final task in owned)
        if (_operations[task.id] != null) _operations[task.id]!,
    ];
    for (final task in owned) {
      // Mark the whole group before remove() schedules remaining providers.
      task.status = UploadStatus.canceled;
    }
    for (final task in owned) {
      remove(task.id);
    }
    await Future.wait(pending);
  }

  Future<void> cancelAll() async {
    final pending = _operations.values.toList();
    for (final task in tasks) {
      task.status = UploadStatus.canceled;
    }
    for (final task in tasks.toList()) {
      remove(task.id);
    }
    await Future.wait(pending);
  }
}
