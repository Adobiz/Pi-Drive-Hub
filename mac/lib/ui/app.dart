import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../core/i18n/strings.dart';
import '../core/state/app_state.dart';
import '../core/state/workspace_tabs.dart';
import 'app_tray.dart';
import 'download_page.dart';
import 'file_browser_page.dart';
import 'login_page.dart';
import 'pi_logo.dart';

class PiPanApp extends StatefulWidget {
  final AppState appState;
  final int viewId;
  final WorkspaceTabs? tabs;
  const PiPanApp({
    super.key,
    required this.appState,
    this.viewId = 0,
    this.tabs,
  });
  @override
  State<PiPanApp> createState() => _PiPanAppState();
}

class _PiPanAppState extends State<PiPanApp> {
  late final WorkspaceTabs tabs;
  final _navigators = <int, GlobalKey<NavigatorState>>{};
  String? _lastTitle;
  bool get english => appLang == 'en';
  @override
  void initState() {
    super.initState();
    tabs =
        widget.tabs ??
        WorkspaceTabs(
          downloads: widget.appState.downloadManager,
          uploads: widget.appState.uploadManager,
        );
    tabs.addListener(_changed);
    HardwareKeyboard.instance.addHandler(_tabKeyEvent);
    AppTray.workspaceActions[widget.viewId] = _action;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppTray.windowReady(widget.viewId, tabs.tabs.length);
    });
  }

  bool _tabKeyEvent(KeyEvent event) {
    if (AppTray.focusedViewId != widget.viewId ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.tab ||
        !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    tabs.cycle(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
    return true;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppTray.windowReady(widget.viewId, tabs.tabs.length);
    });
    final title = '${tabs.current.title} — ${AppStrings.appName}';
    if (_lastTitle != title) {
      _lastTitle = title;
      AppTray.setWindowTitle(widget.viewId, title);
    }
  }

  Future<void> _action(String action) async {
    switch (action) {
      case 'windowHidden':
        for (final navigator in _navigators.values) {
          navigator.currentState?.popUntil((route) => route.isFirst);
        }
      case 'newTab':
        tabs.add();
      case 'nextTab':
        tabs.cycle(1);
      case 'previousTab':
        tabs.cycle(-1);
      case 'closeTab':
        _close(tabs.selected);
      case 'openTransfers':
        final state = tabs.current.state;
        // A closed tab can still own transfers, even while this tab is logged out.
        final navigator = _navigators[tabs.selected]?.currentState;
        navigator?.popUntil((route) => route.isFirst);
        navigator?.push(
          MaterialPageRoute<void>(
            builder:
                (_) => DownloadPage(
                  manager: state.downloadManager,
                  uploadManager: state.uploadManager,
                ),
          ),
        );
    }
  }

  void _close(int id) {
    if (!tabs.close(id)) {
      AppTray.closeWindow(widget.viewId);
    } else {
      _navigators.remove(id);
    }
  }

  @override
  void dispose() {
    AppTray.workspaceActions.remove(widget.viewId);
    HardwareKeyboard.instance.removeHandler(_tabKeyEvent);
    tabs.removeListener(_changed);
    if (widget.tabs == null) tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppStrings.appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kBrandColor),
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kBrandColor,
        brightness: Brightness.dark,
      ),
    ),
    home: Builder(
      builder:
          (context) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
                  () => tabs.add(),
              const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                  () => AppTray.newWindow(),
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
                  () => _close(tabs.selected),
              const SingleActivator(LogicalKeyboardKey.tab, control: true):
                  () => tabs.cycle(1),
              const SingleActivator(
                    LogicalKeyboardKey.tab,
                    control: true,
                    shift: true,
                  ):
                  () => tabs.cycle(-1),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                body: Column(
                  children: [
                    _tabBar(context),
                    Expanded(
                      child: IndexedStack(
                        index: tabs.tabs.indexWhere(
                          (tab) => tab.id == tabs.selected,
                        ),
                        children: [
                          for (final tab in tabs.tabs) _tabContent(tab),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    ),
  );

  Widget _tabContent(DriveTab tab) => KeyedSubtree(
    key: ValueKey(tab.id),
    child: ScaffoldMessenger(
      child: Navigator(
        key: _navigators.putIfAbsent(tab.id, GlobalKey<NavigatorState>.new),
        onGenerateRoute:
            (_) => MaterialPageRoute<void>(
              builder:
                  (_) => ListenableBuilder(
                    listenable: tab.state,
                    builder:
                        (context, _) =>
                            tab.state.isLoggedIn
                                ? FileBrowserPage(
                                  key: ObjectKey(tab.state.currentProvider),
                                  appState: tab.state,
                                )
                                : LoginPage(appState: tab.state),
                  ),
            ),
      ),
    ),
  );

  Widget _tabBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          const PiLogo(size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in tabs.tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Material(
                        color:
                            tab.id == tabs.selected
                                ? theme.colorScheme.surface
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => tabs.select(tab.id),
                          child: SizedBox(
                            width: 174,
                            height: 34,
                            child: Row(
                              children: [
                                const SizedBox(width: 10),
                                Icon(
                                  tab.state.isLoggedIn
                                      ? Icons.folder_open_rounded
                                      : Icons.cloud_outlined,
                                  size: 15,
                                  color:
                                      tab.id == tabs.selected
                                          ? kBrandColor
                                          : theme.hintColor,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    tab.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight:
                                          tab.id == tabs.selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: english ? 'Close tab' : '关闭标签页',
                                  onPressed: () => _close(tab.id),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 28,
                                    height: 28,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: english ? 'New tab (⌘T)' : '新建标签页 (⌘T)',
            icon: const Icon(Icons.add_rounded, size: 19),
            onSelected: (id) => tabs.add(providerID: id),
            itemBuilder:
                (_) => [
                  for (final provider in tabs.current.state.providers)
                    PopupMenuItem(
                      value: provider.id,
                      child: Text(provider.displayName),
                    ),
                ],
          ),
        ],
      ),
    );
  }
}
