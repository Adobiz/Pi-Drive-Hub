---
template: doc
theme: paper
title: PI 网盘：从源码到 GitHub 下载页
subtitle: 2026-11-03 · macOS 1.0.0 开发版本
lang: zh
---

## A 当前可以先上传什么

```callout info 先公开源码，稳定版继续验收
46 项自动化测试与 14 项原生断言通过。
本地 ZIP 和 DMG 已构建并校验。
本机没有有效的分发签名身份。
真实账号、全新 Mac 和 Intel 仍需验收。
```

本轮修复关闭窗口时的队列竞态、迟到登录回调和凭据读取异常。
登录 Cookie 轮询已增加并发与页面存活保护。

查看 [完整复查记录](../audit/PRE_GITHUB_REVIEW.md)。

## B 为什么很多人上传 DMG

DMG 打开后像一个临时磁盘，可以同时提供 App 和安装说明。

```flow LR
下载 DMG -> 打开镜像
打开镜像 -> 将 App 拖入 Applications
将 App 拖入 Applications -> 从应用程序启动
从应用程序启动 -> 推出镜像
```

| 格式 | 用户如何使用 | 本项目的用途 |
| --- | --- | --- |
| DMG | 打开并拖入 Applications | 主要安装包 |
| 应用 ZIP | 解压并移动 App | 备用安装包 |
| 源码 ZIP | 解压后自己构建 | 源码备份 |

DMG 的格式不会自动完成签名或公证。
当前 UNSIGNED 文件仍是本地测试包。
[Apple 打包文档](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)。

## C 文件分别放在哪里

```tree
GitHub 仓库
  lib/ 与 windows/ | 原有 Windows 工程
  .github/workflows/macos.yml | 新增 Mac 工作流
  mac/ | 完整 Mac 子工程
    lib/ 与 macos/ | Mac 应用源码
    test/ 与 scripts/ | 测试和打包
    docs/ 与 third_party/ | 文档和本地依赖
    pubspec.lock 与 macos/Podfile.lock | Mac 依赖版本
GitHub Release 附件
  应用 DMG | 用户下载
  应用 ZIP | 备用下载
  .sha256 | 校验文件
```

本地合并包位于 `build/github-source/Pi-Drive-Hub/`。
运行 `python3 scripts/export-source.py` 可刷新快照。
安装包、缓存和证书由忽略规则排除。

## D 按你的习惯 pull 再 push

沿用 `Adobiz/Pi-Drive-Hub`，加入 `mac/` 子工程。
这些 Git 操作由你执行，整理脚本只生成本地文件。

1. 在原仓库执行 `git pull --ff-only`。
2. 复制合并包里的 mac/ 和 Mac 工作流。
3. 暂存这两部分，检查文件清单。
4. 按平时习惯 commit，再 push。
5. 等待新增的 macOS checks 通过。

检查候选文件时，应看到源码、锁文件和工作流。
不应出现 ZIP、DMG、证书或本地缓存。

详细命令和点击步骤见 [逐步上传教程](GITHUB_PUBLISHING.md)。

## E 正式安装包还需要什么

```flow
有效 Developer ID 身份 -> 检查与构建
检查与构建 -> 签署并公证 App
签署并公证 App -> 为 App 附加票据
为 App 附加票据 -> 创建并签署 DMG
创建并签署 DMG -> 公证 DMG 并附加票据
公证 DMG 并附加票据 -> 安装与真实账号验收
安装与真实账号验收 -> 创建稳定版 Release
```

本机查到 0 个有效签名身份。
准备证书和公证 profile 后，运行 `./scripts/release.sh`。
当前只验证了本地打包及缺少凭据时的失败保护。
真实签名、公证和 Gatekeeper 接受流程尚未执行。

人工项目见 [验收清单](RELEASE_CHECKLIST.md)。
[Apple 公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

## F 如何创建下载页

1. 打开 Releases，选择 Draft a new release。
2. 选择版本标签和已验收的提交。
3. 填写说明，附加 DMG 和校验文件。
4. 先保存草稿，再检查附件与状态。

未签名测试包保留 UNSIGNED 文件名，勾选 pre-release。
稳定版使用已签名、公证并完成验收的附件。
GitHub 自动生成的 Source code ZIP 供开发者使用。

[Release 说明草稿](RELEASE_NOTES.md) 可供复制。
[GitHub Release 官方说明](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
