<div align="center">

# PI 网盘 (macOS)

轻量、无广告的多网盘客户端，支持百度网盘、夸克网盘和 123 云盘。

</div>

> **当前为开发验证版本，尚未完成正式发布验收。** 自动化检查、构建和本地安装包检查已通过；真实账号、全新机器安装及签名公证仍需验收。查看 [最新发布前复查](audit/PRE_GITHUB_REVIEW.md) 和 [GitHub 上传与 DMG 发布教程](docs/GITHUB_PUBLISHING.md)。历史测试包不作为正式安装包。

基于 [PI-Drive-Hub](https://github.com/Adobiz/PI-Drive-Hub) 的 macOS 移植，使用 Flutter 和各服务的非官方客户端协议。协议及平台代码已在本项目独立修改，不能再按“逐字节一致”覆盖同步。

## 功能与限制

- 百度、夸克通过内嵌官方登录页登录；123 使用账号密码登录。
- 登录凭据保存在本机 Keychain。Cookie 按服务域名、路径及有效期发送，下载重定向逐跳重建请求头。
- 文件浏览、搜索、新建文件夹、重命名、删除、上传及下载。部分接口能力没有对应的 UI 入口。
- 支持多个独立窗口和网盘标签页。每个标签页保留自己的网盘会话、目录与导航；同一窗口共用传输队列。
- 单击菜单栏的圆润云朵，查看所有窗口的传输任务、实时下载/上传速率、最近 60 秒曲线、会话流量与暂停/继续操作。
- 应用图标和登录页采用统一的圆角云朵与 π 标识，菜单栏图标随系统明暗主题显示。
- 下载使用任务独立的临时文件；分片校验通过后生成最终文件。**同名目标已存在时任务失败，保留原文件**，可另选目录或先重命名文件。
- 支持进程内暂停和继续；上传继续会重新开始。暂停的任务不会被自动恢复。**退出或崩溃重启后不保证续传**。
- 百度支持并发分片，分片写入按顺序串行执行。上传哈希和百度上传文件流不再读取整个文件到内存；夸克与 123 上传仍保留有界分片缓冲。
- 关闭标签页不停止后台传输；关闭窗口后，有进行中、排队或暂停任务的窗口会在后台保留。通过菜单栏或 Dock 可重新打开。使用「退出 PI 网盘」或 ⌘Q 才会退出进程并中断任务。暂不提供自动更新，通过 GitHub Release 手动更新。

不保证绕过服务端限速、会员限制、验证码或风控。请在自己的测试文件和目录上验证第三方协议兼容性。

## 窗口与标签页

标签栏右上角仅保留「＋」，用于选择网盘并添加标签页。新建窗口通过 ⌘N 或「文件」菜单操作。

| 快捷键 | 操作 |
| --- | --- |
| ⌘N | 新建独立窗口 |
| ⌘T | 新建网盘标签页；标签栏的「＋」可选择网盘 |
| ⌘W | 关闭当前标签页；最后一个标签页会关闭窗口 |
| ⇧⌘W | 关闭当前窗口 |
| Control + Tab / Control + Shift + Tab | 下一个 / 上一个标签页 |

标签页之间不会共享 Provider 的可变状态；账号切换只处理该标签页所属的传输。同一网盘的 Keychain 凭据仍按服务保存一份，多账号同时登录尚未验收。传输管理显示当前窗口所有标签页的任务；菜单栏汇总所有窗口。

界面预览使用离线演示数据：[浅色面板](docs/previews/transfers-light.png)、[深色面板](docs/previews/transfers-dark.png)。本轮验证见 [多窗口与菜单栏验证记录](audit/WORKSPACE_UI_STATUS.md)。

## 本地构建与检查

本机验证工具链为 Flutter 3.44.7、Dart 3.12.2、Xcode 26.6、CocoaPods。建议在 macOS 12+ 开发与测试；工程当前最低部署版本为 10.15，低版本和 Intel 运行仍需单独验收。

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
./build.sh          # 中文本地测试包
./build.sh en       # 英文本地测试包
```

应用位于 `build/macos/Build/Products/Release/pi_pan.app`。构建脚本会先修复本地 ad-hoc 签名结构，再生成 ZIP、DMG 和对应的 SHA-256，路径为 `build/distribution/UNSIGNED-*`。DMG 提供 App 与 Applications 拖拽入口。它们**仅供开发测试，未完成 Developer ID 分发签名或公证**。文件名依据实际二进制架构生成。

## 发布到 GitHub

沿用 `Adobiz/Pi-Drive-Hub`，先 pull，再新增完整 `mac/` 子工程，最后由你 push。运行 `python3 scripts/export-source.py` 可生成 `build/github-source/Pi-Drive-Hub/` 合并包，包含 `mac/` 和根目录的 Mac 工作流，不会修改原仓库或推送。操作见 [逐步教程](docs/GITHUB_PUBLISHING.md)。安装包作为同一仓库的 Release 附件上传。

`mac/` 中保留完整源码、`pubspec.lock`、`macos/Podfile.lock` 和 `third_party/tray_manager_local`。构建物、ZIP、证书和本地日志已加入自己的忽略规则。

Mac 工作流放在原仓库根目录的 `.github/workflows/macos.yml`，从 `mac/` 运行静态检查、测试和构建，保存 UNSIGNED 测试制品，不会自动创建 Release。现有 Windows 工作流保留。

正式站外分发使用 [scripts/release.sh](scripts/release.sh)：它会检查凭据、执行测试和构建，再签名、公证、附加票据及验证 Gatekeeper。签名使用 Keychain 中的 Developer ID Application 证书，公证使用已配置的 `notarytool` Keychain profile。

```bash
./scripts/release.sh --check
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARYTOOL_PROFILE='pi-drive-notary'
./scripts/release.sh
```

只有全部验证通过才会产生 `build/distribution/Pi-Drive-Hub-macos-架构-版本.dmg`、ZIP 和校验文件。正式流程先公证并为 App 附加票据，再创建、签署、公证 DMG，为 DMG 附加票据；两种安装包内的 App 均携带票据。浏览器下载后在全新 Mac 上完成验收，再将安装包及 `.sha256` 作为 GitHub Release 附件上传。脚本不执行 GitHub 推送或发布。

签名证书、公证凭据不要提交到仓库。详细操作见 [GUIDE.md](GUIDE.md#9-发布与分发)。关闭 App Sandbox 本身不妨碍 GitHub 站外分发；Mac App Store 上架不在当前发布流程范围内。

## 项目结构

```text
lib/core/state/          # 账号状态与传输调度
lib/core/transfer/       # 可取消 HTTP、范围校验、临时文件与流式哈希
lib/core/storage/        # Keychain 凭据
lib/providers/           # 百度 / 夸克 / 123 协议
lib/ui/                  # 登录、文件浏览、传输与托盘
macos/Runner/            # 多窗口宿主、云朵菜单栏和原生速率面板
third_party/             # tray_manager 本地 fork（需保留）
test/                    # 传输安全及生命周期回归
tools/                   # 图标生成与离线原生多窗口测试
scripts/release.sh       # 本地签名公证流程
```

## 使用说明与许可

本项目使用非官方协议，仅用于学习与研究。请遵守各网盘用户协议。项目不提供破解、绕过会员或广告推广服务。

保留上游说明和第三方许可证。本项目使用 [MIT License](LICENSE)，本地 tray_manager fork 的许可证见 [third_party/tray_manager_local/LICENSE](third_party/tray_manager_local/LICENSE)。
