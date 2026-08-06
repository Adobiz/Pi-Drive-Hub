import 'package:flutter/material.dart';

import 'core/state/app_state.dart';
import 'ui/app.dart';
import 'ui/app_tray.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 系统托盘：最小化/关闭隐藏到托盘（失败不阻塞启动）
  try {
    await AppTray.init();
  } catch (e) {
    debugPrint('[tray] init 失败: $e');
  }
  final appState = AppState();
  runApp(PiPanApp(appState: appState));
}
