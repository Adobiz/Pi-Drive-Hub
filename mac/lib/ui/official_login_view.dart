/// 官方登录网页内嵌视图（WebView）。
///
/// 加载网盘官方登录页，用户扫码/验证码登录由官方页面处理。
/// 轮询 cookie，检测到登录成功标志（如 BDUSS / __puus）后回调并保存。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/i18n/strings.dart';
import '../core/storage/token_store.dart';

class OfficialLoginView extends StatefulWidget {
  /// 登录页 URL
  final String loginUrl;

  /// 登录成功标志 cookie 名（百度=BDUSS，夸克=__puus）
  final String successCookie;

  /// 登录成功后 cookie 保存的存储 key
  final String storeKey;

  /// 登录成功（拿到标志 cookie）时回调
  final Future<void> Function(Map<String, dynamic> cookies) onLoginSuccess;

  const OfficialLoginView({
    super.key,
    required this.loginUrl,
    required this.successCookie,
    required this.storeKey,
    required this.onLoginSuccess,
  });

  @override
  State<OfficialLoginView> createState() => _OfficialLoginViewState();
}

class _OfficialLoginViewState extends State<OfficialLoginView> {
  InAppWebViewController? _controller;
  Timer? _cookieTimer;
  bool _loggedIn = false;
  bool _checking = false;
  bool _ready = false;

  // 轮询日志去重：cookie 概况未变化时不重复打印
  int _lastCookieCount = -1;
  bool _lastHasSuccess = false;

  @override
  void initState() {
    super.initState();
    // 每秒轮询一次 cookie，检测登录成功标志
    _cookieTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkCookies();
    });
  }

  @override
  void dispose() {
    _cookieTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkCookies() async {
    if (!mounted || !_ready || _loggedIn || _checking) return;
    _checking = true;
    try {
      await _readCookies();
    } finally {
      _checking = false;
    }
  }

  Future<void> _readCookies() async {
    final controller = _controller;
    if (controller == null) return;

    final url = Uri.parse(widget.loginUrl);
    List<Cookie> cookies;
    try {
      cookies = await CookieManager.instance().getCookies(
        url: WebUri('${url.scheme}://${url.host}/'),
        webViewController: controller,
      );
    } catch (e) {
      // 单次轮询失败不致命，下一轮会重试；打印便于排查
      debugPrint('[login] 读取 cookie 失败: $e');
      return;
    }
    if (!mounted || _loggedIn) return;

    // 找登录成功标志
    String? successValue;
    for (final c in cookies) {
      if (c.name == widget.successCookie && c.value.isNotEmpty) {
        successValue = c.value;
        break;
      }
    }
    if (successValue == null) {
      // 尚未登录成功：仅在 cookie 概况变化时打印一次，避免每秒刷屏
      final hasSuccess = cookies.any((c) => c.name == widget.successCookie);
      if (cookies.length != _lastCookieCount || hasSuccess != _lastHasSuccess) {
        _lastCookieCount = cookies.length;
        _lastHasSuccess = hasSuccess;
        debugPrint(
          '[login] 等待登录态: 共 ${cookies.length} 个 cookie, '
          '含 ${widget.successCookie}: $hasSuccess',
        );
      }
      return;
    }
    debugPrint('[login] 检测到 ${widget.successCookie}，登录成功');

    // 登录成功：收集全部 cookie 保存
    _loggedIn = true;
    _cookieTimer?.cancel();
    final cookieMap = <String, dynamic>{
      'version': 2,
      'cookies':
          cookies
              .map(
                (c) => {
                  'name': c.name,
                  'value': c.value,
                  'domain': c.domain ?? url.host,
                  'path': c.path ?? '/',
                  'secure': true,
                  'hostOnly': c.domain == null,
                  'expires': c.expiresDate,
                },
              )
              .toList(),
    };

    try {
      await widget.onLoginSuccess(cookieMap);
    } catch (e) {
      // 保存失败也关闭页面，让登录页给出明确提示，避免卡死在 WebView
      debugPrint('[login] cookie 保存失败: $e');
      if (mounted) {
        Navigator.of(context).pop(false);
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.webLoginTitle),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller?.loadUrl(
                urlRequest: URLRequest(url: WebUri(widget.loginUrl)),
              );
            },
          ),
        ],
      ),
      body: InAppWebView(
        // 不设 initialUrlRequest：先清 cookie 再手动加载，
        // 否则已登录用户会直接跳转到登录状态而非登录页
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          supportMultipleWindows: true,
          useShouldOverrideUrlLoading: false,
          allowFileAccess: false,
        ),
        onWebViewCreated: (controller) async {
          _controller = controller;
          // 清除 WebView2 持久化的 cookie，强制显示登录页
          await CookieManager.instance().deleteCookies(
            url: WebUri(widget.loginUrl),
          );
          if (!mounted) return;
          _ready = true;
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(widget.loginUrl)),
          );
        },
      ),
    );
  }
}

/// 从 WebView cookie 登录并保存凭据（供登录页调用）。
///
/// 注意：WebView 是原生 platform view（macOS 为 WKWebView），
/// 不能放进 Dialog/Overlay，必须用整页路由承载。
Future<bool> loginWithOfficialWebView(
  BuildContext context, {
  required String loginUrl,
  required String successCookie,
  required String storeKey,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder:
          (ctx) => OfficialLoginView(
            loginUrl: loginUrl,
            successCookie: successCookie,
            storeKey: storeKey,
            onLoginSuccess: (cookies, [extracted]) async {
              final store = TokenStore();
              await store.save(storeKey, jsonEncode(cookies));
            },
          ),
    ),
  );
  return result ?? false;
}
