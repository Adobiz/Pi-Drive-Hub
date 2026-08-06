/// 夸克网盘 Provider：通过官方登录网页（WebView）登录 + 私有 API 操作。
library;

import 'dart:io';

import '../../core/models/cloud_account.dart';
import '../../core/models/cloud_file.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/cloud_provider.dart';
import 'quark_api.dart';
import 'quark_auth.dart';

class QuarkProvider implements CloudProvider {
  final QuarkAuthProvider authProvider;
  late final QuarkApi api;

  /// 根目录 fid
  static const String rootFid = '0';

  /// 路径 → fid 缓存（夸克按 fid 操作，缓存避免反复解析）
  final Map<String, String> _fidCache = {'/': rootFid};

  QuarkProvider({QuarkAuthProvider? auth})
      : authProvider = auth ?? QuarkAuthProvider() {
    api = QuarkApi(auth: authProvider);
  }

  @override
  String get id => 'quark';

  @override
  String get displayName => '夸克网盘';

  @override
  AuthProvider? get auth => authProvider;

  @override
  Future<CloudAccount> getAccountInfo() async {
    final info = await api.getUserInfo();
    // 容量与会员：从 growth/info 接口获取
    int? total;
    int? used;
    int? vip;
    try {
      final cap = await api.getCapacityInfo();
      if (cap != null) {
        // 总量：total_capacity；已用：use_capacity（实测返回字段）
        total = (cap['total_capacity'] as num?)?.toInt();
        used = (cap['use_capacity'] as num?)?.toInt();
        final memberType = cap['member_type']?.toString();
        // 夸克会员类型：0=普通, 1=会员, 2=超级会员
        vip = _memberTypeToVip(memberType);
      }
    } catch (_) {}
    return CloudAccount(
      providerId: id,
      displayName: (info['nickname'] as String?) ?? '夸克用户',
      avatarUrl: info['avatar'] as String?,
      totalQuota: total,
      usedQuota: used,
      vipType: vip,
    );
  }

  /// 夸克 member_type 字符串 → 统一的 vipType 数字
  int? _memberTypeToVip(String? memberType) {
    if (memberType == null) return null;
    final t = memberType.toLowerCase();
    if (t.contains('svip') || t.contains('super')) return 2;
    if (t.contains('vip') || t.contains('member')) return 1;
    return 0;
  }


  @override
  Future<List<CloudFile>> list(String path) async {
    final fid = await _resolveFid(path);
    final list = await api.listDir(fid);
    final parent = path == '/' ? '' : path;
    return list.map((e) => _toCloudFile(e, parent)).toList();
  }

  /// 搜索文件（按文件名，夸克无全盘搜索，用列表接口 + 全目录递归近似）
  Future<List<CloudFile>> search(String keyword) async {
    final results = <CloudFile>[];
    await _searchRecursive(keyword, rootFid, '', results);
    return results;
  }

  Future<void> _searchRecursive(
      String keyword, String fid, String parent, List<CloudFile> out) async {
    final list = await api.listDir(fid);
    for (final item in list) {
      final f = _toCloudFile(item, parent);
      if (f.name.toLowerCase().contains(keyword.toLowerCase())) {
        out.add(f);
      }
      if (f.isDir) {
        await _searchRecursive(keyword, f.remoteId ?? '', f.path, out);
      }
    }
  }

  @override
  Future<CloudFile> createFolder(String parentPath, String name) async {
    final full = parentPath == '/' ? '/$name' : '$parentPath/$name';
    await api.createFolder(full);
    // 新建后清缓存，强制重新解析
    _fidCache.removeWhere((k, _) => k.startsWith(parentPath == '/' ? '/' : parentPath));
    return CloudFile(path: full, name: name, isDir: true, remoteId: full);
  }

  @override
  Future<void> rename(String path, String newName) async {
    final fid = await _resolveFid(path);
    await api.rename(fid, newName);
    _fidCache.clear();
  }

  @override
  Future<void> delete(String path) async {
    final fid = await _resolveFid(path);
    await api.delete([fid]);
    _fidCache.clear();
  }

  @override
  Future<void> move(String fromPath, String toDir) async {
    final fid = await _resolveFid(fromPath);
    final toFid = await _resolveFid(toDir);
    await api.move([fid], toFid);
    _fidCache.clear();
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
  }) async {
    final file = File(localPath);
    final name = file.uri.pathSegments.last;
    final dirFid = await _resolveFid(remoteDir);
    await api.upload(localPath, dirFid, name, onProgress: onProgress);
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
    final fid = await _resolveFid(remotePath);
    final name = remotePath.split('/').last;
    await api.download(fid, '$localDir/$name',
        onProgress: onProgress,
        isCanceled: isCanceled,
        completedBlocks: completedBlocks,
        onBlocks: onBlocks);
  }

  CloudFile _toCloudFile(Map<String, dynamic> item, String parent) {
    final fid = (item['fid'] as String?) ?? '';
    final name = (item['file_name'] as String?) ?? '';
    final isFile = (item['file'] as bool?) ?? false;
    final ts = (item['updated_at'] as num?)?.toInt();
    final path = parent.isEmpty ? '/$name' : '$parent/$name';
    // 记录目录 fid 到缓存，供后续导航
    if (!isFile && fid.isNotEmpty) {
      _fidCache[path] = fid;
    }
    return CloudFile(
      path: path,
      name: name,
      isDir: !isFile,
      size: (item['size'] as num?)?.toInt(),
      serverModified: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
      remoteId: fid,
      raw: item,
    );
  }

  /// 解析路径对应文件的 fid（缓存命中直接返回，否则遍历父目录列表）
  Future<String> _resolveFid(String path) async {
    final cached = _fidCache[path];
    if (cached != null) return cached;
    if (path == '/' || path.isEmpty) return rootFid;

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    var currentPath = '';
    var currentFid = rootFid;
    for (final seg in segments) {
      currentPath = currentPath.isEmpty ? '/$seg' : '$currentPath/$seg';
      final hit = _fidCache[currentPath];
      if (hit != null) {
        currentFid = hit;
        continue;
      }
      final list = await api.listDir(currentFid);
      Map<String, dynamic>? found;
      for (final item in list) {
        if (item['file_name'] == seg) {
          found = item;
          break;
        }
      }
      if (found == null) throw QuarkApiException(-1, '路径不存在: $seg');
      currentFid = found['fid'] as String;
      if (!(found['file'] as bool? ?? false)) {
        _fidCache[currentPath] = currentFid;
      }
    }
    return currentFid;
  }
}
