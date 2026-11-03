/// 敏感凭据（access_token / refresh_token）的本地安全存储。
///
/// 凭据经 flutter_secure_storage 加密落盘（Windows DPAPI / macOS Keychain），
/// 避免明文 token 泄漏。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // macOS：关闭 Data Protection Keychain（插件默认开启）。
    // 无 Apple 开发证书的 ad-hoc 签名下，Data Protection 模式写入
    // 会报 -34018 (errSecMissingEntitlement)；登录钥匙串模式无此限制，
    // 首次写入系统会弹"允许访问钥匙串"授权框。
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  /// 保存某 provider 的凭据 JSON
  Future<void> save(String providerId, String credentialsJson) async {
    await _storage.write(key: 'token_$providerId', value: credentialsJson);
  }

  /// 读取凭据 JSON；不存在返回 null
  Future<String?> read(String providerId) async {
    return _storage.read(key: 'token_$providerId');
  }

  /// 清除某 provider 的凭据
  Future<void> clear(String providerId) async {
    await _storage.delete(key: 'token_$providerId');
  }
}
