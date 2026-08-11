/// 登录页：选择网盘通道 → 各网盘登录方式。
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/i18n/strings.dart';
import '../core/providers/cloud_provider.dart';
import '../core/state/app_state.dart';
import '../providers/baidu_client/baidu_client_auth.dart';
import '../providers/pan123/pan123_auth.dart';
import '../providers/quark/quark_auth.dart';
import '../providers/quark/quark_config.dart';
import 'official_login_view.dart';
import 'pi_logo.dart';

class LoginPage extends StatefulWidget {
  final AppState appState;

  const LoginPage({super.key, required this.appState});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  CloudProvider? _selected;
  bool _loggingIn = false;

  // 123云盘账号密码登录
  final _pan123UserCtrl = TextEditingController();
  final _pan123PwdCtrl = TextEditingController();


  @override
  void initState() {
    super.initState();
    if (widget.appState.providers.isNotEmpty) {
      _selected = widget.appState.providers.first;
    }
  }

  /// 打开官方登录网页（WebView）登录网盘（百度/夸克）
  Future<void> _startOfficialWebLogin() async {
    final provider = _selected;
    if (provider == null) return;
    setState(() => _loggingIn = true);

    // 按网盘配置登录页参数
    final String loginUrl;
    final String successCookie;
    final String storeKey;
    if (provider.id == 'quark') {
      loginUrl = QuarkConfig.loginUrl;
      successCookie = '__puus';
      storeKey = QuarkConfig.storeKey;
    } else {
      loginUrl = 'https://passport.baidu.com/v2/?login&tpl=netdisk';
      successCookie = 'BDUSS';
      storeKey = 'baidu_client';
    }

    final ok = await loginWithOfficialWebView(
      context,
      loginUrl: loginUrl,
      successCookie: successCookie,
      storeKey: storeKey,
    );
    if (mounted) setState(() => _loggingIn = false);
    if (ok) {
      final auth = provider.auth;
      final restored = auth != null && await _restoreAuth(auth);
      if (restored && mounted) {
        await _onSuccess(provider);
      } else if (mounted) {
        _showSnack(AppStrings.loginIncomplete);
      }
    }
  }

  /// 恢复网盘会话（百度用 restoreCookies，夸克同）
  Future<bool> _restoreAuth(dynamic auth) async {
    if (auth is BaiduClientAuthProvider) return auth.restoreCookies();
    if (auth is QuarkAuthProvider) return auth.restoreCookies();
    return false;
  }

  /// 123云盘账号密码登录
  Future<void> _startPan123Login() async {
    final provider = _selected;
    final auth = provider?.auth as Pan123AuthProvider?;
    if (provider == null || auth == null) return;
    final username = _pan123UserCtrl.text.trim();
    final password = _pan123PwdCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      _showSnack(AppStrings.enterAccount);
      return;
    }
    setState(() => _loggingIn = true);
    final err = await auth.loginWithPassword(username, password);
    if (mounted) setState(() => _loggingIn = false);
    if (err != null) {
      _showSnack(err);
      return;
    }
    await _onSuccess(provider);
  }

  Future<void> _onSuccess(CloudProvider provider) async {
    // 登录成功后设置当前网盘并加载账号信息（isLoggedIn 依赖此步骤）
    await widget.appState.selectProvider(provider.id);
    if (mounted) _showSnack(AppStrings.loginSuccess);
  }

  /// 从迅雷网页版 localStorage 提取 OAuth 凭据的 JS。
  /// credentials_* 存 access_token/refresh_token，captcha_* 存 captcha_token。
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final providers = widget.appState.providers;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PiLogo(size: 64),
                const SizedBox(height: 12),
                Text(
                  AppStrings.appName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  AppStrings.tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 40),

                // 网盘通道选择
                DropdownButtonFormField<CloudProvider>(
                  initialValue: _selected,
                  decoration: InputDecoration(
                    labelText: AppStrings.selectProvider,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    for (final p in providers)
                      DropdownMenuItem(value: p, child: Text(p.displayName)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selected = v);
                  },
                ),
                const SizedBox(height: 24),

                // 百度网盘：官方登录网页
                if (_selected?.id == 'baidu_client') ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loggingIn ? null : _startOfficialWebLogin,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: kBrandColor,
                    ),
                    icon: _loggingIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.language),
                    label: Text(_loggingIn ? AppStrings.opening : AppStrings.openLoginPage),
                  ),
                ] else if (_selected?.id == 'quark') ...[
                  // 夸克网盘：官方登录网页
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loggingIn ? null : _startOfficialWebLogin,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: kBrandColor,
                    ),
                    icon: _loggingIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.language),
                    label: Text(_loggingIn ? AppStrings.opening : AppStrings.openLoginPage),
                  ),
                ] else if (_selected?.id == 'pan123') ...[
                  // 123云盘：账号密码登录
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pan123UserCtrl,
                    decoration: InputDecoration(
                      labelText: AppStrings.accountOrEmail,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pan123PwdCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: AppStrings.password,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.pan123Note,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loggingIn ? null : _startPan123Login,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: kBrandColor,
                    ),
                    icon: _loggingIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline),
                    label: Text(_loggingIn ? AppStrings.loggingIn : AppStrings.login),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
