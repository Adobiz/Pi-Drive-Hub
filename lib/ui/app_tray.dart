/// 系统托盘支持：最小化/关闭时隐藏到托盘，托盘菜单恢复或退出。
///
/// 依赖 tray_manager + window_manager（Windows 桌面端）。
/// 需在 main() 中先 `await AppTray.init()` 完成托盘与窗口初始化。
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 托盘图标 asset 路径（Windows 需 .ico）
const String _trayIconAsset = 'assets/app_icon.ico';

class AppTray {
  static bool _initialized = false;

  /// 是否已初始化
  static bool get initialized => _initialized;

  /// 初始化托盘与窗口行为（在 runApp 前调用）
  static Future<void> init() async {
    if (_initialized) return;

    // window_manager：拦截窗口事件（最小化/关闭 → 隐藏到托盘）
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true); // 拦截关闭按钮

    // tray_manager：托盘图标 + 菜单
    try {
      await trayManager.setIcon(_trayIconAsset);
    } catch (e) {
      // 图标加载失败不阻塞启动（仅无托盘图标）
      debugPrint('[tray] setIcon 失败: $e');
    }
    await trayManager.setToolTip('Pi Drive Hub');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'exit', label: '退出'),
    ]));

    _initialized = true;
  }

  /// 隐藏主窗口到托盘（供最小化/关闭事件调用）。
  /// 注：window_manager 的 setSkipTaskbar 在 Windows 上与托盘交互会崩溃
  /// （window_manager_plugin.dll 0xc0000005），因此仅最小化窗口，
  /// 任务栏仍保留图标，托盘图标可右键退出/双击恢复。
  static Future<void> hideToTray() async {
    if (!_initialized) return;
    await windowManager.minimize();
  }

  /// 从托盘恢复主窗口
  static Future<void> showFromTray() async {
    if (!_initialized) return;
    await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  /// 完全退出（销毁托盘 + 关窗口）。
  /// 用 exit(0) 立即终止进程：window_manager.destroy() 走异步
  /// WM_SYSCOMMAND/SC_CLOSE 消息，配合 preventClose 有延迟/卡顿。
  static Future<void> exitApp() async {
    if (_initialized) {
      try {
        await trayManager.destroy();
      } catch (_) {}
    }
    // 立即退出进程（托盘图标随进程终止被系统清理）
    exit(0);
  }
}

/// 应用托盘监听器：接入 TrayListener + WindowListener。
/// 用法：在根 State 上 `with AppTrayMixin`，并覆写 [onWindowMinimize] 等回调。
mixin AppTrayMixin<T extends StatefulWidget> on State<T>
    implements TrayListener, WindowListener {
  /// 是否启用"最小化到托盘"（默认 true，调试时可关闭）
  bool get trayEnabled => true;

  // ---------- 窗口事件：最小化/关闭 → 隐藏到托盘 ----------

  @override
  void onWindowMinimize() async {
    if (!trayEnabled) return;
    // 用户点最小化按钮：窗口已最小化到任务栏，托盘图标保持可用
  }

  @override
  void onWindowClose() async {
    // 用户点右上角 X（或任务栏关闭）：直接退出，含托盘
    await AppTray.exitApp();
  }

  @override
  void onWindowRestore() async {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowBlur() {}

  @override
  void onWindowMaximize() async {}

  @override
  void onWindowUnmaximize() async {}

  @override
  void onWindowEnterFullScreen() async {}

  @override
  void onWindowLeaveFullScreen() async {}

  @override
  void onWindowMove() async {}

  @override
  void onWindowResize() async {}

  @override
  void onWindowResized() async {}

  @override
  void onWindowMoved() async {}

  @override
  void onWindowDocked() async {}

  @override
  void onWindowUndocked() async {}

  @override
  void onWindowEvent(String eventName) {}

  // ---------- 托盘事件 ----------

  // 双击检测：记录上次左键按下时间
  DateTime? _lastLeftClick;

  @override
  void onTrayIconMouseDown() {
    // 左键：检测双击（间隔 <300ms 视为双击 → 打开主窗口）；
    // 单击不弹菜单（Windows 标准：单击仅选中）
    final now = DateTime.now();
    if (_lastLeftClick != null &&
        now.difference(_lastLeftClick!) < const Duration(milliseconds: 300)) {
      _lastLeftClick = null;
      AppTray.showFromTray();
    } else {
      _lastLeftClick = now;
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconMouseUp() {}

  @override
  void onTrayIconRightMouseUp() {}

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        AppTray.showFromTray();
        break;
      case 'exit':
        AppTray.exitApp();
        break;
    }
  }
}
