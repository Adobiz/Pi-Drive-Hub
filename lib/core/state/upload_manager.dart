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

  /// 当前使用的 Provider
  CloudProvider? _provider;

  /// 同时上传的任务数量上限（默认 3，上传并发限制较宽松）
  int maxConcurrent = 3;

  String? _justPausedId;

  int _activeCount = 0;
  final Set<String> _canceledIds = {};
  final Map<String, int> _generations = {};

  /// 添加任务（进入排队）
  void add(CloudProvider provider, String localPath, String remoteDir) {
    _provider = provider;
    _justPausedId = null;
    // 兼容 Windows/Unix 路径分隔符（split r'[\/]' 只匹配 /，Windows \ 会取到完整路径）
    final name = File(localPath).uri.pathSegments.last;
    final task = UploadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      localPath: localPath,
      name: name,
      remoteDir: remoteDir,
    );
    _generations[task.id] = 0;
    tasks.add(task);
    notifyListeners();
    _schedule(provider);
  }

  void _schedule([CloudProvider? provider]) {
    final p = provider ?? _provider;
    if (p == null) return;
    while (_activeCount < maxConcurrent) {
      UploadTask? next;
      for (final t in tasks) {
        if (t.status == UploadStatus.queued) {
          next = t;
          break;
        }
      }
      // 没有排队任务时，自动恢复暂停的任务（跳过刚暂停的）
      if (next == null) {
        for (final t in tasks) {
          if (t.status == UploadStatus.paused && t.id != _justPausedId) {
            _canceledIds.remove(t.id);
            t.status = UploadStatus.queued;
            next = t;
            break;
          }
        }
      }
      if (next == null) break;
      _activeCount++;
      _run(p, next);
    }
  }

  Future<void> _run(CloudProvider provider, UploadTask task) async {
    task.status = UploadStatus.uploading;
    // 本线程捕获自己的代数快照（局部变量，不受共享 task 对象影响）
    final myGeneration = _generations[task.id] ?? 0;
    notifyListeners();
    try {
      await provider.upload(
        task.localPath,
        task.remoteDir,
        onProgress: (done, total) {
          if (task.updateProgress(done, total)) {
            notifyListeners();
          }
          // 代数变化（暂停/继续）时中止上传，防止新旧线程并发
          if (_generations[task.id] != myGeneration) {
            throw StateError('上传已中断');
          }
        },
      );
      if (task.status != UploadStatus.paused &&
          task.status != UploadStatus.canceled) {
        task.status = UploadStatus.done;
      }
    } catch (e) {
      // 代数已过期：旧线程被暂停/继续淘汰，不标记失败
      if (_generations[task.id] != myGeneration) {
        // 旧线程让位，忽略
      } else if (task.status == UploadStatus.paused) {
        // 保持暂停
      } else if (task.status != UploadStatus.canceled) {
        task.status = UploadStatus.failed;
        task.error = '$e';
      }
    }
    _activeCount--;
    notifyListeners();
    _schedule(provider);
  }

  /// 暂停任务：立即释放槽位，让下一个排队任务开始
  void pause(String id) {
    final t = _byId(id);
    if (t == null) return;
    final wasRunning = t.status == UploadStatus.uploading;
    _generations[id] = (_generations[id] ?? 0) + 1;
    _canceledIds.add(id); // 标记中断
    if (wasRunning || t.status == UploadStatus.queued) {
      t.status = UploadStatus.paused;
    }
    _justPausedId = id;
    // 上传中的任务：不立即让槽位，旧线程退出后（_run 收尾）释放并调度
    // 排队中的任务：不占槽位，触发一次调度让其他排队任务有机会启动
    if (!wasRunning) {
      _schedule();
    }
    notifyListeners();
  }

  /// 继续任务（重新开始上传）
  void resume(String id) {
    final t = _byId(id);
    if (t == null || t.status != UploadStatus.paused) return;
    _canceledIds.remove(id);
    _generations[id] = (_generations[id] ?? 0) + 1;
    t.status = UploadStatus.queued;
    t.error = null;
    t.sent = 0;
    t.total = null;
    _justPausedId = null;
    notifyListeners();
    _schedule();
  }

  /// 删除任务
  void remove(String id) {
    final t = _byId(id);
    if (t == null) return;
    _canceledIds.add(id);
    tasks.remove(t);
    notifyListeners();
  }

  UploadTask? _byId(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void clearFinished() {
    tasks.removeWhere((t) =>
        t.status == UploadStatus.done || t.status == UploadStatus.failed);
    notifyListeners();
  }

  /// 取消所有任务并清空列表（切换账号时调用）
  void cancelAll() {
    for (final t in tasks) {
      if (t.status == UploadStatus.uploading ||
          t.status == UploadStatus.queued ||
          t.status == UploadStatus.paused) {
        _canceledIds.add(t.id);
      }
    }
    tasks.clear();
    _activeCount = 0;
    notifyListeners();
  }
}
