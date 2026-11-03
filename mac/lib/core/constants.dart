/// 全局常量：品牌色、传输参数、超时等集中管理。
library;

import 'dart:ui' show Color;

/// 品牌主色（云朵蓝）
const Color kBrandColor = Color(0xFF2F6FED);

/// 品牌深色（渐变用）
const Color kBrandColorDark = Color(0xFF1B4BC4);

/// SVIP 账号最大并发下载数
const int kSvipMaxConcurrent = 8;

/// 普通账号最大并发下载数
const int kNormalMaxConcurrent = 1;

/// 下载分片大小（字节，1MB；小分片让断点续传粒度细）
const int kDownloadChunkSize = 1 * 1024 * 1024;

/// HTTP 请求默认超时
const Duration kHttpTimeout = Duration(seconds: 30);

/// 下载连接超时（直链 CDN 响应可能慢）
const Duration kDownloadTimeout = Duration(seconds: 60);

/// 上传超时（S3/OSS 分片上传）
const Duration kUploadTimeout = Duration(seconds: 120);
