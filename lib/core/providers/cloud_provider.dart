/// 网盘操作层抽象接口。
///
/// 每个支持的网盘实现一个 CloudProvider（如 BaiduProvider），
/// 文件操作统一归一化为本接口定义的能力，UI 完全不感知网盘差异。
library;

import '../models/cloud_account.dart';
import '../models/cloud_file.dart';
import 'auth_provider.dart';

/// 传输进度回调：doneBytes / totalBytes（totalBytes 可能为 null，未知总量）
typedef TransferProgress = void Function(int doneBytes, int? totalBytes);

abstract class CloudProvider {
  /// Provider 唯一 id（如 `baidu`）
  String get id;

  /// 展示名称（如 `百度网盘`）
  String get displayName;

  /// 该网盘的认证实现；未实现认证能力的 Provider 返回 null
  AuthProvider? get auth => null;

  /// 当前登录账号信息
  Future<CloudAccount> getAccountInfo();

  /// 列出指定目录下的文件和子目录
  Future<List<CloudFile>> list(String path);

  /// 在 parentPath 下新建目录
  Future<CloudFile> createFolder(String parentPath, String name);

  /// 重命名
  Future<void> rename(String path, String newName);

  /// 删除文件或目录（目录需为空或递归删除由具体实现决定）
  Future<void> delete(String path);

  /// 上传本地文件到网盘目录
  Future<void> upload(
    String localPath,
    String remoteDir, {
    TransferProgress? onProgress,
  });

  /// 下载网盘文件到本地目录
  Future<void> download(
    String remotePath,
    String localDir, {
    TransferProgress? onProgress,
    bool Function()? isCanceled,
    Set<int>? completedBlocks,
    void Function(int, Set<int>)? onBlocks,
  });

  /// 移动（可选能力，默认抛 [UnimplementedError]）
  Future<void> move(String fromPath, String toDir) {
    throw UnimplementedError('$displayName 不支持移动操作');
  }

  /// 复制（可选能力，默认抛 [UnimplementedError]）
  Future<void> copy(String fromPath, String toDir) {
    throw UnimplementedError('$displayName 不支持复制操作');
  }
}
