/// 下载管理器：管理多个下载任务，支持暂停/继续/删除，
/// 并控制同时下载数量（SVIP 可多任务并发，普通账号受限）。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../providers/cloud_provider.dart';

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

  /// 当前使用的 Provider（add 时记录，供 resume/pause 调度用）
  CloudProvider? _provider;

  /// 同时下载的任务数量上限（SVIP 可调大，普通账号受限）
  int maxConcurrent = 1;

  /// 设置并发上限并立即重新调度（UI 加减按钮调用）
  void setMaxConcurrent(int n) {
    maxConcurrent = n < 1 ? 1 : n;
    notifyListeners();
    _schedule();
  }

  /// 根据账号类型设置并发上限：
  /// - SVIP(vipType>=2)：最多 8 个任务同时下载
  /// - 普通账号：最多 1 个
  void applyVipConcurrency(int vipType) {
    setMaxConcurrent((vipType >= 2) ? kSvipMaxConcurrent : kNormalMaxConcurrent);
  }

  int _activeCount = 0;
  final Set<String> _canceledIds = {};
  final Map<String, int> _generations = {};

  /// 添加下载任务（进入排队，由 [_schedule] 决定何时开始）
  void add(CloudProvider provider, String remotePath, String localDir, String name) {
    _provider = provider;
    _justPausedId = null;
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      remotePath: remotePath,
      name: name,
      localDir: localDir,
    );
    _generations[task.id] = 0;
    // 新任务追加到列表末尾（最新任务在下方），
    // 避免批量下载时先添加的文件沉底、下载完成后无法暂停的困惑
    tasks.add(task);
    notifyListeners();
    _schedule();
  }

  /// 调度：在并发上限内启动排队中的任务。
  /// 没有排队任务时，自动恢复暂停的任务（跳过刚被暂停的那个），
  /// 保证下载队列持续推进。
  void _schedule() {
    final provider = _provider;
    if (provider == null) return;
    while (_activeCount < maxConcurrent) {
      DownloadTask? next;
      // 优先取排队中的任务
      for (final t in tasks) {
        if (t.status == DownloadStatus.queued) {
          next = t;
          break;
        }
      }
      // 没有排队任务时，自动恢复暂停的任务（跳过刚暂停的）
      if (next == null) {
        for (final t in tasks) {
          if (t.status == DownloadStatus.paused && t.id != _justPausedId) {
            _canceledIds.remove(t.id);
            t.status = DownloadStatus.queued;
            next = t;
            break;
          }
        }
      }
      if (next == null) break;
      _activeCount++;
      _run(provider, next);
    }
  }

  /// 刚被暂停的任务 id（暂停时记录，调度时跳过它，避免暂停立即失效）
  String? _justPausedId;

  Future<void> _run(CloudProvider provider, DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    // 本线程捕获自己的代数快照（局部变量，不受共享 task 对象影响）
    final myGeneration = _generations[task.id] ?? 0;
    notifyListeners();
    try {
      await provider.download(
        task.remotePath,
        task.localDir,
        onProgress: (done, total) {
          // 节流：chunk 级回调很频繁，仅每 200ms 刷新一次 UI
          if (task.updateProgress(done, total)) {
            notifyListeners();
          }
        },
        isCanceled: () =>
            _canceledIds.contains(task.id) ||
            _generations[task.id] != myGeneration,
        completedBlocks: task.completedBlocks,
        onBlocks: (done, blocks) {
          task.completedBlocks = blocks;
        },
      );
      if (task.status != DownloadStatus.paused &&
          task.status != DownloadStatus.canceled) {
        task.status = DownloadStatus.done;
      }
    } catch (e) {
      // 代数已过期：此线程是被暂停/继续淘汰的旧线程，
      // 不标记失败（任务状态已由 resume 改为 queued/新线程接管）
      if (_generations[task.id] != myGeneration) {
        // 旧线程让位，忽略其取消异常
      } else if (task.status == DownloadStatus.paused) {
        // 暂停中断，保持暂停状态
      } else if (task.status != DownloadStatus.canceled) {
        task.status = DownloadStatus.failed;
        task.error = '$e';
      }
    }
    // 无论任务最终状态（含暂停），线程退出即释放槽位；
    // 只有旧线程真正退出后才调度下一个，避免新旧线程并发写同一文件
    _activeCount--;
    notifyListeners();
    _schedule();
  }

  /// 暂停任务：立即释放并发槽位，让下一个排队任务开始
  void pause(String id) {
    final t = _byId(id);
    if (t == null) return;
    final wasRunning = t.status == DownloadStatus.downloading;
    _generations[id] = (_generations[id] ?? 0) + 1; // 旧线程代数失效，立即中断
    _canceledIds.add(id); // 下载线程检测到后自行退出
    if (wasRunning || t.status == DownloadStatus.queued) {
      t.status = DownloadStatus.paused;
    }
    _justPausedId = id;
    // 注意：不立即让出槽位/调度——旧下载线程退出后（_run 收尾）才释放，
    // 确保同一任务同时只有一个下载线程在写文件
    notifyListeners();
  }

  /// 继续任务（断点续传：保留已完成分片）
  void resume(String id) {
    final t = _byId(id);
    if (t == null || t.status != DownloadStatus.paused) return;
    _canceledIds.remove(id);
    _generations[id] = (_generations[id] ?? 0) + 1; // 新线程新代数
    t.status = DownloadStatus.queued;
    t.error = null;
    _justPausedId = null;
    notifyListeners();
    _schedule();
  }

  /// 删除任务（中断并移除，同时清理本地半成品文件）
  void remove(String id) {
    final t = _byId(id);
    if (t == null) return;
    final wasRunning = t.status == DownloadStatus.downloading;
    _canceledIds.add(id); // 中断进行中的下载
    tasks.remove(t);
    if (wasRunning) {
      _activeCount--;
    }
    _cleanupLocalFile(t);
    notifyListeners();
    _schedule();
  }

  void _cleanupLocalFile(DownloadTask t) {
    // 已完成的保留，避免误删；半成品删除
    if (t.status == DownloadStatus.done) return;
    try {
      final f = File('${t.localDir}/${t.name}');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  DownloadTask? _byId(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
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

  /// 清除已完成/失败/取消的任务
  void clearFinished() {
    tasks.removeWhere((t) =>
        t.status == DownloadStatus.done ||
        t.status == DownloadStatus.failed ||
        t.status == DownloadStatus.canceled);
    notifyListeners();
  }

  /// 取消所有正在进行的任务并清空列表（切换账号时调用）
  void cancelAll() {
    for (final t in tasks) {
      if (t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued ||
          t.status == DownloadStatus.paused) {
        _canceledIds.add(t.id);
      }
    }
    tasks.clear();
    _activeCount = 0;
    notifyListeners();
  }
}
