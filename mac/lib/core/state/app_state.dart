/// 应用全局状态：当前网盘、登录状态、导航。
library;

import 'package:flutter/foundation.dart';

import '../models/cloud_account.dart';
import '../providers/cloud_provider.dart';
import '../providers/provider_registry.dart';
import 'download_manager.dart';
import 'upload_manager.dart';

class AppState extends ChangeNotifier {
  /// 下载任务管理器
  final DownloadManager downloadManager;

  /// 上传任务管理器
  final UploadManager uploadManager;

  final List<CloudProvider> _providers;
  String preferredProviderId;
  AppState({
    DownloadManager? downloadManager,
    UploadManager? uploadManager,
    List<CloudProvider>? providers,
    String? preferredProviderId,
  }) : downloadManager = downloadManager ?? DownloadManager(),
       uploadManager = uploadManager ?? UploadManager(),
       _providers = providers ?? createDefaultProviders(),
       preferredProviderId = preferredProviderId ?? 'baidu_client';

  void preferProvider(String id) {
    if (_disposed) return;
    preferredProviderId = id;
    _notify();
  }

  Future<void> _cancelCurrent() async {
    final provider = _currentProvider;
    if (provider == null) return;
    await Future.wait([
      downloadManager.cancelForProvider(provider),
      uploadManager.cancelForProvider(provider),
    ]);
  }

  /// 当前选中的网盘
  CloudProvider? _currentProvider;
  CloudProvider? get currentProvider => _currentProvider;

  /// 当前账号信息（登录后填充）
  int _sessionRevision = 0;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  CloudAccount? _account;
  CloudAccount? get account => _account;

  /// 是否已登录（有 token 且已加载账号信息）
  bool get isLoggedIn => _currentProvider != null && _account != null;

  /// 所有可用网盘
  List<CloudProvider> get providers => List.unmodifiable(_providers);

  /// 切换到指定网盘并尝试自动登录（有缓存 token 时）
  Future<bool> selectProvider(String providerId) async {
    if (_disposed) return false;
    CloudProvider? provider;
    for (final candidate in _providers) {
      if (candidate.id == providerId) provider = candidate;
    }
    if (provider == null) return false;

    final revision = ++_sessionRevision;
    _account = null;
    _notify();
    // 只取消当前标签页所属 Provider 的任务。
    await _cancelCurrent();
    if (revision != _sessionRevision) return false;
    _currentProvider?.clearSession();
    provider.clearSession();

    preferredProviderId = providerId;
    _currentProvider = provider;
    _account = null;
    _notify();

    // 尝试用本地缓存 token 静默登录
    final auth = provider.auth;
    if (auth != null) {
      try {
        final token = await auth.getAccessToken();
        if (revision != _sessionRevision) return false;
        if (token != null) {
          final account = await provider.getAccountInfo();
          if (revision != _sessionRevision) return false;
          _account = account;
          // 根据会员类型设置下载并发上限（SVIP 多任务并发，普通账号受限）
          final vip = _account?.vipType ?? 0;
          downloadManager.applyVipConcurrency(vip, provider: provider);
          _notify();
          return true;
        }
      } catch (e) {
        // Keychain 拒绝访问、旧凭据损坏和接口异常均返回登录失败。
        debugPrint('[login] 会话恢复失败(${provider.id}): $e');
      }
    }
    return false;
  }

  Future<void> logout() async {
    if (_disposed) return;
    final revision = ++_sessionRevision;
    final provider = _currentProvider;
    _account = null;
    _notify();
    // 退出登录只处理当前标签页所属 Provider 的任务。
    await _cancelCurrent();
    if (revision != _sessionRevision) return;
    provider?.clearSession();
    await provider?.auth?.logout();
    _account = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionRevision++;
    super.dispose();
  }
}
