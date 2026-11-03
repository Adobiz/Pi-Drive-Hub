# PI 网盘 macOS：GitHub 发布检查

> **历史审计快照**：以下记录的是修复前状态。当前代码修复、验证结果和剩余发布条件请先看 [FIX_STATUS.md](FIX_STATUS.md)。

检查日期：2026-11-02（Asia/Shanghai）。检查版本：`1.0.0+1`。

**结论：可以作为开发中的开源项目上传 GitHub；当前不应发布稳定版安装包。**

Release 构建和静态检查通过，但针对传输安全的 12 个用例只有 2 个通过、10 个失败。失败覆盖文件覆盖、下载完整性、账号隔离和取消行为。另有分发签名阻断项。仅把版本标成 Beta 不能消除这些风险。

本轮仅新增审计报告、模拟测试和检查记录，没有修复业务代码，没有初始化 Git 仓库，也没有向 GitHub 推送或发布 Release。

## 已验证的结果

| 检查 | 结果 | 证据与边界 |
| --- | --- | --- |
| 静态检查 | 通过 | `flutter analyze --no-pub`，最终记录见 [analyze-results.txt](analyze-results.txt) |
| Release 构建 | 通过 | `flutter build macos --release --no-pub`，生成约 51.3 MB 的 `pi_pan.app` |
| 配置语法 | 通过 | Info.plist、两个 entitlements 的 `plutil -lint`，以及 `bash -n build.sh` |
| 现有包签名结构 | 通过完整性检查，但无发布身份 | `codesign --verify --deep --strict` 通过；签名是 ad-hoc |
| Gatekeeper | 拒绝 | 对现有 ZIP 解包后的应用执行 `spctl --assess --type execute --verbose=4`，结果 `rejected` |
| 公证票据 | 未附加 | `xcrun stapler validate`：`does not have a ticket stapled to it` |
| 自动化回归 | 2 通过，10 失败 | 全部使用假凭据、模拟 HTTP 和临时文件；见 [test-results.txt](test-results.txt) |
| 明显凭据特征扫描 | 未匹配 | 源码范围未匹配所查私钥、GitHub token、AWS access key 模式；不是完整秘密审计 |
| Git 仓库状态 | 尚未初始化 | 当前目录无 `.git`，`git status` 返回 `not a git repository` |

构建工具为 Flutter 3.44.7、Dart 3.12.2、Xcode 26.6。检查使用本地锁定依赖，没有做依赖更新。

现有下载包：`Pi-Drive-Hub-macos-arm64.zip`，20,000,576 字节。

```text
SHA-256: 379ee377f5e2367919400a1a1c2d6c5b2a9240b90d19769f5806ba06118a5b22
```

现有包和本次重建应用中的 Dart AOT 主体 `App.framework/Versions/A/App` 的 SHA-256 一致。这不代表整个应用逐字节可复现。主可执行文件同时包含 arm64 和 x86_64；ZIP 文件名只写了 arm64。架构存在不等于已经在 Intel Mac 上验收。

## 阻断项与修复方向

以下均按 P1 处理：正式 Release 前应修复或解决。优先处理账号隔离与本地文件安全。

### R1：旧上传任务会用旧网盘调度新网盘的任务

