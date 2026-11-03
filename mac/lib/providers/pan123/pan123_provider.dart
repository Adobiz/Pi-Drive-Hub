/// 123 云盘 Provider：账号密码登录 + 私有 API 操作。
library;

import 'package:http/http.dart' as http;
import '../../core/models/cloud_account.dart';
import '../../core/models/cloud_file.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cloud_provider.dart';
import 'pan123_api.dart';
import 'pan123_auth.dart';

class Pan123Provider implements CloudProvider {
  final Pan123AuthProvider authProvider;
  late final Pan123Api api;

  /// 根目录 fileId（123 根目录为 0）
  static const int rootFileId = 0;

  /// 路径 → fileId 缓存
  final Map<String, int> _fileIdCache = {'/': rootFileId};

  /// 路径 → 文件元信息（etag/s3keyFlag/size/type）
  final Map<String, Pan123File> _metaCache = {};

  Pan123Provider({Pan123AuthProvider? auth, http.Client? client})
    : authProvider = auth ?? Pan123AuthProvider() {
    api = Pan123Api(auth: authProvider, client: client);
  }

  @override
  void clearSession() {
    _fileIdCache.clear();
    _fileIdCache['/'] = rootFileId;
    _metaCache.clear();
  }

  @override
  String get id => 'pan123';

  @override
  String get displayName => '123云盘';

  @override
  AuthProvider? get auth => authProvider;

  @override
  Future<CloudAccount> getAccountInfo() async {
    final info = await api.getUserInfo();
    // 123 容量/会员字段（帕斯卡命名）：SpaceUsed/SpacePermanent/Vip/VipLevel
    final used = (info['SpaceUsed'] as num?)?.toInt();
    final total = (info['SpacePermanent'] as num?)?.toInt();
    final isVip = (info['Vip'] as bool?) ?? false;
    final vipLevel = (info['VipLevel'] as num?)?.toInt() ?? 0;
    return CloudAccount(
      providerId: id,
      displayName:
          (info['NickName'] as String?) ??
          (info['Nickname'] as String?) ??
          '123云盘用户',
      avatarUrl: info['Avatar'] as String?,
      totalQuota: total,
      usedQuota: used,
      // vipType 约定：0=普通, 1=会员, 2=超级会员；123 用 Vip+VipLevel
      vipType: isVip ? (vipLevel > 1 ? 2 : 1) : 0,
    );
  }

  @override
  Future<List<CloudFile>> list(String path) async {
    final parentId = await _resolveFileId(path);
    final files = await api.listDir(parentId);
    final parent = path == '/' ? '' : path;
    // 缓存目录的 fileId
    for (final f in files) {
      final p = parent.isEmpty ? '/${f.name}' : '$parent/${f.name}';
      _fileIdCache[p] = f.fileId;
      _metaCache[p] = f;
    }
    return files.map((f) => _toCloudFile(f, parent)).toList();
  }

  /// 搜索文件
  Future<List<CloudFile>> search(String keyword) async {
    final list = await api.search(keyword);
    return list.map((f) {
      final key = 'pi-search://${f.fileId}/${f.name}';
      _fileIdCache[key] = f.fileId;
      _metaCache[key] = f;
      return _toCloudFile(f, '', pathOverride: key);
    }).toList();
  }

  @override
  Future<CloudFile> createFolder(String parentPath, String name) async {
    final parentId = await _resolveFileId(parentPath);
    await api.createFolder(parentId, name);
    final full = parentPath == '/' ? '/$name' : '$parentPath/$name';
    _fileIdCache.removeWhere((k, _) => k.startsWith(full));
    _metaCache.remove(full);
    return CloudFile(path: full, name: name, isDir: true, remoteId: full);
  }

  @override
  Future<void> rename(String path, String newName) async {
    final fileId = await _resolveFileId(path);
    await api.rename(fileId, newName);
    _invalidate(fileId);
  }

  @override
  Future<void> delete(String path) async {
    await _resolveFileId(path);
    final meta = _metaCache[path];
    if (meta == null) {
      throw Pan123ApiException(-1, '无法获取文件信息: $path');
    }
    await api.delete([meta]);
    _invalidate(meta.fileId);
  }

