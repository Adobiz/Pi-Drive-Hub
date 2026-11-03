# 多窗口、菜单栏与图标验证

日期：2026-11-03。版本：`1.0.0+1`。本记录补充此前的 [传输安全修复](FIX_STATUS.md)。

## 已实现

- ⌘N 新建原生窗口，每个窗口运行独立 Flutter 引擎，使用唯一窗口 ID 路由命令。
- ⌘T 新建标签页，「＋」可选择百度、夸克或 123。各标签页保留独立 Provider、会话对象、目录与 Navigator，Control + Tab / Control + Shift + Tab 切换。
- 同一窗口的标签页共享传输管理器，每项任务固定绑定自己的 Provider。切换一个标签页的账号只取消该 Provider 所属任务；账号权限分别限制下载并发。
- 关闭标签页保留后台任务；关闭有进行中、排队或暂停任务的窗口时保留引擎。主窗口隐藏后可由 Dock 或菜单栏恢复；空闲的附加窗口关闭后释放引擎。
- 菜单栏只有一个单色云朵图标。单击打开原生 SwiftUI 面板，汇总各窗口下载/上传速率、任务和本次流量；提供最近 60 秒曲线、下载峰值、单任务及全部暂停/继续操作。任务操作按所属窗口路由。
- 当前标签页未登录时，仍能从云朵面板进入该窗口的传输管理，查看已关闭标签页留下的任务。
- 下载进度包含正在接收的分片字节，避免只在整个分片结束后跳变；完整分片校验与最终文件保护保留。
- Dock、Finder 和界面 Logo 使用圆角蓝底、圆润云朵及 π 笔画。菜单栏使用同一云形的单色轮廓。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| `flutter analyze --no-pub` | 无问题 |
| `flutter test --no-pub --reporter expanded` | 44 项全部通过 |
| `./build.sh` | macOS Release 构建及本地 ad-hoc 签名结构校验通过 |
| `scripts/test-workspace.sh APP` | 11 项原生集成断言通过，退出码 0，输出 `WORKSPACE_SMOKE_OK` |
| 浅色、深色和空闲面板 | 使用 SwiftUI 离屏渲染并检查布局 |
| ZIP SHA-256 | 校验通过 |
| ZIP 解压后的 `codesign --verify --deep --strict` | 通过 |
| 主可执行文件、App.framework、FlutterMacOS.framework | 均包含 x86_64 与 arm64 |
| Shell 脚本语法 | 通过 |
| 构建副本与当前源码 | `lib/`、`macos/Runner/` 一致 |

44 项测试包括此前的 27 项传输安全用例、8 项速率监控、7 项标签页与生命周期、1 项分片内进度和 1 项 Logo 方形布局回归。

原生测试创建三个离屏窗口，验证三个 Dart 页面完成渲染、窗口 ID 唯一、仅目标窗口增加标签页、其他窗口状态不变、关闭窗口保留暂停任务、空闲引擎释放，以及跨引擎速率/任务 ID/会话流量汇总。测试使用构建产物中的 Dart AOT 代码和原生通道；插件注册在测试入口中留空，不登录服务、不读取 Keychain，也不修改云端文件。它不代替多个真实 WebView 登录及各插件的交互验收。

测试引擎销毁时 Flutter SDK 输出一次 `Communicating on a dead channel.` 诊断；进程未崩溃，后续引擎释放断言与退出码均正常。真实使用中的多窗口插件销毁与长时间运行仍应纳入人工验收。

预览图在 [docs/previews](../docs/previews/) 中，任务和曲线全部为离线演示数据，演示数据仅编入 DEBUG 预览。本记录中的离屏测试和预览渲染未开启屏幕共享，也未替换当前运行的原应用。

## 本地测试包

```text
build/distribution/UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0-workspaces.zip
build/distribution/UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0-workspaces.zip.sha256
```

ZIP：21,454,217 字节。

SHA-256：`81c589c49c707a1f3d28dfc02c3ace02d91c160880ca2b8c6a0ef4b471b20c41`。

该包仍是本地 ad-hoc 测试包，未完成 Developer ID 签名或公证。安装测试前先完成旧版本中的传输并退出旧版，再解压打开新包；进程内任务不会迁移到新版本。

## 正式发布前仍需完成

- 真实账号的多窗口登录、不同网盘标签页并行传输及暂停恢复；同一服务多账号同时登录尚未验收，Keychain 仍按服务保存一份凭据。
- 长时间后台传输、睡眠唤醒、断网重试，以及 Intel 与较低版本 macOS 实机验收。
- Developer ID 签名、公证、全新 Mac 安装与 GitHub Actions 远端运行。

本轮没有初始化 Git 仓库、推送 GitHub 或发布 Release。

## 右上角精简更新（2026-11-03）

移除标签栏右上角的新建窗口按钮，仅保留「＋」选择网盘并新建标签页。⌘N、文件菜单和菜单栏的新建窗口功能继续保留。

本次静态检查无问题，7 项现有标签页回归测试全部通过；独立副本中的 macOS Release 构建、ZIP CRC 与解压后的签名结构校验通过，未覆盖当前运行的应用。

最新本地测试包：`build/distribution/UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0-workspaces-plus-only.zip`。

ZIP：21,453,705 字节。SHA-256：`77213687f0326f764453e99510a982a8ec05af6eea5871e17938b866f1f6a0f1`。仍为未完成 Developer ID 签名、公证的本地测试包。
