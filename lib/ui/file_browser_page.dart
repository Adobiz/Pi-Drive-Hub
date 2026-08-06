/// 文件浏览页：干净的文件管理界面。
/// 支持：目录导航、新建文件夹、上传、下载、重命名、删除、刷新。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/i18n/strings.dart';
import '../core/models/cloud_file.dart';
import '../core/providers/cloud_provider.dart';
import '../core/state/app_state.dart';
import '../providers/baidu_client/baidu_client_provider.dart';
import '../providers/pan123/pan123_provider.dart';
import '../providers/quark/quark_provider.dart';
import 'download_page.dart';
import 'pi_logo.dart';

class FileBrowserPage extends StatefulWidget {
  final AppState appState;

  const FileBrowserPage({super.key, required this.appState});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  late final provider = widget.appState.currentProvider!;
  String _currentPath = '/';
  List<CloudFile>? _files;
  String? _error;

  // 搜索状态
  bool _searchMode = false;
  final _searchCtrl = TextEditingController();
  List<CloudFile>? _searchResults;
  bool _searching = false;

  // 多选状态
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final files = await provider.list(_currentPath);
      if (mounted) setState(() => _files = files);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _doSearch() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty) return;
    setState(() {
      _searching = true;
      _searchResults = null;
    });
    try {
      // 客户端协议 Provider 支持 search；其他通道提示不支持
      final results = await _searchFiles(provider, kw);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
        if (results.isEmpty) _toast('未找到匹配文件');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        _toast('${AppStrings.searchFailed}$e');
      }
    }
  }

  /// 搜索（按网盘类型分发；不支持搜索的返回空）
  Future<List<CloudFile>> _searchFiles(CloudProvider provider, String kw) async {
    if (provider is BaiduClientProvider) {
      return provider.search(kw);
    }
    if (provider is QuarkProvider) {
      return provider.search(kw);
    }
    if (provider is Pan123Provider) {
      return provider.search(kw);
    }
    return <CloudFile>[];
  }

  void _exitSearch() {
    setState(() {
      _searchMode = false;
      _searchResults = null;
      _searchCtrl.clear();
    });
  }

  void _toggleSelection(CloudFile f) {
    setState(() {
      if (_selectedPaths.contains(f.path)) {
        _selectedPaths.remove(f.path);
        if (_selectedPaths.isEmpty) _selectionMode = false;
      } else {
        _selectedPaths.add(f.path);
        _selectionMode = true;
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  /// 批量删除
  Future<void> _batchDelete() async {
    if (_selectedPaths.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.batchDeleteTitle),
        content: Text(AppStrings.batchDeleteContent(_selectedPaths.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppStrings.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final paths = _selectedPaths.toList();
      if (provider is BaiduClientProvider) {
        await (provider as BaiduClientProvider).deleteBatch(paths);
      } else {
        // 其他通道逐个删除
        for (final p in paths) {
          await provider.delete(p);
        }
      }
      _toast(AppStrings.deletedCount(paths.length));
      _exitSelection();
      await _load();
    } catch (e) {
      _toast('${AppStrings.batchDeleteFailed}$e');
    }
  }

  /// 批量下载
  Future<void> _batchDownload() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    for (final f in _allVisibleFiles) {
      if (_selectedPaths.contains(f.path) && !f.isDir) {
        widget.appState.downloadManager.add(provider, f.path, dir, f.name);
      }
    }
    _toast(AppStrings.addedToDownload(_selectedPaths.length));
    _exitSelection();
  }

  /// 当前展示的所有文件（目录浏览或搜索结果）
  List<CloudFile> get _allVisibleFiles =>
      _searchMode ? (_searchResults ?? const []) : (_files ?? const []);

  // ---- 操作 ----

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.newFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppStrings.create),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await provider.createFolder(_currentPath, name);
      await _load();
    } catch (e) {
      _toast('${AppStrings.createFailed}$e');
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      // 交给上传管理器：后台上传 + 实时进度
      widget.appState.uploadManager.add(provider, path, _currentPath);
    }
    _toast(AppStrings.addedToUpload);
    await _load();
  }

  Future<void> _download(CloudFile file) async {
    if (file.isDir) return;
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    // 交给下载管理器：后台下载 + 实时进度
    widget.appState.downloadManager.add(provider, file.path, dir, file.name);
    _toast(AppStrings.addedToDownloadQueue);
  }

  Future<void> _rename(CloudFile file) async {
    final controller = TextEditingController(text: file.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(file.isDir ? AppStrings.renameFolder : AppStrings.renameFile),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppStrings.confirm),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == file.name) return;
    try {
      await provider.rename(file.path, newName);
      await _load();
    } catch (e) {
      _toast('${AppStrings.renameFailed}$e');
    }
  }

  Future<void> _delete(CloudFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.deleteTitle),
        content: Text(AppStrings.deleteContent(file.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppStrings.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await provider.delete(file.path);
      await _load();
    } catch (e) {
      _toast('${AppStrings.deleteFailed}$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_selectionMode)
              _buildSelectionBar()
            else if (_searchMode)
              _buildSearchBar()
            else ...[
              _buildTopBar(),
              _buildBreadcrumb(),
            ],
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: _searchMode ? null : buildBottomBar(),
    );
  }

  /// 多选模式顶栏
  Widget _buildSelectionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _exitSelection,
          ),
          Text(
            AppStrings.selectedCount(_selectedPaths.length),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            tooltip: AppStrings.selectAll,
            icon: const Icon(Icons.select_all),
            onPressed: () {
              setState(() {
                _selectedPaths
                  ..clear()
                  ..addAll(_allVisibleFiles.map((f) => f.path));
                _selectionMode = true;
              });
            },
          ),
        ],
      ),
    );
  }

  /// 搜索模式顶栏
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _exitSearch,
          ),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppStrings.searchHint,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onSubmitted: (_) => _doSearch(),
              textInputAction: TextInputAction.search,
            ),
          ),
          IconButton(
            icon: _searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            onPressed: _doSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final account = widget.appState.account;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
      child: Row(
        children: [
          const PiLogo(size: 28),
          const SizedBox(width: 8),
          Text(provider.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          if (account != null && account.quotaText.isNotEmpty)
            Text(account.quotaText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 12),
          if (account != null && account.vipType != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: account.vipType! >= 2
                    ? const Color(0xFFFFB300)
                    : (account.vipType! == 1
                        ? const Color(0xFFFF7043)
                        : const Color(0xFF9E9E9E)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                account.vipText,
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: AppStrings.search,
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _searchMode = true;
                _searchResults = null;
              });
            },
          ),
          IconButton(
            tooltip: AppStrings.downloadManager,
            icon: const Icon(Icons.download),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DownloadPage(
                    manager: widget.appState.downloadManager,
                    uploadManager: widget.appState.uploadManager,
                    provider: provider,
                    vipType: widget.appState.account?.vipType ?? 0,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: AppStrings.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          PopupMenuButton<String>(
            tooltip: AppStrings.more,
            onSelected: (v) {
              if (v == 'logout') widget.appState.logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'logout', child: Text(AppStrings.logout)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final segs = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            _crumb(AppStrings.allFiles, () => _goTo('/')),
            for (var i = 0; i < segs.length; i++) ...[
              const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              _crumb(segs[i], () => _goTo('/${segs.sublist(0, i + 1).join('/')}')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _crumb(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  void _goTo(String path) {
    setState(() {
      _currentPath = path;
      _files = null;
    });
    _load();
  }

  Widget _buildBody() {
    if (_searchMode) {
      final results = _searchResults;
      if (results == null) {
        return Center(
            child: Text(AppStrings.searchEmptyHint, style: TextStyle(color: Colors.grey)));
      }
      if (results.isEmpty) {
        return Center(
            child: Text(AppStrings.searchNoResult, style: TextStyle(color: Colors.grey)));
      }
      return _buildFileList(results);
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    final files = _files;
    if (files == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (files.isEmpty) {
      return Center(child: Text(AppStrings.dirEmpty, style: TextStyle(color: Colors.grey)));
    }
    return _buildFileList(files);
  }

  /// 文件列表（目录浏览和搜索结果共用）
  Widget _buildFileList(List<CloudFile> files) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
      itemBuilder: (context, i) {
        final f = files[i];
        final selected = _selectedPaths.contains(f.path);
        return ListTile(
          selected: _selectionMode && selected,
          leading: _selectionMode
              ? Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? kBrandColor
                      : Colors.grey,
                )
              : _iconFor(f),
          title: Text(f.name),
          subtitle: f.isDir ? null : Text(f.sizeText),
          onTap: () {
            if (_selectionMode) {
              _toggleSelection(f);
            } else if (!_searchMode && f.isDir) {
              _goTo(f.path);
            }
          },
          onLongPress: () => _toggleSelection(f),
          trailing: _selectionMode
              ? null
              : PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'download':
                  _download(f);
                case 'rename':
                  _rename(f);
                case 'delete':
                  _delete(f);
              }
            },
            itemBuilder: (_) => [
              if (!f.isDir) PopupMenuItem(value: 'download', child: Text(AppStrings.download)),
              PopupMenuItem(value: 'rename', child: Text(AppStrings.rename)),
              PopupMenuItem(value: 'delete', child: Text(AppStrings.delete)),
            ],
          ),
        );
      },
    );
  }

  Widget _iconFor(CloudFile f) {
    if (f.isDir) {
      return const Icon(Icons.folder, color: Color(0xFFFFB300), size: 32);
    }
    return const Icon(Icons.insert_drive_file, color: Colors.grey, size: 32);
  }

  // 底部操作栏（多选模式显示批量操作）
  Widget buildBottomBar() {
    if (_selectionMode) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: _selectedPaths.isEmpty ? null : _batchDelete,
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.delete_outline),
              label: Text(AppStrings.batchDelete),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _selectedPaths.isEmpty ? null : _batchDownload,
              icon: const Icon(Icons.download),
              label: Text(AppStrings.batchDownload),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            onPressed: _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(AppStrings.newFolder),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: _upload,
            icon: const Icon(Icons.upload_file),
            label: Text(AppStrings.upload),
          ),
        ],
      ),
    );
  }
}