  @override
  Future<void> move(String fromPath, String toDir) async {
    final fileId = await _resolveFileId(fromPath);
    final toId = await _resolveFileId(toDir);
    await api.move(fileId, toId);
    _invalidate(fileId);
  }

  @override
  Future<void> copy(String fromPath, String toDir) {
    throw UnimplementedError('$displayName 暂不支持复制操作');
  }

  @override
  Future<void> upload(
    String localPath,
    String remoteDir, {
    TransferProgress? onProgress,
    TransferCancellation? cancellation,
    bool Function()? isCanceled,
  }) async {
    final dirId = await _resolveFileId(remoteDir);
    await api
        .forTransfer(cancellation)
        .upload(
          localPath,
          dirId,
          onProgress: onProgress,
          isCanceled: isCanceled,
        );
  }

  @override
  Future<void> download(
    String remotePath,
    String localDir, {
    TransferProgress? onProgress,
    TransferCancellation? cancellation,
    bool Function()? isCanceled,
    Set<int>? completedBlocks,
    void Function(int, Set<int>)? onBlocks,
  }) async {
    await _resolveFileId(remotePath);
    final meta = _metaCache[remotePath];
    if (meta == null) {
      // 元信息缺失：尝试从父目录列表解析
      final parent = remotePath.substring(0, remotePath.lastIndexOf('/'));
      final parentId = await _resolveFileId(parent);
      final files = await api.listDir(parentId);
      for (final f in files) {
        final p = parent == '/' ? '/${f.name}' : '$parent/${f.name}';
        _fileIdCache[p] = f.fileId;
        _metaCache[p] = f;
      }
    }
    final m = _metaCache[remotePath];
    if (m == null || m.isDir) {
      throw Pan123ApiException(-1, '无法获取文件信息: $remotePath');
    }
    final name = m.name;
    await api
        .forTransfer(cancellation)
        .download(
          m.fileId,
          m.etag,
          m.s3KeyFlag,
          m.size,
          m.type,
          '$localDir/$name',
          onProgress: onProgress,
          isCanceled: isCanceled,
          completedBlocks: completedBlocks,
          onBlocks: onBlocks,
        );
  }

  CloudFile _toCloudFile(Pan123File f, String parent, {String? pathOverride}) {
    final path =
        pathOverride ?? (parent.isEmpty ? '/${f.name}' : '$parent/${f.name}');
    return CloudFile(
      path: path,
      name: f.name,
      isDir: f.isDir,
      size: f.isDir ? null : f.size,
      remoteId: '${f.fileId}',
      raw: {'etag': f.etag, 's3keyFlag': f.s3KeyFlag, 'type': f.type},
    );
  }

  void _invalidate(int fileId) {
    _fileIdCache.removeWhere(
      (key, value) => !key.startsWith('pi-search://') || value == fileId,
    );
    _metaCache.removeWhere(
      (key, value) => !key.startsWith('pi-search://') || value.fileId == fileId,
    );
    _fileIdCache['/'] = rootFileId;
  }

  /// 路径 → fileId（缓存命中直接返回，否则遍历父目录解析）
  Future<int> _resolveFileId(String path) async {
    final cached = _fileIdCache[path];
    if (cached != null) return cached;
    if (path.startsWith('pi-search://')) throw StateError('搜索结果已失效，请重新搜索');
    if (path == '/' || path.isEmpty) return rootFileId;

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    var currentPath = '';
    var currentId = rootFileId;
    for (final seg in segments) {
      currentPath = currentPath.isEmpty ? '/$seg' : '$currentPath/$seg';
      final hit = _fileIdCache[currentPath];
      if (hit != null) {
        currentId = hit;
        continue;
      }
      final files = await api.listDir(currentId);
      Pan123File? found;
      for (final f in files) {
        if (f.name == seg) {
          found = f;
          break;
        }
      }
      if (found == null) throw Pan123ApiException(-1, '路径不存在: $seg');
      currentId = found.fileId;
      _fileIdCache[currentPath] = currentId;
      _metaCache[currentPath] = found;
    }
    return currentId;
  }
}
