import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/state/app_state.dart';
import 'ui/app.dart';
import 'ui/app_tray.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1080, 720),
        minimumSize: Size(880, 600),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  final appState = AppState();
  // 系统托盘：菜单栏常驻图标，托盘菜单可退出（失败不阻塞启动）
  try {
    await AppTray.init(appState);
  } catch (e) {
    debugPrint('[tray] init 失败: $e');
  }
  runApp(PiPanApp(appState: appState, viewId: AppTray.windowID));
}
