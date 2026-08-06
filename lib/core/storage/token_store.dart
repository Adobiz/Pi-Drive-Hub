/// 敏感凭据（access_token / refresh_token）的本地安全存储。
///
/// Windows 下通过 flutter_secure_storage 走 DPAPI 加密落盘，
/// 避免明文 token 泄漏。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
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
