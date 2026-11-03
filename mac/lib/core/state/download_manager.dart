/// 下载管理器：管理多个下载任务，支持暂停/继续/删除，
/// 并控制同时下载数量（SVIP 可多任务并发，普通账号受限）。
library;

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../providers/cloud_provider.dart';
import '../transfer/download_destination.dart';

enum DownloadStatus { queued, downloading, paused, done, failed, canceled }

class DownloadTask {
  final String id;
  final String remotePath;
  final String name;
  final String localDir;
  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int? total;
  String? error;

  DateTime _lastSample = DateTime.now();
  int _lastBytes = 0;
  double _speedBps = 0;

  /// 断点续传：已完成的分片索引（暂停时保存，继续时跳过）
  Set<int> completedBlocks = {};

  /// 任务代数：每次暂停/继续递增，旧下载线程检测到代数不匹配立即退出，
  /// 防止新旧线程并发下载写同一文件

  late final CloudProvider provider;
  int generation = 0;
  TransferCancellation? cancellation;

  DownloadTask({
    required this.id,
    required this.remotePath,
    required this.name,
    required this.localDir,
  });

  double get speedBps => _speedBps;

  String get speedText {
    if (status != DownloadStatus.downloading) return '';
    final s = _speedBps;
    if (s < 1024) return '${s.toStringAsFixed(0)} B/s';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB/s';
    return '${(s / 1024 / 1024).toStringAsFixed(1)} MB/s';
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
    received = done;
    total = totalBytes;
    return dt >= 200;
  }

  double get progress {
    final t = total;
    if (t == null || t == 0) return 0;
    return (received / t).clamp(0.0, 1.0);
  }

  String get statusText {
    switch (status) {
      case DownloadStatus.queued:
        return '等待中';
      case DownloadStatus.downloading:
        return '下载中 ${_fmt(received)}${total != null ? ' / ${_fmt(total!)}' : ''}';
      case DownloadStatus.paused:
        return '已暂停${received > 0 ? '（${_fmt(received)}）' : ''}';
      case DownloadStatus.done:
        return '已完成';
      case DownloadStatus.failed:
        return '失败: $error';
      case DownloadStatus.canceled:
        return '已取消';
    }
  }

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class DownloadManager extends ChangeNotifier {
  final List<DownloadTask> tasks = [];
  int maxConcurrent = 1;
  final Map<CloudProvider, int> _providerLimits = {};
  final Map<String, CloudProvider> _runningProviders = {};
  final Set<String> _running = {};
  final Map<String, Future<void>> _operations = {};
  int _nextId = 0;

  void setMaxConcurrent(int n) {
    maxConcurrent = n.clamp(1, 8);
    notifyListeners();
    _schedule();
  }

  void applyVipConcurrency(int vipType, {CloudProvider? provider}) {
    final limit = vipType >= 2 ? kSvipMaxConcurrent : kNormalMaxConcurrent;
    if (provider == null) {
      setMaxConcurrent(limit);
      return;
    }
    _providerLimits[provider] = limit;
    setMaxConcurrent(kSvipMaxConcurrent);
  }

  void add(
    CloudProvider provider,
    String remotePath,
    String localDir,
    String name,
  ) {
    final task = DownloadTask(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
      remotePath: remotePath,
      name: name,
      localDir: localDir,
    )..provider = provider;
    tasks.add(task);
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    for (final task in tasks) {
      if (_running.length >= maxConcurrent) break;
      if (task.status != DownloadStatus.queued || _running.contains(task.id)) {
        continue;
      }
      final sameProvider =
          _runningProviders.values
              .where((provider) => identical(provider, task.provider))
              .length;
      if (sameProvider >= (_providerLimits[task.provider] ?? maxConcurrent)) {
        continue;
      }
      _runningProviders[task.id] = task.provider;
      _running.add(task.id);
      _operations[task.id] = _run(task);
    }
  }

  Future<void> _run(DownloadTask task) async {
    final generation = task.generation;
    final cancellation = TransferCancellation();
    task.cancellation = cancellation;
    task.status = DownloadStatus.downloading;
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
      await task.provider.download(
        task.remotePath,
        task.localDir,
        onProgress: progress,
        cancellation: cancellation,
        isCanceled: () => !current(),
        completedBlocks: task.completedBlocks,
        onBlocks: (done, blocks) {
          if (current()) task.completedBlocks = blocks;
        },
      );
      if (current()) task.status = DownloadStatus.done;
    } catch (e) {
      if (current()) {
        task.status = DownloadStatus.failed;
        task.error = '$e';
      }
    } finally {
      cancellation.cancel();
      _running.remove(task.id);
      _runningProviders.remove(task.id);
      _operations.remove(task.id);
      if (!tasks.contains(task)) {
        DownloadDestination.discard(task.completedBlocks);
      }
      notifyListeners();
      _schedule();
    }
  }

  void pause(String id) {
    final task = _byId(id);
    if (task == null ||
        (task.status != DownloadStatus.downloading &&
            task.status != DownloadStatus.queued)) {
      return;
    }
    task.generation++;
    task.cancellation?.cancel();
    task.status = DownloadStatus.paused;
    notifyListeners();
  }

  void resume(String id) {
    final task = _byId(id);
    if (task == null || task.status != DownloadStatus.paused) return;
    task.generation++;
    task.status = DownloadStatus.queued;
    task.error = null;
    notifyListeners();
    _schedule();
  }

  void remove(String id) {
    final task = _byId(id);
    if (task == null) return;
    task.generation++;
    task.cancellation?.cancel();
    task.status = DownloadStatus.canceled;
    tasks.remove(task);
    if (!_running.contains(id)) {
      DownloadDestination.discard(task.completedBlocks);
    }
    notifyListeners();
    _schedule();
  }

  DownloadTask? _byId(String id) {
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
                  t.status == DownloadStatus.done ||
                  t.status == DownloadStatus.failed ||
                  t.status == DownloadStatus.canceled,
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
      task.status = DownloadStatus.canceled;
    }
    for (final task in owned) {
      remove(task.id);
    }
    await Future.wait(pending);
  }

  Future<void> cancelAll() async {
    final pending = _operations.values.toList();
    for (final task in tasks) {
      task.status = DownloadStatus.canceled;
    }
    for (final task in tasks.toList()) {
      remove(task.id);
    }
    await Future.wait(pending);
  }

  /// 任务排序：下载中/排队在前，已完成/失败/暂停沉底
  void sortTasks() {
    int rank(DownloadStatus st) {
      switch (st) {
        case DownloadStatus.downloading:
          return 0;
        case DownloadStatus.queued:
          return 1;
        case DownloadStatus.paused:
          return 2;
        default:
          return 3; // done/failed/canceled
      }
    }

    tasks.sort((a, b) {
      final r = rank(a.status).compareTo(rank(b.status));
      return r != 0 ? r : a.id.compareTo(b.id);
    });
  }
}
