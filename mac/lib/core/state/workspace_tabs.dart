import 'package:flutter/foundation.dart';
import '../providers/cloud_provider.dart';
import 'app_state.dart';
import 'download_manager.dart';
import 'upload_manager.dart';

class DriveTab {
  final int id;
  final AppState state;
  DriveTab(this.id, this.state);
  String get title =>
      state.currentProvider?.displayName ??
      state.providers
          .firstWhere(
            (p) => p.id == state.preferredProviderId,
            orElse: () => state.providers.first,
          )
          .displayName;
}

/// Every tab has independent authentication objects and navigation state.
/// Transfers remain in the application queue after a tab or window closes.
class WorkspaceTabs extends ChangeNotifier {
  final DownloadManager downloads;
  final UploadManager uploads;
  final List<CloudProvider> Function()? providerFactory;
  final List<DriveTab> _tabs = [];
  int _nextID = 0;
  int selected = 0;
  WorkspaceTabs({
    required this.downloads,
    required this.uploads,
    this.providerFactory,
  }) {
    add();
  }
  List<DriveTab> get tabs => List.unmodifiable(_tabs);
  DriveTab get current => _tabs.firstWhere((tab) => tab.id == selected);
  void add({String? providerID}) {
    final state = AppState(
      downloadManager: downloads,
      uploadManager: uploads,
      providers: providerFactory?.call(),
      preferredProviderId: providerID,
    );
    state.addListener(notifyListeners);
    final tab = DriveTab(_nextID++, state);
    _tabs.add(tab);
    selected = tab.id;
    notifyListeners();
  }

  void select(int id) {
    if (!_tabs.any((tab) => tab.id == id)) return;
    selected = id;
    notifyListeners();
  }

  bool close(int id) {
    if (_tabs.length <= 1) return false;
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return true;
    final tab = _tabs.removeAt(index);
    tab.state.removeListener(notifyListeners);
    tab.state.dispose();
    if (selected == id) {
      selected = _tabs[(index - 1).clamp(0, _tabs.length - 1)].id;
    }
    notifyListeners();
    return true;
  }

  void cycle(int direction) {
    final index = _tabs.indexWhere((tab) => tab.id == selected);
    select(_tabs[(index + direction) % _tabs.length].id);
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.state.removeListener(notifyListeners);
      tab.state.dispose();
    }
    super.dispose();
  }
}
