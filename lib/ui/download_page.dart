/// 传输管理页面：下载/上传任务的实时进度、暂停/继续/删除、
/// 以及同时下载数量设置（按账号权限）。
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/i18n/strings.dart';
import '../core/providers/cloud_provider.dart';
import '../core/state/download_manager.dart';
import '../core/state/upload_manager.dart';

class DownloadPage extends StatefulWidget {
  final DownloadManager manager;
  final UploadManager uploadManager;
  final CloudProvider provider;
  final int vipType;

  const DownloadPage({
    super.key,
    required this.manager,
    required this.uploadManager,
    required this.provider,
    required this.vipType,
  });

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('传输管理'),
          actions: [
            TextButton(
              onPressed: _tab == 0
                  ? widget.manager.clearFinished
                  : widget.uploadManager.clearFinished,
              child: Text(AppStrings.clearFinished),
            ),
          ],
          bottom: TabBar(
            onTap: (i) => setState(() => _tab = i),
            tabs: [
              Tab(text: AppStrings.tabDownload),
              Tab(text: AppStrings.tabUpload),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_tab == 0) _buildConcurrencyBar(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildDownloadList(),
                  _buildUploadList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右上角「同时下载数量」设置（按账号权限）
  Widget _buildConcurrencyBar() {
    final vip = widget.vipType;
    final maxAllowed = (vip >= 2) ? kSvipMaxConcurrent : kNormalMaxConcurrent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(AppStrings.concurrentCount, style: TextStyle(fontSize: 13)),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: widget.manager.maxConcurrent > 1
                ? () => widget.manager.setMaxConcurrent(widget.manager.maxConcurrent - 1)
                : null,
          ),
          Text('${widget.manager.maxConcurrent}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: widget.manager.maxConcurrent < maxAllowed
                ? () => widget.manager.setMaxConcurrent(widget.manager.maxConcurrent + 1)
                : null,
          ),
          const Spacer(),
          Text(
            vip >= 2 ? AppStrings.svipConcurrent : AppStrings.normalConcurrent,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadList() {
    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        if (widget.manager.tasks.isEmpty) {
          return Center(
              child: Text(AppStrings.noDownloadTasks, style: TextStyle(color: Colors.grey)));
        }
        // 排序：下载中/排队在前，已完成/失败沉底，方便操作
        widget.manager.sortTasks();
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: widget.manager.tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final task = widget.manager.tasks[i];
            return _TaskCard(
              task: task,
              onPauseResume: () {
                if (task.status == DownloadStatus.paused) {
                  widget.manager.resume(task.id);
                } else {
                  widget.manager.pause(task.id);
                }
              },
              onDelete: () => widget.manager.remove(task.id),
            );
          },
        );
      },
    );
  }

  Widget _buildUploadList() {
    return ListenableBuilder(
      listenable: widget.uploadManager,
      builder: (context, _) {
        if (widget.uploadManager.tasks.isEmpty) {
          return Center(
              child: Text(AppStrings.noUploadTasks, style: TextStyle(color: Colors.grey)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: widget.uploadManager.tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final task = widget.uploadManager.tasks[i];
            return _UploadCard(
              task: task,
              onPauseResume: () {
                if (task.status == UploadStatus.paused) {
                  widget.uploadManager.resume(task.id);
                } else {
                  widget.uploadManager.pause(task.id);
                }
              },
              onDelete: () => widget.uploadManager.remove(task.id),
            );
          },
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPauseResume;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onPauseResume,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final done = task.status == DownloadStatus.done;
    final failed = task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.canceled;
    final paused = task.status == DownloadStatus.paused;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done
                      ? Icons.check_circle
                      : (failed
                          ? Icons.error
                          : (paused ? Icons.pause_circle : Icons.downloading)),
                  color: done
                      ? Colors.green
                      : (failed
                          ? Colors.red
                          : (paused ? Colors.orange : kBrandColor)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                // 暂停/继续按钮
                if (!done && !failed)
                  IconButton(
                    tooltip: paused ? AppStrings.resume : AppStrings.pause,
                    icon: Icon(
                      paused ? Icons.play_arrow : Icons.pause,
                      size: 20,
                    ),
                    onPressed: onPauseResume,
                  ),
                // 删除按钮
                IconButton(
                  tooltip: AppStrings.delete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (task.status == DownloadStatus.downloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 6,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.statusText,
                    style: TextStyle(
                      fontSize: 13,
                      color: failed ? Colors.red : Colors.grey,
                    ),
                  ),
                ),
                if (task.status == DownloadStatus.downloading &&
                    task.speedText.isNotEmpty)
                  Text(
                    task.speedText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: kBrandColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  final UploadTask task;
  final VoidCallback onPauseResume;
  final VoidCallback onDelete;

  const _UploadCard({
    required this.task,
    required this.onPauseResume,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final done = task.status == UploadStatus.done;
    final failed = task.status == UploadStatus.failed ||
        task.status == UploadStatus.canceled;
    final paused = task.status == UploadStatus.paused;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done
                      ? Icons.check_circle
                      : (failed
                          ? Icons.error
                          : (paused ? Icons.pause_circle : Icons.upload)),
                  color: done
                      ? Colors.green
                      : (failed
                          ? Colors.red
                          : (paused ? Colors.orange : kBrandColor)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (!done && !failed)
                  IconButton(
                    tooltip: paused ? AppStrings.resume : AppStrings.pause,
                    icon: Icon(
                      paused ? Icons.play_arrow : Icons.pause,
                      size: 20,
                    ),
                    onPressed: onPauseResume,
                  ),
                IconButton(
                  tooltip: AppStrings.delete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (task.status == UploadStatus.uploading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 6,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.statusText,
                    style: TextStyle(
                      fontSize: 13,
                      color: failed ? Colors.red : Colors.grey,
                    ),
                  ),
                ),
                if (task.status == UploadStatus.uploading &&
                    task.speedText.isNotEmpty)
                  Text(
                    task.speedText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: kBrandColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
