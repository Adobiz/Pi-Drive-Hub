/// 应用根组件：干净主题 + 登录/主界面路由 + 系统托盘。
library;

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/constants.dart';
import '../core/state/app_state.dart';
import '../core/i18n/strings.dart';
import 'app_tray.dart';
import 'file_browser_page.dart';
import 'login_page.dart';

class PiPanApp extends StatefulWidget {
  final AppState appState;

  const PiPanApp({super.key, required this.appState});

  @override
  State<PiPanApp> createState() => _PiPanAppState();
}

class _PiPanAppState extends State<PiPanApp>
    with AppTrayMixin, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // 注册托盘 + 窗口事件监听（AppTrayMixin 提供实现）
    if (AppTray.initialized) {
      trayManager.addListener(this);
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (AppTray.initialized) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrandColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrandColor,
          brightness: Brightness.dark,
        ),
      ),
      home: ListenableBuilder(
        listenable: widget.appState,
        builder: (context, _) {
          if (widget.appState.isLoggedIn) {
            return FileBrowserPage(appState: widget.appState);
          }
          return LoginPage(appState: widget.appState);
        },
      ),
    );
  }
}
