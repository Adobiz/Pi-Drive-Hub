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
  final DownloadManager downloadManager = DownloadManager();

  /// 上传任务管理器
  final UploadManager uploadManager = UploadManager();

  AppState() {
    setupDefaultProviders();
  }

  /// 当前选中的网盘
  CloudProvider? _currentProvider;
  CloudProvider? get currentProvider => _currentProvider;

  /// 当前账号信息（登录后填充）
  CloudAccount? _account;
  CloudAccount? get account => _account;

  /// 是否已登录（有 token 且已加载账号信息）
  bool get isLoggedIn => _currentProvider != null && _account != null;

  /// 所有可用网盘
  List<CloudProvider> get providers => ProviderRegistry.instance.all;

  /// 切换到指定网盘并尝试自动登录（有缓存 token 时）
  Future<bool> selectProvider(String providerId) async {
    final provider = ProviderRegistry.instance.byId(providerId);
    if (provider == null) return false;

    // 切换账号：取消并清空所有传输任务，避免旧账号任务残留
    downloadManager.cancelAll();
    uploadManager.cancelAll();

    _currentProvider = provider;
    _account = null;
    notifyListeners();

    // 尝试用本地缓存 token 静默登录
    final auth = provider.auth;
    if (auth != null) {
      final token = await auth.getAccessToken();
      if (token != null) {
        try {
          _account = await provider.getAccountInfo();
          // 根据会员类型设置下载并发上限（SVIP 多任务并发，普通账号受限）
          final vip = _account?.vipType ?? 0;
          downloadManager.applyVipConcurrency(vip);
          notifyListeners();
          return true;
        } catch (e) {
          // token 失效则停留登录页
        }
      }
    }
    return false;
  }

  Future<void> logout() async {
    // 退出登录：取消并清空所有传输任务
    downloadManager.cancelAll();
    uploadManager.cancelAll();
    final provider = _currentProvider;
    await provider?.auth?.logout();
    _account = null;
    notifyListeners();
  }
}

