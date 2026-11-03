import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_pan/core/state/app_state.dart';
import 'package:pi_pan/core/state/download_manager.dart';
import 'package:pi_pan/core/state/upload_manager.dart';
import 'package:pi_pan/core/state/workspace_tabs.dart';
import 'package:pi_pan/core/models/cloud_file.dart';
import 'package:pi_pan/core/providers/auth_provider.dart';
import 'package:pi_pan/ui/app.dart';
import 'package:pi_pan/ui/app_tray.dart';
import 'release_safety_test.dart' show FakeDrive, tick;

class MemoryAuth implements AuthProvider {
  @override
  String get providerId => 'baidu_client';
  @override
  Future<String?> getAccessToken() async => 'test-local-session';
  @override
  Future<void> logout() async {}
  @override
  Future<AuthSession> startLogin() async => const AuthSession.failed('test');
  @override
  Stream<AuthSession> get updates => const Stream.empty();
  @override
  Future<void> cancelLogin() async {}
}

class BrowseDrive extends FakeDrive {
  BrowseDrive(super.id);
  final paths = <String>[];
  @override
  AuthProvider get auth => MemoryAuth();
  @override
  Future<List<CloudFile>> list(String path) async {
    paths.add(path);
    return path == '/'
        ? [CloudFile(path: '/Projects', name: 'Projects', isDir: true)]
        : [];
  }
}

class LockedAuth extends MemoryAuth {
  @override
  Future<String?> getAccessToken() async =>
      throw StateError('test Keychain access denied');
}

class LockedDrive extends BrowseDrive {
  LockedDrive(super.id);
  @override
  AuthProvider get auth => LockedAuth();
}

