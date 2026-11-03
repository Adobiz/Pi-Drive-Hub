/// 认证层抽象接口。
///
/// 两种实现路线：
/// 1. 官方开放平台 OAuth（合规，推荐）
/// 2. 模拟官方客户端私有协议（功能全但违反条款，需自行承担风险）
///
/// UI 只面向本接口，切换实现不影响上层代码。
library;

import 'dart:async';

/// 登录流程的各个阶段
enum AuthStatus {
  /// 等待用户扫码
  waitingForScan,

  /// 用户已扫码，等待确认
  confirmed,

  /// 已拿到 token，登录成功
  success,

  /// 登录失败或已过期
  failed,
}

/// 一次登录会话的状态快照
class AuthSession {
  final AuthStatus status;

  /// 二维码内容（或授权 URL），status 为 waitingForScan 时有值
  final String? qrContent;

  /// 错误信息，status 为 failed 时有值
  final String? error;

  const AuthSession({
    required this.status,
    this.qrContent,
    this.error,
  });

  const AuthSession.waiting(String qr) : this(status: AuthStatus.waitingForScan, qrContent: qr);
  const AuthSession.confirmed() : this(status: AuthStatus.confirmed);
  const AuthSession.success() : this(status: AuthStatus.success);
  const AuthSession.failed(String message) : this(status: AuthStatus.failed, error: message);
}

abstract class AuthProvider {
  /// Provider 唯一 id（如 `baidu`）
  String get providerId;

  /// 开始登录流程。
  ///
  /// 返回首个会话快照（通常为 waitingForScan，含二维码内容）。
  /// 后续进展通过 [updates] 流推送。
  Future<AuthSession> startLogin();

  /// 登录过程中的状态更新流（扫码确认、成功、失败等）
  Stream<AuthSession> get updates;

  /// 取消当前登录流程（轮询应停止）
  Future<void> cancelLogin();

  /// 当前有效的 access token；未登录或过期时返回 null
  Future<String?> getAccessToken();

  /// 退出登录，清除本地凭据
  Future<void> logout();
}