位置：[upload_manager.dart](../lib/core/state/upload_manager.dart#L184)。

`cancelAll()` 清空队列并把活动数重置为 0，但旧异步上传仍会结束。旧 `_run()` 随后调用 `_schedule(provider)`，把旧 Provider 交给新的队列。

复现：A 网盘上传尚未结束时清空任务；切换 B，添加两个上传；A 的旧上传结束。第二个 B 任务实际进入 A 的 `upload()`。模拟测试记录到 A 收到了 `new2.txt`。

修复：每个任务绑定 Provider 和账号会话；会话失效后禁止回调修改当前队列；旧任务完成时不把旧 Provider 带回调度器。取消后等待旧任务退出，再结算对应槽位。

### R2：下载会无提示覆盖用户已有的同名文件

位置：[file_browser_page.dart](../lib/ui/file_browser_page.dart#L230)、[baidu_client_api.dart](../lib/providers/baidu_client/baidu_client_api.dart#L483)。

下载按钮只选择目录，未检查目标文件冲突。下载后端直接写入最终路径。复现中，原有内容 `original-user-data` 被替换为一个下载字节。

修复：采用独立的 `.part` 临时文件；完成校验后再落到最终路径。目标已存在时明确选择覆盖、另存或跳过。并发下载同名文件也要分配不同临时路径。删除任务只能清理该任务拥有的临时文件。

### R3：百度和 123 会把不完整分片当作下载成功

位置：[baidu_client_api.dart](../lib/providers/baidu_client/baidu_client_api.dart#L584)、[pan123_api.dart](../lib/providers/pan123/pan123_api.dart#L378)。

两个下载实现都接受 200/206，未严格核对分片的 Content-Range 和实际字节数。模拟服务器只返回 1 字节时，两个下载方法仍正常返回。预分配文件长度会掩盖缺失数据。

修复：逐片校验状态码、范围和字节数；对忽略 Range 的响应执行明确的整文件回退策略或拒绝；校验失败不得记录完成分片。完成后核对总长度及服务端可信哈希（如可获得）。

### R4：百度正常并发下载会争用同一个文件句柄

位置：[baidu_client_api.dart](../lib/providers/baidu_client/baidu_client_api.dart#L525)。

多个 worker 共享一个 `RandomAccessFile`，分别异步调用 `setPosition()` 和 `writeFrom()`。3 并发、正确 Range 响应的用例触发 `FileSystemException: An async operation is currently pending`。相同内容的串行用例通过 SHA-256 比对。

修复：网络分片仍可并发，文件写入由单一写入队列串行完成；或使用能保证偏移写入隔离的实现。添加并发、乱序响应和暂停恢复后的整文件哈希校验。

### R5：123 直链返回普通二进制文件时会触发 UTF-8 异常

位置：[pan123_api.dart](../lib/providers/pan123/pan123_api.dart#L264)。

`getDownloadUrl()` 用 `_client.get()` 读取响应正文，再在 JSON 解析的 try 外执行 `utf8.decode()`。若直链或自动重定向最终返回文件，非 UTF-8 数据会直接抛异常。包含 JPEG 起始字节的用例复现 `FormatException: Invalid UTF-8 byte`。

该路径还会先把整个文件缓存在内存里，然后另行下载，存在重复流量和大文件内存风险。

修复：用流式请求读取状态和响应头；明确控制重定向。只对受大小限制的 JSON 响应解析文本，二进制响应直接交给下载流。

### R6：删除上传任务或退出登录并未可靠取消上传

位置：[upload_manager.dart](../lib/core/state/upload_manager.dart#L159)、[upload_manager.dart](../lib/core/state/upload_manager.dart#L224)。

`remove()` 和 `cancelAll()` 写入 `_canceledIds`，但上传执行回调只检查 `_generations`，没有读取该集合。删除和退出登录后，模拟上传的后续进度回调均未中止。底层 Provider 接口也没有上传取消参数。

修复：将取消信号贯穿 manager、Provider 和 HTTP 请求；在发送、分片、提交前检查；删除任务和退出登录必须让正在执行的上传停止。仅从列表移除任务不算取消。

### R7：恢复的登录 Cookie 会被附加到任意请求域名

位置：[cookie_jar.dart](../lib/providers/baidu_client/cookie_jar.dart#L48)。

`loadMap()` 丢失域、路径和 Secure 属性；无 domain 的 Cookie 在 `headerFor()` 中对任意 host 都发送。测试中，假 `BDUSS` 出现在 `https://unrelated.example/file` 的请求头中。百度和夸克下载链路使用该容器构造 Cookie 头。

这是已复现的凭据作用域缺陷，不代表已经发现真实账号泄漏。

修复：保存和恢复完整的 Cookie 作用域；使用明确的服务和 CDN 域名策略；限制协议并审查跨域重定向。不能为了让 CDN 下载成功而把全部会话 Cookie 发往任意直链。

### R8：删除下载任务会重复释放并发名额

位置：[download_manager.dart](../lib/core/state/download_manager.dart#L251)、[download_manager.dart](../lib/core/state/download_manager.dart#L216)。

`remove()` 先减 `_activeCount` 并调度新任务，旧 `_run()` 收尾时又减一次。并发上限为 1 的测试最终出现 2 个 downloading 任务。清空任务后旧任务回调也需要隔离。

修复：只在旧任务实际退出时释放对应名额，且恰好一次。取消后不让旧任务修改新会话计数；清理文件也应等待该任务停止写入。

### R9：现有包无法通过正常 macOS 分发验证

位置：[build.sh](../build.sh)、[Release.entitlements](../macos/Runner/Release.entitlements)。

现有 ZIP 内应用及本次构建均为 `Signature=adhoc`，`TeamIdentifier=not set`。签名标记不含 hardened runtime。现有包经系统检查被 Gatekeeper 拒绝，且没有附加公证票据。

GitHub 托管下载不会替代 macOS 的签名、公证验证。正式站外分发应完成 Developer ID 签名、hardened runtime 和公证，并验证票据与干净机器安装体验。依据：[Apple 站外分发说明](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html)、[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

关闭 App Sandbox 本身不是 GitHub 站外分发的阻断项；本次目标按 GitHub Release 评估，不要求改为 Mac App Store 分发。

`GUIDE.md` 的公证示例直接提交 `.app`，且没有实际执行 staple 步骤。应改为可执行的 ZIP/DMG 提交、查询结果、staple 和 verify 流程，不能把 `xattr -cr` 当作正式用户安装方案。

## 还需要验证的功能与边界

- **真实服务可用性未验收**：未使用百度、夸克或 123 的真实账号；不能确认当前非官方协议、扫码、验证码、会员识别及服务端错误兼容性。
- **内存风险由代码确认、未做压力测量**：百度上传及夸克上传会读取整个文件。多 GB 文件、并发上传和内存峰值应实测并改为流式处理。
- **账号缓存隔离待验证**：123 的路径与元信息缓存、夸克的 fid 缓存保存在长生命周期 Provider 中。登出后换同服务的另一个账号，应测试同名目录及文件操作是否沿用旧 ID。
- **123 搜索结果操作待验证**：`search()` 把结果转换为根路径形式，后续操作按路径重新解析，未沿用搜索命中的 remoteId。子目录同名文件需要重点检查，尤其是删除和重命名。
- **断点记录未持久化**：传输任务和已完成分片保存在内存中。没有证据证明退出或崩溃重启后仍可恢复；UI 关闭路径直接 `exit(0)`。
- **安装兼容性待验证**：未完成实际 UI 验收、全新机器安装、钥匙串首次授权、升级授权、Intel 运行、低版本 macOS、睡眠唤醒和断网恢复。源码最低版本为 10.15，README 写 12+，应按实测统一。
- **原有自动化不足**：没有标准 `test/` 或 `integration_test/` 测试集；原生 `RunnerTests.swift` 只有空示例。本次 `audit/` 用例需显式运行，不能依赖默认 `flutter test` 自动发现。

## 针对 GitHub 的准备清单

### 如果现在只上传源码

1. 在 README 顶部明确标注“开发中，暂不提供稳定版”，链接已知问题和本报告。
2. 初始化仓库前补充忽略 Release ZIP/DMG、证书、私钥、`.env` 和本地审计日志。当前 `.gitignore` 已排除 build、Pods 和 Flutter 临时目录，但没有排除根目录 ZIP。
3. 保留应用所需的 `third_party/tray_manager_local`、`pubspec.lock` 和 `macos/Podfile.lock`。保留现有 MIT 许可证、第三方许可证和上游项目说明。
4. 明确目标 GitHub 仓库、拥有者和可见性。当前目录没有 remote，不能直接执行已有仓库的 push。
5. 上传源码前复核暂存文件，排除账号 Cookie、网盘文件截图和本机日志。此次特征扫描没有发现所查凭据，不等于对任意格式的秘密做出保证。

### 发布安装包前

1. 修复 R1–R8，让本次 12 个用例全部通过，并为修复增加必要的正常、取消和异常回归。
2. 将稳定测试纳入 `test/` 或 CI 的显式测试命令；建立 macOS 构建和测试检查。
3. 用真实账号完成三家服务的独立验收，至少包括二进制与大文件、下载哈希、暂停恢复、取消、登出换号及同名文件。
4. 完成 R9 的签名和公证；在下载产生 quarantine 标记的全新环境中验证安装。不要用开发机直接运行代替此项。
5. 统一应用版本、支持系统和架构标识。重新打包并生成最终 ZIP/DMG 的 SHA-256；将二进制作为 Release 附件，源码仓库保留源文件。
6. 修订 README/GUIDE 的功能承诺、公证命令和安装说明；提供版本说明、问题反馈入口及已知限制。首次对外验证可使用 prerelease，但仍需先消除数据安全缺陷。

## 复现命令

```bash
flutter analyze --no-pub
flutter test --no-pub audit/release_audit_test.dart --reporter expanded
flutter build macos --release --no-pub
```

第二条命令在当前代码上预期失败：这些断言表达修复后应达到的行为，没有把缺陷当作正确结果。模拟测试不连接网盘，不读取真实 Keychain 凭据，不改动用户云端文件。
