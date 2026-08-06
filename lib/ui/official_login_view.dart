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
  final Future<void> Function(Map<String, String> cookies) onLoginSuccess;

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
    if (_loggedIn) return;
    final controller = _controller;
    if (controller == null) return;

    final url = Uri.parse(widget.loginUrl);
    final cookies = await CookieManager.instance()
        .getCookies(url: WebUri('${url.scheme}://${url.host}/'),
            webViewController: controller);

    // 找登录成功标志
    String? successValue;
    for (final c in cookies) {
      if (c.name == widget.successCookie && c.value.isNotEmpty) {
        successValue = c.value;
        break;
      }
    }
    if (successValue == null) return;

    // 登录成功：收集全部 cookie 保存
    _loggedIn = true;
    _cookieTimer?.cancel();
    final cookieMap = <String, String>{};
    for (final c in cookies) {
      cookieMap[c.name] = c.value;
    }
    // 从主域名再取一轮（可能更全）
    final hostCookies = await CookieManager.instance()
        .getCookies(url: WebUri('https://${url.host}/'), webViewController: controller);
    for (final c in hostCookies) {
      cookieMap[c.name] = c.value;
    }
    if (!cookieMap.containsKey(widget.successCookie)) {
      cookieMap[widget.successCookie] = successValue;
    }

    await widget.onLoginSuccess(cookieMap);
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
                  urlRequest: URLRequest(url: WebUri(widget.loginUrl)));
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
          allowFileAccess: true,
        ),
        onWebViewCreated: (controller) async {
          _controller = controller;
          // 清除 WebView2 持久化的 cookie，强制显示登录页
          await CookieManager.instance().deleteAllCookies();
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
/// 注意：flutter_inappwebview_windows 是原生 HWND platform view，
/// 不能放进 Dialog/Overlay，必须用整页路由承载。
Future<bool> loginWithOfficialWebView(
  BuildContext context, {
  required String loginUrl,
  required String successCookie,
  required String storeKey,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (ctx) => OfficialLoginView(
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
