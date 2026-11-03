/// 已登录网盘账号的公开信息（用于 UI 展示）。
class CloudAccount {
  /// 所属 Provider 的唯一 id（如 `baidu`）
  final String providerId;

  /// 网盘内显示的用户昵称
  final String displayName;

  /// 头像 URL（可能为空）
  final String? avatarUrl;

  /// 网盘总容量（字节），可能为空
  final int? totalQuota;

  /// 已用容量（字节），可能为空
  final int? usedQuota;

  /// 会员类型：0=非会员，1=普通会员，2=超级会员(SVIP)，null=未知
  final int? vipType;

  const CloudAccount({
    required this.providerId,
    required this.displayName,
    this.avatarUrl,
    this.totalQuota,
    this.usedQuota,
    this.vipType,
  });

  /// 会员状态文字（用于右上角显示）
  String get vipText {
    switch (vipType) {
      case 1:
        return '会员';
      case 2:
        return 'SVIP';
      case 3:
        return '尊享会员';
      default:
        return '未开通会员';
    }
  }

  /// 剩余容量人性化文本，如 `已用 12.3 GB / 2 TB`
  String get quotaText {
    final total = totalQuota;
    final used = usedQuota;
    if (total == null || used == null) return '';
    return '已用 ${_fmt(used)} / ${_fmt(total)}';
  }

  static String _fmt(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}
