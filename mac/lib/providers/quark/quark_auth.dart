/// 夸克网盘认证实现。
///
/// 登录方式：官方登录网页（WebView）→ 提取 cookie（核心为 __puus/__uid）。
/// 本类负责 cookie 的保存/恢复，供文件 API 使用。
library;

import 'dart:async';
import 'dart:convert';

import '../../core/providers/auth_provider.dart';
import '../../core/storage/token_store.dart';
import '../baidu_client/cookie_jar.dart';
import 'quark_config.dart';

class QuarkAuthProvider implements AuthProvider {
  final TokenStore _store;
  final CookieJar cookieJar;

  QuarkAuthProvider({TokenStore? store})
    : _store = store ?? TokenStore(),
      cookieJar = CookieJar(origin: Uri.parse('https://quark.cn'));

  @override
  String get providerId => 'quark';

  /// 夸克通过 WebView 登录，不走本接口
  @override
  Future<AuthSession> startLogin() async {
    return const AuthSession.failed('请使用官方登录网页登录');
  }

  @override
  Stream<AuthSession> get updates => const Stream<AuthSession>.empty();

  @override
  Future<void> cancelLogin() async {}

  /// 登录态以 cookie 串为凭据（无单独 token）
  @override
  Future<String?> getAccessToken() async {
    final raw = await _store.read(QuarkConfig.storeKey);
    if (raw == null) return null;
    cookieJar.loadMap(jsonDecode(raw) as Map<String, dynamic>);
    return cookieJar.get('__puus') == null ? null : 'quark-logged-in';
  }

  /// 加载本地保存的 cookie 到 jar
  Future<bool> restoreCookies() async {
    final raw = await _store.read(QuarkConfig.storeKey);
    if (raw == null) return false;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    cookieJar.loadMap(map);
    if (cookieJar.get('__puus') == null) return false;
    return true;
  }

  /// 保存 WebView 提取的 cookie（供登录页调用）
  Future<void> saveCookies(Map<String, String> cookies) async {
    await _store.save(QuarkConfig.storeKey, jsonEncode(cookies));
  }

  @override
  Future<void> logout() async {
    cookieJar.clear();
    await _store.clear(QuarkConfig.storeKey);
  }
}
