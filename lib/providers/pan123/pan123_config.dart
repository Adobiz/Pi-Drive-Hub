/// 123 云盘协议配置。
library;

class Pan123Config {
  /// 登录域名
  static const String loginBase = 'https://login.123pan.com/api';

  /// 业务 API 域名
  static const String apiBase = 'https://yun.123pan.com/b/api';

  /// 网页端 Referer/Origin
  static const String webBase = 'https://yun.123pan.com';

  /// 浏览器 UA（123 对 UA 敏感）
  static const String ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 存储 key（TokenStore）
  static const String storeKey = 'pan123';
}
