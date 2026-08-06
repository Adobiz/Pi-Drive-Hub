/// 轻量国际化：构建时通过 --dart-define=APP_LANG=zh|en 注入语言。
///
/// 默认中文；构建参数 `--dart-define=APP_LANG=en` 时全部 UI 文本切英文。
/// 用法：AppStrings.appName / AppStrings.selectedCount(n)
library;

/// 当前语言（zh / en），由构建参数注入
const String appLang = String.fromEnvironment('APP_LANG', defaultValue: 'zh');

bool get _isEn => appLang == 'en';

/// 全部 UI 文本（zh/en 双套）
class AppStrings {
  AppStrings._();

  // ---------- 通用 ----------
  static String get appName => _isEn ? 'Pi Drive Hub' : 'PI 网盘';
  static String get tagline => _isEn ? 'Clean · Ad-free · Multi-drive' : '干净 · 无广告 · 多网盘';
  static String get cancel => _isEn ? 'Cancel' : '取消';
  static String get confirm => _isEn ? 'OK' : '确定';
  static String get delete => _isEn ? 'Delete' : '删除';
  static String get create => _isEn ? 'Create' : '创建';
  static String get search => _isEn ? 'Search' : '搜索';
  static String get refresh => _isEn ? 'Refresh' : '刷新';
  static String get more => _isEn ? 'More' : '更多';
  static String get logout => _isEn ? 'Log out' : '退出登录';
  static String get upload => _isEn ? 'Upload' : '上传';
  static String get download => _isEn ? 'Download' : '下载';
  static String get rename => _isEn ? 'Rename' : '重命名';
  static String get allFiles => _isEn ? 'All files' : '全部文件';
  static String get loginSuccess => _isEn ? 'Logged in' : '登录成功';
  static String get loginIncomplete => _isEn ? 'Login incomplete or session invalid' : '登录未完成或会话无效';
  static String get enterAccount => _isEn ? 'Please enter account and password' : '请输入账号和密码';
  static String get loggingIn => _isEn ? 'Logging in…' : '正在登录…';
  static String get opening => _isEn ? 'Opening…' : '正在打开…';

  // ---------- 登录页 ----------
  static String get selectProvider => _isEn ? 'Select drive' : '选择网盘通道';
  static String get openLoginPage => _isEn ? 'Open official login page' : '打开官方登录网页';
  static String get accountOrEmail => _isEn ? 'Phone or email' : '手机号或邮箱';
  static String get password => _isEn ? 'Password' : '密码';
  static String get login => _isEn ? 'Log in' : '登录';
  static String get pan123Note => _isEn ? '123 Drive uses account & password (no QR)' : '123云盘需账号密码登录（无扫码）';
  static String get webLoginTitle => _isEn ? 'Drive account login' : '网盘账号登录';

  // ---------- 文件浏览器 ----------
  static String get batchDeleteTitle => _isEn ? 'Batch delete confirm' : '批量删除确认';
  static String batchDeleteContent(int n) =>
      _isEn ? 'Delete $n selected items? This cannot be undone.' : '确定删除选中的 $n 个项目吗？此操作不可恢复。';
  static String deletedCount(int n) => _isEn ? 'Deleted $n items' : '已删除 $n 个项目';
  static String get batchDeleteFailed => _isEn ? 'Batch delete failed: ' : '批量删除失败: ';
  static String addedToDownload(int n) =>
      _isEn ? '$n files added to download queue' : '已加入下载队列 $n 个文件';
  static String get searchFailed => _isEn ? 'Search failed: ' : '搜索失败: ';
  static String get newFolder => _isEn ? 'New folder' : '新建文件夹';
  static String get addedToUpload => _isEn ? 'Added to upload queue' : '已加入上传队列';
  static String get addedToDownloadQueue => _isEn ? 'Added to download queue' : '已加入下载队列';
  static String get renameFolder => _isEn ? 'Rename folder' : '重命名文件夹';
  static String get renameFile => _isEn ? 'Rename file' : '重命名文件';
  static String get renameFailed => _isEn ? 'Rename failed: ' : '重命名失败: ';
  static String get deleteTitle => _isEn ? 'Delete confirm' : '删除确认';
  static String deleteContent(String name) =>
      _isEn ? 'Delete "$name"? This cannot be undone.' : '确定删除「$name」吗？此操作不可恢复。';
  static String get deleteFailed => _isEn ? 'Delete failed: ' : '删除失败: ';
  static String get selectAll => _isEn ? 'Select all' : '全选';
  static String get searchHint => _isEn ? 'Search file name' : '搜索文件名';
  static String get searchEmptyHint => _isEn ? 'Type keyword to search files' : '输入关键词搜索文件';
  static String get searchNoResult => _isEn ? 'No matching files' : '未找到匹配文件';
  static String get dirEmpty => _isEn ? 'This folder is empty' : '此目录为空';
  static String get downloadManager => _isEn ? 'Downloads' : '下载管理';
  static String get batchDelete => _isEn ? 'Batch delete' : '批量删除';
  static String get batchDownload => _isEn ? 'Batch download' : '批量下载';
  static String get createFailed => _isEn ? 'Create failed: ' : '创建失败: ';
  static String selectedCount(int n) => _isEn ? '$n selected' : '已选 $n 项';

  // ---------- 传输管理（download_page） ----------
  static String get svipConcurrent => _isEn ? 'SVIP: multi-task concurrent' : 'SVIP 可多任务并发';
  static String get normalConcurrent => _isEn ? 'Normal: 1 task' : '普通账号限 1 个';
  static String get clearFinished => _isEn ? 'Clear finished' : '清除已完成';
  static String get tabDownload => _isEn ? 'Downloads' : '下载';
  static String get tabUpload => _isEn ? 'Uploads' : '上传';
  static String get concurrentCount => _isEn ? 'Concurrent downloads' : '同时下载数量';
  static String get noDownloadTasks => _isEn ? 'No download tasks' : '暂无下载任务';
  static String get noUploadTasks => _isEn ? 'No upload tasks' : '暂无上传任务';
  static String get resume => _isEn ? 'Resume' : '继续';
  static String get pause => _isEn ? 'Pause' : '暂停';
}