void main() {
  test(
    'Unavailable saved credentials leave a recoverable login state',
    () async {
      final state = AppState(providers: [LockedDrive('baidu_client')]);
      addTearDown(state.dispose);
      expect(await state.selectProvider('baidu_client'), false);
      expect(state.isLoggedIn, false);
      expect(state.account, isNull);
    },
  );
  test('Each tab gets independent providers but the same transfer queues', () {
    final downloads = DownloadManager();
    final uploads = UploadManager();
    final tabs = WorkspaceTabs(downloads: downloads, uploads: uploads);
    addTearDown(tabs.dispose);
    final first = tabs.current;
    tabs.add(providerID: 'quark');
    expect(
      identical(
        first.state.providers.first,
        tabs.current.state.providers.first,
      ),
      false,
    );
    expect(
      identical(
        first.state.downloadManager,
        tabs.current.state.downloadManager,
      ),
      true,
    );
    expect(tabs.current.state.preferredProviderId, 'quark');
    tabs.select(first.id);
    expect(tabs.current, same(first));
  });
  test(
    'Closing a tab keeps its transfer alive and does not log out other tabs',
    () async {
      final downloads = DownloadManager();
      final uploads = UploadManager();
      final tabs = WorkspaceTabs(
        downloads: downloads,
        uploads: uploads,
        providerFactory: () => [FakeDrive('baidu_client'), FakeDrive('quark')],
      );
      addTearDown(tabs.dispose);
      final first = tabs.current;
      final provider = first.state.providers.first as FakeDrive;
      downloads.add(provider, '/one', '/tmp', 'one');
      tabs.add(providerID: 'quark');
      expect(tabs.close(first.id), true);
      expect(downloads.tasks.single.status, DownloadStatus.downloading);
      expect(tabs.current.state.preferredProviderId, 'quark');
      provider.downloads.single.end.complete();
      await tick();
      expect(downloads.tasks.single.status, DownloadStatus.done);
    },
  );
  test(
    'Last tab asks its native window to close instead of leaving an empty pane',
    () {
      final tabs = WorkspaceTabs(
        downloads: DownloadManager(),
        uploads: UploadManager(),
      );
      addTearDown(tabs.dispose);
      expect(tabs.close(tabs.selected), false);
      expect(tabs.tabs.length, 1);
    },
  );
  test(
    'Switching one tab cancels only transfers owned by its provider',
    () async {
      final downloads = DownloadManager()..maxConcurrent = 2;
      final uploads = UploadManager();
      final a = FakeDrive('baidu_client');
      final b = FakeDrive('quark');
      final state = AppState(
        downloadManager: downloads,
        uploadManager: uploads,
        providers: [a, b],
      );
      addTearDown(state.dispose);
      await state.selectProvider('baidu_client');
      downloads.add(a, '/one', '/tmp', 'one');
      downloads.add(b, '/two', '/tmp', 'two');
      final switchTab = state.selectProvider('quark');
      a.downloads.single.end.complete();
      await switchTab;
      expect(downloads.tasks.single.provider, same(b));
      expect(downloads.tasks.single.status, DownloadStatus.downloading);
    },
  );
  test(
    'Per-provider concurrency keeps a normal account at one active download',
    () {
      final manager = DownloadManager();
      final normal = FakeDrive('normal');
      final vip = FakeDrive('vip');
      manager.applyVipConcurrency(0, provider: normal);
      manager.applyVipConcurrency(2, provider: vip);
      manager.add(normal, '/a', '/tmp', 'a');
      manager.add(normal, '/b', '/tmp', 'b');
      manager.add(vip, '/c', '/tmp', 'c');
      expect(normal.downloads.length, 1);
      expect(vip.downloads.length, 1);
    },
  );
  test(
    'Late login callbacks cannot cancel transfers from a disposed tab',
    () async {
      final downloads = DownloadManager();
      final uploads = UploadManager();
      final a = BrowseDrive('baidu_client');
      final b = BrowseDrive('quark');
      final state = AppState(
        downloadManager: downloads,
        uploadManager: uploads,
        providers: [a, b],
      );
      await state.selectProvider(a.id);
      downloads.add(a, '/still-running', '/tmp', 'still-running');
      state.dispose();
      expect(await state.selectProvider(b.id), false);
      await state.logout();
      state.preferProvider(b.id);
      expect(state.currentProvider, same(a));
      expect(state.preferredProviderId, a.id);
      expect(downloads.tasks.single.status, DownloadStatus.downloading);
      a.downloads.single.end.complete();
      await tick();
      expect(downloads.tasks.single.status, DownloadStatus.done);
    },
  );
  testWidgets('Switching tabs preserves the original directory and navigator', (
    tester,
  ) async {
    final downloads = DownloadManager();
    final uploads = UploadManager();
    final tabs = WorkspaceTabs(
      downloads: downloads,
      uploads: uploads,
      providerFactory:
          () => [BrowseDrive('baidu_client'), BrowseDrive('quark')],
    );
    final first = tabs.current;
    await first.state.selectProvider('baidu_client');
    final drive = first.state.currentProvider as BrowseDrive;
    await tester.pumpWidget(
      PiPanApp(
        appState: AppState(downloadManager: downloads, uploadManager: uploads),
        tabs: tabs,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    expect(drive.paths, ['/', '/Projects']);
    tabs.add(providerID: 'quark');
    await tester.pumpAndSettle();
    tabs.select(first.id);
    await tester.pumpAndSettle();
    expect(find.text('Projects').hitTestable(), findsOneWidget);
    expect(drive.paths, ['/', '/Projects']);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(tabs.current.state.preferredProviderId, 'quark');
    await tester.pumpWidget(const SizedBox());
    tabs.dispose();
  });
  testWidgets('A logged-out tab can inspect transfers from a closed tab', (
    tester,
  ) async {
    final downloads = DownloadManager();
    final uploads = UploadManager();
    final tabs = WorkspaceTabs(
      downloads: downloads,
      uploads: uploads,
      providerFactory:
          () => [BrowseDrive('baidu_client'), BrowseDrive('quark')],
    );
    final source = tabs.current;
    final provider = source.state.providers.first as BrowseDrive;
    downloads.add(provider, '/background.zip', '/tmp', 'background.zip');
    tabs.add(providerID: 'quark');
    tabs.close(source.id);
    expect(tabs.current.state.isLoggedIn, false);
    await tester.pumpWidget(
      PiPanApp(
        appState: AppState(downloadManager: downloads, uploadManager: uploads),
        tabs: tabs,
      ),
    );
    await tester.pumpAndSettle();
    await AppTray.workspaceActions[0]!('openTransfers');
    await tester.pumpAndSettle();
    expect(find.text('background.zip'), findsOneWidget);
    expect(find.text(provider.displayName), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    provider.downloads.single.end.complete();
    await tester.pump();
    tabs.dispose();
  });
}
