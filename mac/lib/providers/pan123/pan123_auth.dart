/// 123 云盘认证实现（账号密码登录）。
///
/// 123 无第三方扫码接口，登录方式为手机号/邮箱 + 密码，
/// 成功后保存 AccessToken，请求带 `Authorization: Bearer <token>`。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/providers/auth_provider.dart';
import '../../core/storage/token_store.dart';
import 'pan123_config.dart';

class Pan123AuthProvider implements AuthProvider {
  final TokenStore _store;
  final http.Client _client;
  String? _token;

  Pan123AuthProvider({TokenStore? store, http.Client? client})
      : _store = store ?? TokenStore(),
        _client = client ?? http.Client();

  @override
  String get providerId => 'pan123';

  /// 账号密码登录（123 无扫码）
  /// 返回 null 表示成功，否则返回错误信息
  Future<String?> loginWithPassword(String username, String password) async {
    try {
      // 邮箱 or 手机号
      final isEmail = username.contains('@');
      final body = isEmail
          ? {
              'mail': username,
              'password': password,
              'type': 2,
            }
          : {
              'passport': username,
              'password': password,
              'remember': true,
            };
      final resp = await _client
          .post(
            Uri.parse('${Pan123Config.loginBase}/user/sign_in'),
            headers: {
              'origin': Pan123Config.webBase,
              'referer': '${Pan123Config.webBase}/',
              'platform': 'web',
              'app-version': '3',
              'Content-Type': 'application/json',
              'User-Agent': Pan123Config.ua,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final code = (json['code'] as num?)?.toInt() ?? -1;
      if (code != 200) {
        return (json['message'] ?? '登录失败 code=$code').toString();
      }
      final data = json['data'] as Map<String, dynamic>?;
      _token = data?['token'] as String?;
      if (_token == null) return '登录响应缺少 token';
      await _store.save(Pan123Config.storeKey, jsonEncode({'token': _token}));
      return null;
    } catch (e) {
      return '登录异常: $e';
    }
  }

  @override
  Future<AuthSession> startLogin() async {
    return const AuthSession.failed('123云盘请使用账号密码登录');
  }

  @override
  Stream<AuthSession> get updates => const Stream<AuthSession>.empty();

  @override
  Future<void> cancelLogin() async {}

  @override
  Future<String?> getAccessToken() async {
    if (_token != null) return _token;
    final raw = await _store.read(Pan123Config.storeKey);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _token = map['token'] as String?;
    return _token;
  }

  /// 恢复本地 token（登录页调用）
  Future<bool> restoreToken() async {
    final t = await getAccessToken();
    return t != null;
  }

  @override
  Future<void> logout() async {
    _token = null;
    await _store.clear(Pan123Config.storeKey);
  }
}
