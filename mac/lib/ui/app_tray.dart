/// 系统菜单栏（托盘）支持：菜单栏常驻图标，托盘菜单退出应用。
///
/// macOS 使用原生 AppKit/SwiftUI；其他平台保留 tray_manager 回退。
/// 需在 main() 中先 `await AppTray.init()` 完成托盘与窗口初始化。
library;

import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/i18n/strings.dart';
import '../core/state/app_state.dart';
import '../core/state/transfer_monitor.dart';

/// 托盘图标 asset 路径（macOS 菜单栏需方形 PNG，
/// 显示尺寸由 tray_manager 的 iconSize 参数控制，默认 18pt）
const String _trayIconAsset = 'assets/tray_icon.png';

class AppTray {
  static bool _initialized = false;
  static const _native = MethodChannel('pi_drive_hub/menu_bar');
  static TransferMonitor? _monitor;
  static int windowID = 0;
  static int focusedViewId = 0;
  static final workspaceActions = <int, Future<void> Function(String)>{};
  static bool _publishing = false;
  static bool _needsPublish = false;

  static Future<void> _publish() async {
    if (_publishing) {
      _needsPublish = true;
      return;
    }
    _publishing = true;
    try {
      do {
        _needsPublish = false;
        final monitor = _monitor;
        if (monitor == null) break;
        await _native.invokeMethod<void>('update', monitor.snapshot());
      } while (_needsPublish);
    } on PlatformException catch (error) {
      debugPrint('[tray] update failed: ${error.code}');
    } finally {
      _publishing = false;
    }
  }

  static Future<dynamic> _nativeAction(MethodCall call) async {
    if (call.method != 'action') return;
    final arguments = Map<String, dynamic>.from(call.arguments as Map);
    final action = arguments['action'] as String? ?? '';
    switch (action) {
      case 'focusWindow':
        focusedViewId = (arguments['viewId'] as num?)?.toInt() ?? 0;
      case 'openMain':
        await showFromTray();
      case 'openTransfers':
        final id = await _native.invokeMethod<int>('showWindow');
        await workspaceActions[id]?.call('openTransfers');
      case 'windowHidden':
        final id = (arguments['viewId'] as num?)?.toInt() ?? windowID;
        await workspaceActions[id]?.call(action);
        // Reply directly with current queue state. The native host must not
        // destroy an engine based on a coalesced, potentially older update.
        return _monitor?.snapshot();
      case 'newTab' || 'closeTab' || 'nextTab' || 'previousTab':
        final id = (arguments['viewId'] as num?)?.toInt() ?? 0;
        await workspaceActions[id]?.call(action);
      case 'quit':
        await exitApp();
      case 'pause' || 'resume' || 'pauseAll' || 'resumeAll':
        _monitor?.act(
          action,
          kind: arguments['kind'] as String?,
          id: arguments['id'] as String?,
        );
    }
  }

  /// 是否已初始化
  static bool get initialized => _initialized;

  /// 初始化托盘与窗口行为（在 runApp 前调用）
  static Future<void> init(AppState state) async {
    if (_initialized) return;

    // macOS 窗口由原生宿主管理，避免覆盖 NSWindowDelegate。
    if (!Platform.isMacOS) {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(false);
    }

    if (Platform.isMacOS) {
      try {
        _native.setMethodCallHandler(_nativeAction);
        windowID =
            await _native.invokeMethod<int>('configure', {
              'language': appLang,
            }) ??
            0;
        focusedViewId = windowID;
        _monitor = TransferMonitor(
          downloads: state.downloadManager,
          uploads: state.uploadManager,
        );
        _monitor!.addListener(_publish);
        await _publish();
        _initialized = true;
        return;
      } catch (_) {
        _monitor?.dispose();
        _monitor = null;
        rethrow;
      }
    }

    // tray_manager：非 macOS 平台保留原托盘菜单
    try {
      await trayManager.setIcon(_trayIconAsset);
    } catch (e) {
      // 图标加载失败不阻塞启动（仅无托盘图标）
      debugPrint('[tray] setIcon 失败: $e');
    }
    trayManager.addListener(_LegacyTrayListener());
    await trayManager.setToolTip('Pi Drive Hub');
    await trayManager.setContextMenu(
      Menu(items: [MenuItem(key: 'exit', label: AppStrings.quit)]),
    );

    _initialized = true;
  }

  /// 隐藏主窗口到菜单栏（供需要时调用）。
  /// macOS 无任务栏概念，直接隐藏窗口即可；应用仍在 Dock 与菜单栏驻留。
  static Future<void> hideToTray() async {
    if (!_initialized) return;
    if (Platform.isMacOS) {
      await _native.invokeMethod<void>('hideWindow');
    } else {
      await windowManager.hide();
    }
  }

  /// 从托盘恢复主窗口
  static Future<void> showFromTray() async {
    if (!_initialized) return;
    if (Platform.isMacOS) {
      await _native.invokeMethod<int>('showWindow');
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  static Future<void> windowReady(int viewId, int tabs) async {
    if (Platform.isMacOS && _initialized) {
      await _native.invokeMethod<void>('workspaceReady', {
        'viewId': viewId,
        'tabs': tabs,
      });
    }
  }

  static Future<void> newWindow() async {
    if (Platform.isMacOS && _initialized) {
      await _native.invokeMethod<int>('newWindow');
    }
  }

  static Future<void> closeWindow(int viewId) async {
    if (Platform.isMacOS && _initialized) {
      await _native.invokeMethod<void>('closeWindow', {'viewId': viewId});
    }
  }

  static Future<void> setWindowTitle(int viewId, String title) async {
    if (Platform.isMacOS && _initialized) {
      await _native.invokeMethod<void>('setWindowTitle', {
        'viewId': viewId,
        'title': title,
      });
    }
  }

  /// 完全退出（销毁托盘 + 退出进程）。
  /// 用 exit(0) 立即终止进程：避免 window_manager.destroy() 异步销毁
  /// 与 preventClose 拦截互相等待导致的延迟/卡顿。
  static Future<void> exitApp() async {
    if (_initialized) {
      try {
        _monitor?.dispose();
        _monitor = null;
        if (Platform.isMacOS) {
          await _native.invokeMethod<void>('destroy');
        } else {
          await trayManager.destroy();
        }
      } catch (_) {}
    }
    // 立即退出进程（菜单栏图标随进程终止被系统清理）
    exit(0);
  }
}

class _LegacyTrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    AppTray.showFromTray();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'exit') {
      AppTray.exitApp();
    }
  }
}
