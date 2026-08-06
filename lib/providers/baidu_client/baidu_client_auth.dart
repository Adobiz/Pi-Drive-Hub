/// 百度网盘客户端协议认证实现。
///
/// 登录方式：官方登录网页（WebView）→ 提取 BDUSS cookie 保存。
/// 本类负责 cookie 的保存/恢复，供文件 API 使用。
library;

import 'dart:async';
import 'dart:convert';


import '../../core/providers/auth_provider.dart';
import '../../core/storage/token_store.dart';
import 'cookie_jar.dart';

class BaiduClientAuthProvider implements AuthProvider {
  final TokenStore _store;
  final CookieJar cookieJar;

  BaiduClientAuthProvider({TokenStore? store})
      : _store = store ?? TokenStore(),
        cookieJar = CookieJar();

  @override
  String get providerId => 'baidu_client';

  /// 客户端协议通过 WebView 登录，不走本接口
  @override
  Future<AuthSession> startLogin() async {
    return const AuthSession.failed('请使用官方登录网页登录');
  }

  @override
  Stream<AuthSession> get updates =>
      const Stream<AuthSession>.empty();

  @override
  Future<void> cancelLogin() async {}

  /// 客户端协议以 BDUSS 为会话标识
  @override
  Future<String?> getAccessToken() async {
    final raw = await _store.read('baidu_client');
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map['BDUSS'] as String?;
  }

  /// 加载本地保存的 cookie 到 jar（WebView 登录成功后调用）
  Future<bool> restoreCookies() async {
    final raw = await _store.read('baidu_client');
    if (raw == null) return false;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (map['BDUSS'] == null) return false;
    cookieJar.loadMap(map.cast<String, String>());
    return true;
  }

  @override
  Future<void> logout() async {
    cookieJar.clear();
    await _store.clear('baidu_client');
  }
}
