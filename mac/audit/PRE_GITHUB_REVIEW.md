# GitHub 上传前本地复查

日期：2026-11-03。版本：`1.0.0+1`。

**源码已整理为可公开的开发项目；稳定版安装包仍需签名、公证和真实环境验收。** 本轮没有上传源码或安装包，没有初始化本地仓库、创建远端仓库、建立标签或发布 Release。GitHub 仅查询了账号与现有仓库。

## 本轮发现并修复

| 问题 | 修复 |
| --- | --- |
| 刚添加任务便关闭窗口，原生宿主可能读取旧空闲快照并销毁引擎 | 等待 Dart 返回最新队列状态再判断；等待期间禁止释放；重新打开窗口后忽略旧关闭确认 |
| 标签页关闭后，迟到的登录回调仍可修改已销毁状态 | 销毁后拒绝选择、退出及偏好修改；登录页检查 mounted 并释放控制器 |
| Keychain 拒绝访问或凭据损坏可能抛出未处理异常 | 将凭据读取纳入恢复异常处理，返回可重试的登录失败 |
| Cookie 轮询重叠、初始化前读取旧状态、关闭页面后继续处理 | 初始化完成后才轮询；限制单次轮询；异步返回后检查页面存活；禁用远程登录页文件访问 |
| 缺少 DMG 与清晰的上传材料 | 新增 DMG、干净源码导出、逐步教程、人工验收表和 Release 说明草稿 |

## 验证结果

| 检查 | 结果与范围 |
| --- | --- |
| Flutter 静态检查 | 无问题 |
| 完整自动化测试 | 46 项全部通过，不读取真实 Keychain、不操作云端文件 |
| 最终构建的原生离屏测试 | 14 项断言通过，进程正常退出 |
| macOS Release 构建 | 在独立副本成功构建 App、ZIP 和 DMG |
| ZIP 与 DMG | SHA-256、ZIP CRC、镜像校验通过 |
| 解压或只读挂载后的 App | 深度严格签名结构校验通过；仅为本地 ad-hoc 身份 |
| DMG 内容 | App、Applications 符号链接、安装说明齐全；检查后已卸载，没有启动 App |
| 架构 | 主程序、App.framework、FlutterMacOS.framework 均包含 arm64、x86_64 |
| 源码对照 | 构建使用的 lib/、macos/Runner/ 与当前源码一致 |
| 发布脚本 | 语法通过；缺少凭据时在构建、公证前失败 |
| 源码导出 | 按 Git 忽略规则排除构建物、缓存、证书及本地日志；常见私钥和令牌模式无匹配，不构成完整安全审计 |
| GitHub 工作流 | 官方 checkout/upload-artifact v7 引用已核对；远端未运行 |

原生测试使用真实 Flutter AOT 页面和原生通道，但测试入口插件注册留空，使用演示数据。它覆盖三个窗口、命令隔离、标签页状态、关闭确认竞态、引擎释放和跨窗口汇总；不代替真实 WebView、文件选择器及 Keychain 验收。

引擎销毁时仍有一次 `Communicating on a dead channel.` 诊断。测试没有崩溃，14 项断言完成；本轮未消除此诊断，多次开关真实插件页面与长时间运行仍需人工验收。

## 最新本地测试包

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| `UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0.dmg` | 24,419,579 字节 | `68c63a0c5a05f2d48a341c55fb37f6ffc66467450a13b1d9b9789241e602604e` |
| `UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0.zip` | 21,457,282 字节 | `8eec66c06d81d4fd181410329d152ea72521ba3efd50749eebf61f790064121e` |

路径为 `build/distribution/`，均附有 `.sha256` 文件。这些包没有 Developer ID 分发签名或公证，不作为稳定版。当前运行的旧应用未替换，历史测试包未删除。

## 稳定版仍待完成

1. 本机查询到 0 个有效签名身份。需准备 Developer ID Application 证书及私钥、公证 profile，再验证真实签名、公证、票据和 Gatekeeper 接受流程。本轮未提交 Apple 公证。
2. 百度、夸克、123 的真实登录、协议兼容性、并行传输、大文件哈希和异常恢复尚未验收。
3. 全新 Mac 安装、Intel、低版本 macOS、睡眠唤醒、磁盘满及长时间运行尚未验收。
4. 原仓库新增的 Mac GitHub Actions 尚未运行；合并后也需确认现有 Windows 检查仍正常。

源码可以先公开；公开测试附件时保留 UNSIGNED 名称并标记 pre-release。完成上述验收后再发布稳定版。

## 本地材料

- [逐步上传教程](../docs/GITHUB_PUBLISHING.md)
- [教程概览页](../docs/GITHUB_RELEASE_GUIDE.html)
- [人工验收清单](../docs/RELEASE_CHECKLIST.md)
- [Release 说明草稿](../docs/RELEASE_NOTES.md)
- 本地合并包：`build/github-source/Pi-Drive-Hub/`，包含 `mac/` 和根目录的 Mac 工作流；清单：`build/github-source/manifest.txt`。
- 合并 ZIP：`build/distribution/Pi-Drive-Hub-mac-overlay-1.0.0.zip`。

源码导出脚本只在临时目录建立索引，不修改原项目 Git 状态。日志保存在被忽略的 `audit/pre-github-*.txt`。

参考：[Apple 打包说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)、[Apple 公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)、[GitHub Release 说明](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
