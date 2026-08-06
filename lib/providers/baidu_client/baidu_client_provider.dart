/// 百度网盘客户端协议 Provider：非官方通道，可操作任意目录。
///
/// 与官方 OAuth 通道（BaiduProvider）并存，UI 可选择使用。
library;

import 'dart:io';

import '../../core/constants.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/cloud_file.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cloud_provider.dart';
import 'baidu_client_api.dart';
import 'baidu_client_auth.dart';

class BaiduClientProvider implements CloudProvider {
  final BaiduClientAuthProvider authProvider;
  late final BaiduClientApi api;

  BaiduClientProvider({BaiduClientAuthProvider? auth})
      : authProvider = auth ?? BaiduClientAuthProvider() {
    api = BaiduClientApi(auth: authProvider);
  }

  @override
  String get id => 'baidu_client';

  @override
  String get displayName => '百度网盘';

  @override
  AuthProvider? get auth => authProvider;

  @override
  Future<CloudAccount> getAccountInfo() async {
    // 先拿配额（api/quota）
    final quotaJson = await api.getUserInfo();
    final used = (quotaJson['used'] as num?)?.toInt();
    final total = (quotaJson['total'] as num?)?.toInt();

    // 再拿用户详情（昵称/头像/会员类型）
    String displayName = '百度网盘账号';
    String? avatarUrl;
    int? vipType;
    try {
      final detail = await api.getUserInfoDetail();
      displayName = (detail['netdisk_name'] as String?) ??
          (detail['baidu_name'] as String?) ??
          displayName;
      avatarUrl = detail['avatar_url'] as String?;
      vipType = (detail['vip_type'] as num?)?.toInt();
    } catch (_) {
      // 详情获取失败不阻塞
    }

    // 根据会员类型自动设置下载并发数：
    // SVIP(>=2) 开 8 并发加速，普通账号(0/1) 用 1 并发（避免被限速/封禁）
    api.downloadConcurrency = ((vipType ?? 0) >= 2) ? kSvipMaxConcurrent : kNormalMaxConcurrent;

    return CloudAccount(
      providerId: id,
      displayName: displayName,
      avatarUrl: avatarUrl,
      totalQuota: total,
      usedQuota: used,
      vipType: vipType,
    );
  }

  @override
  Future<List<CloudFile>> list(String path) async {
    final list = await api.listDir(path);
    final files = <CloudFile>[];
    for (final item in list) {
      files.add(_toCloudFile(item));
    }
    files.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return files;
  }

  /// 搜索文件（客户端协议独有能力）
  Future<List<CloudFile>> search(String keyword) async {
    final list = await api.search(keyword);
    return list.map(_toCloudFile).toList();
  }

  @override
  Future<CloudFile> createFolder(String parentPath, String name) async {
    final full = parentPath == '/' ? '/$name' : '$parentPath/$name';
    await api.createFolder(full);
    return CloudFile(path: full, name: name, isDir: true);
  }

  @override
  Future<void> rename(String path, String newName) async {
    // 重命名用独立接口（opera=rename + newname），不是 move
    await api.rename(path, newName);
  }

  @override
  Future<void> delete(String path) async {
    await api.delete([path]);
  }

  /// 批量删除（客户端协议支持一次删除多个）
  Future<void> deleteBatch(List<String> paths) async {
    await api.delete(paths);
  }

  @override
  Future<void> move(String fromPath, String toDir) async {
    final name = fromPath.split('/').last;
    final to = toDir == '/' ? '/$name' : '$toDir/$name';
    await api.move(fromPath, to);
  }

  @override
  Future<void> copy(String fromPath, String toDir) async {
    // 客户端协议复制需要先下载再上传，成本高，暂不支持
    throw UnimplementedError('$displayName 暂不支持复制操作');
  }

  @override
  Future<void> upload(
    String localPath,
    String remoteDir, {
    TransferProgress? onProgress,
  }) async {
    final file = File(localPath);
    final name = file.uri.pathSegments.last;
    final remotePath = remoteDir == '/' ? '/$name' : '$remoteDir/$name';
    final bytes = await file.readAsBytes();
    await api.upload(remotePath, bytes, onProgress: onProgress);
  }

  @override
  Future<void> download(
    String remotePath,
    String localDir, {
    TransferProgress? onProgress,
    bool Function()? isCanceled,
    Set<int>? completedBlocks,
    void Function(int, Set<int>)? onBlocks,
  }) async {
    final name = remotePath.split('/').last;
    final localPath = '$localDir/$name';
    await api.download(remotePath, localPath,
        onProgress: onProgress,
        isCanceled: isCanceled,
        completedBlocks: completedBlocks,
        onBlocks: onBlocks);
  }

  CloudFile _toCloudFile(Map<String, dynamic> item) {
    final path = item['path'] as String? ?? '';
    return CloudFile(
      path: path,
      name: (item['server_filename'] as String?) ?? path.split('/').last,
      isDir: (item['isdir'] as num?) == 1,
      size: (item['size'] as num?)?.toInt(),
      modified: _fromEpoch(item['local_mtime']),
      serverModified: _fromEpoch(item['server_mtime']),
      md5: item['md5'] as String?,
      remoteId: (item['fs_id'] as num?)?.toString(),
      raw: item,
    );
  }

  DateTime? _fromEpoch(Object? epoch) {
    if (epoch == null) return null;
    return DateTime.fromMillisecondsSinceEpoch((epoch as num).toInt() * 1000);
  }
}
