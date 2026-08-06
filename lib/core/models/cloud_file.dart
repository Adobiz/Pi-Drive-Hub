/// 网盘中的文件/目录统一模型。
///
/// 各网盘 Provider 返回的原生数据都会归一化为该模型，
/// UI 层只依赖此模型，不感知具体网盘差异。
class CloudFile {
  /// 网盘内完整路径，如 `/apps/我的数据/照片`
  final String path;

  /// 文件名/目录名
  final String name;

  /// 是否为目录
  final bool isDir;

  /// 文件大小（字节），目录为 null
  final int? size;

  /// 本地修改时间
  final DateTime? modified;

  /// 服务端修改时间
  final DateTime? serverModified;

  /// 文件 MD5（部分网盘提供）
  final String? md5;

  /// 网盘原生 fs_id / id，用于后续操作（删除/重命名/下载）
  final String? remoteId;

  /// 网盘原生元数据（保留原始字段，便于调试和扩展）
  final Map<String, dynamic> raw;

  const CloudFile({
    required this.path,
    required this.name,
    required this.isDir,
    this.size,
    this.modified,
    this.serverModified,
    this.md5,
    this.remoteId,
    this.raw = const {},
  });

  /// 人性化显示大小
  String get sizeText {
    final s = size;
    if (s == null) return '';
    if (s < 1024) return '$s B';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    if (s < 1024 * 1024 * 1024) {
      return '${(s / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(s / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  String toString() => 'CloudFile($path, isDir=$isDir)';
}
