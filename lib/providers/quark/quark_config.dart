/// 夸克网盘协议配置。
library;

class QuarkConfig {
  /// 网页版 API 域名
  static const String driveBase = 'https://drive.quark.cn/1/clouddrive';

  /// 网盘首页（登录成功后跳转、Referer 用）
  static const String homeBase = 'https://pan.quark.cn';

  /// 用户信息接口（独立域名）
  static const String accountBase = 'https://pan.quark.cn/account/info';

  /// 夸克 Electron UA
  static const String ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/3.14.2 Chrome/112.0.5615.165 Electron/24.1.3.8 Safari/537.36';

  /// 登录页（WebView 加载）
  static const String loginUrl = 'https://pan.quark.cn/';

  /// 存储 key（TokenStore）
  static const String storeKey = 'quark';
}
