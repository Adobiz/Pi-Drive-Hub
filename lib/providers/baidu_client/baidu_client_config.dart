/// 百度网盘客户端协议（非官方通道）配置。
///
/// 该通道模拟百度网盘 PC 客户端，使用 BDUSS 会话 cookie，
/// 可操作用户网盘任意目录（不受 /apps 限制）。
library;

class BaiduClientConfig {
  /// 网盘客户端 app_id（BaiduPCS-Go 同款）
  static const String appId = '250528';

  /// 客户端 UA（伪装成百度网盘 Android 客户端，文件 API 用）
  static const String ua =
      'netdisk;P2SP;3.0.0.8;netdisk;11.12.3;ANG-AN00;android-android;10.0;JSbridge4.4.0;jointBridge;1.1.0;';

  /// 网盘首页 API 域名（api/*、首页）
  static const String panBase = 'https://pan.baidu.com';

  /// PCS 文件 API 域名（rest/2.0/pcs/*，BaiduPCS-Go 同款）
  static const String pcsFileBase = 'https://pcs.baidu.com';

  /// 上传分片大小（4MB，最小分片）
  static const int blockSize = 4 * 1024 * 1024;


}
