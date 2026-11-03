# PI 网盘 macOS 修复记录

日期：2026-11-02。版本：`1.0.0+1`。

后续更新：2026-11-03 已新增多窗口、独立网盘标签页、云朵菜单栏面板与圆润 Logo，自动化测试增至 44 项。下文保留传输安全修复当时的验证记录；最新结果见 [多窗口与菜单栏验证](WORKSPACE_UI_STATUS.md)。

**本轮已复现的代码缺陷已修复，27 项自动化测试全部通过，静态检查及 macOS Release 构建通过。** 可以提交开发中源码；正式安装包仍需 Developer ID 签名、公证及真实环境验收。

原始发现保存在 [修复前审计](RELEASE_READINESS.md)，该文件中的失败数描述历史状态。

## 修复结果

| 原始问题 | 当前行为 | 主要文件 |
| --- | --- | --- |
| R1 旧上传调度到新账号 | 每个任务固定绑定 Provider；取消旧会话并等待退出后再切换；旧回调不更新新任务 | [上传管理器](../lib/core/state/upload_manager.dart)、[账号状态](../lib/core/state/app_state.dart) |
| R2 覆盖同名文件 | 写入独立 `.pi-download-*` 目录；校验后独占创建目标；已有文件报错保留 | [下载目标](../lib/core/transfer/download_destination.dart) |
| R3 不完整分片假成功 | 校验 HTTP 状态、Content-Range 和实际字节数；失败不记录完成，也不生成最终文件 | [范围下载](../lib/core/transfer/range_download.dart) |
| R4 百度并发文件句柄冲突 | 网络可并发，文件定位与写入串行；正常并发文件的 SHA-256 比对通过 | [范围下载](../lib/core/transfer/range_download.dart) |
| R5 123 二进制解析异常 | 解析下载地址不再预先读取文件；限制大小的 JSON 重定向与二进制下载分开处理 | [123 API](../lib/providers/pan123/pan123_api.dart) |
| R6 上传取消无效 | 请求贯穿取消 token；保留底层 Abortable 信号；上传前、分片间、合并前检查取消 | [取消与 HTTP](../lib/core/transfer/cancellation.dart)、[上传管理器](../lib/core/state/upload_manager.dart) |
| R7 Cookie 发往任意域 | 旧凭据限定在所属服务域；新凭据保留域、路径、有效期与 host-only；只允许 HTTPS；重定向重建请求头 | [Cookie 容器](../lib/providers/baidu_client/cookie_jar.dart)、[登录保存](../lib/ui/official_login_view.dart) |
| R8 并发名额重复释放 | 运行集合仅在旧操作真正结束时移除；删除和退出不提前重置计数 | [下载管理器](../lib/core/state/download_manager.dart) |
| R9 分发身份与公证 | 已提供严格的发布脚本；**本机无 Developer ID Application 身份，尚未实际签名、公证** | [发布脚本](../scripts/release.sh) |

额外修正：

- 暂停任务不会被调度器自行恢复；快速暂停再继续时，同一任务要等待旧操作退出。
- 续传使用不截断模式打开私有临时文件，测试校验恢复后的全部字节。
- 删除任务仅清理所属临时目录，不删除同名用户文件。目录权限变化导致清理失败时，不破坏调度计数。
- 账号切换清除百度 bdstoken、夸克 fid 和 123 文件 ID/元信息缓存；异步登录结果检查会话代数。
- 123 搜索结果以命中 ID 区分同名文件；删除、重命名和下载不再把子目录命中误解析为根目录同名文件。
- 百度、夸克、123 的文件哈希改为流式计算并检查取消。百度分片上传直接读取文件流；夸克与 123 保留有界分片缓冲。
- 保留分片有限重试，夸克重试时可刷新直链；错误范围仍必须经过完整校验。

## 验证证据

| 验证 | 结果 |
| --- | --- |
| `flutter analyze --no-pub` | 无问题 |
| `flutter test --no-pub --reporter expanded` | 27 项全部通过 |
| `./build.sh` | 成功，应用约 51.4 MB |
| `bash -n build.sh scripts/release.sh scripts/sign-app.sh` | 通过 |
| GitHub Actions YAML 解析 | 通过；尚未在远端运行 |
| ZIP 结构与 SHA-256 校验 | 通过 |
| 应用签名结构 `codesign --verify --deep --strict` | 通过；仍为 ad-hoc 本地身份 |
| 发布脚本缺少凭据时 | 在构建、公证前失败，不产生正式发行包 |

27 项包含原始 12 项回归及 15 项补测，覆盖取消信号穿过多层 HTTP 客户端、multipart 内容保留、Cookie 迁移/路径/过期、跨域重定向、暂停恢复、排队、同名文件竞争、搜索命中 ID、异常分片、网络重试和空文件探测。

测试只使用模拟服务和临时文件，没有读取真实 Keychain 凭据、操作云端文件或向网盘上传内容。对照与异常分片分别验证；二进制正常用例补充了合法 Content-Range，以独立验证 UTF-8 缺陷，不放宽范围校验。

本机原始日志在 `audit/fix-analyze.txt`、`audit/fix-tests.txt` 和 `audit/fix-build.txt`，已在 `.gitignore` 中排除。

## GitHub 发布准备

- `test/` 下的测试现在由默认 `flutter test` 自动发现；原审计命令保留兼容入口。
- [macOS Actions](../.github/workflows/macos.yml) 检查源码、测试并构建，只保存明确标为 UNSIGNED 的测试制品，不自动发布 Release。
- `.gitignore` 新增分发包、证书、私钥、环境凭据及本地日志的忽略规则。
- 构建后原生 framework 的增量签名不一致已由 `scripts/sign-app.sh` 从内到外重签修复，并强制检查签名结构。本地使用 ad-hoc，正式流程使用 Developer ID。
- 本地包依据实际架构命名，附 SHA-256，输出到被忽略的 `build/distribution/`。
- [README](../README.md) 和 [发布教程](../GUIDE.md#9-发布与分发) 已更新，移除把绕过 Gatekeeper 当作正式安装方案的指引。
- [release.sh](../scripts/release.sh) 检查 Developer ID 和 Keychain profile，通过测试与构建后，从内到外签名、公证、附加票据及验证 Gatekeeper，最后生成正式发行 ZIP。

本轮没有初始化仓库、推送 GitHub、创建标签或发布 Release。根目录历史 ZIP 未被覆盖或删除，已被忽略并明确不作为当前发行包。

## 当前可用的本地测试包

```text
build/distribution/UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0.zip
build/distribution/UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0.zip.sha256
```

该包供本地验证，尚未通过 Developer ID 分发流程。

## 仍需完成

1. 在发布机器安装 Developer ID Application 证书和私钥，配置 `notarytool` Keychain profile，然后运行 `./scripts/release.sh`。当前身份查询为 0 个有效身份，因此没有尝试真实签名或提交公证。
2. 使用真实账号逐家验收登录、第三方协议、大文件及下载哈希、取消、切换账号和 Cookie/CDN 兼容性。自动化模拟通过不证明服务端当前协议可用。
3. 在全新 Mac 上测试浏览器下载后的安装、首次 Keychain 授权与升级；完成 Intel、低版本 macOS、睡眠唤醒和断网验收。静态架构检查不代替设备验收。
4. 推送目标 GitHub 仓库并实际运行 Actions；只有上述验收完成后，发布脚本生成的已签名、公证包才适合作为稳定版 Release 附件。

传输记录仍仅在内存中，不保证退出或崩溃后恢复。自动更新不在本轮范围内。公证依据：[Apple 站外分发](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html)、[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
