# PI 网盘 macOS：上传 GitHub 与发布教程

更新：2026-11-03。适用于当前 `1.0.0+1` 开发版本。

源码已整理为可公开的开发项目；稳定版安装包还需真实账号验收、Developer ID 签名与公证。本机目前查询到 0 个有效签名身份。完整检查结果见 [发布前复查](../audit/PRE_GITHUB_REVIEW.md)。

## 1. 为什么很多 macOS 项目使用 DMG

DMG 是磁盘映像。用户双击后看到一个临时磁盘，通常将里面的 App 拖入 Applications，再推出磁盘。它可以同时放安装说明，并为整个容器提供签名。ZIP 解压后也能得到可用的 App，适合提供备用下载。PKG 则适合需要安装多个组件或执行安装操作的产品。

| 形式 | 用户操作 | 当前项目的用途 |
| --- | --- | --- |
| DMG | 打开镜像，将 App 拖入 Applications | 面向 macOS 用户的主要安装包 |
| ZIP | 解压 App，再移动到 Applications | 备用下载和开发测试 |
| 源码 ZIP | 解压项目，用 Flutter 构建 | 源码备份；里面没有可直接安装的 App |

DMG 不会自动完成签名、公证，也不代表 GitHub 或 Apple 审核通过。当前 `UNSIGNED-*.dmg` 仍是本地测试包。正式分发流程要签署 App 和 DMG，公证 DMG，并附加公证票据。[Apple 打包说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)、[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 2. 已整理的文件

沿用现有 `Adobiz/Pi-Drive-Hub` 仓库：先 pull，再加入完整的 `mac/` 子工程，最后由你 commit 和 push。本地整理脚本不会操作现有仓库或远端。

```text
build/github-source/Pi-Drive-Hub/         可直接合并到现有仓库的内容
  mac/                                  完整 Mac 工程与自己的忽略规则
  .github/workflows/macos.yml            放在现有仓库根目录的 Mac 工作流
build/github-source/manifest.txt         合并文件清单
build/distribution/
  Pi-Drive-Hub-mac-overlay-1.0.0.zip      上述内容的合并包
  UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0.dmg
  UNSIGNED-Pi-Drive-Hub-macos-universal-1.0.0.zip
  对应的 .sha256 文件
```

`universal` 表示二进制包含 Apple Silicon 与 Intel 架构；Intel 实机运行还未验收。`UNSIGNED` 表示缺少 Developer ID 分发签名及公证，内部 App 只有本地 ad-hoc 签名。

历史 ZIP、`build/`、SDK 缓存、Pods、证书和本地日志已由 Mac 自己的 `.gitignore` 排除。`mac/` 中保留 `pubspec.lock`、`macos/Podfile.lock`、`test/` 和整个 `third_party/tray_manager_local/`；工作流单独放到原仓库根目录。

需要重新整理时，在项目目录运行：

```bash
python3 scripts/export-source.py
```

该命令不修改原项目的 Git 状态，会刷新 `build/github-source/` 和源码 ZIP。导出前检查 Git 忽略规则和常见私钥、令牌模式。导出的干净副本是快照；后续改动原项目时，要重新导出。

## 3. 按你的习惯：pull → 加入 mac → push

本轮只整理本地合并包，下面的 Git 操作由你执行。

### 第一步：拉取现有仓库

在已克隆的仓库中执行：

```bash
cd "$HOME/GitHub/Pi-Drive-Hub"
git status --short
git pull --ff-only
```

如有未提交的改动，先按你平时的方式处理，再 pull。如果尚未克隆：

```bash
cd "$HOME/GitHub"
git clone https://github.com/Adobiz/Pi-Drive-Hub.git
cd Pi-Drive-Hub
```

### 第二步：复制合并内容

在原仓库根目录执行，或用 Finder 复制同样两个部分：

```bash
rsync -av "$HOME/GitHub/Pi-Drive-Hub-Mac/build/github-source/Pi-Drive-Hub/" ./
```

命令不带删除参数，复制内容仅包含 `mac/` 和新增的 Mac 工作流。合并后结构如下：

```text
Pi-Drive-Hub/
  lib/                           原有 Windows 代码
  windows/                       原有 Windows 工程
  pubspec.yaml                   原有 Windows 依赖
  .github/workflows/
    build-windows.yml            原有 Windows 工作流
    star-tracker.yml             原有工作流
    macos.yml                    新增 Mac 工作流
  mac/
    lib/                         Mac 代码
    macos/                       Flutter 的 macOS 原生目录
    pubspec.yaml                 Mac 独立依赖
    .gitignore                   排除 Mac 构建物和缓存
    build.sh
    scripts/
    docs/
```

`mac/` 中保留完整工程及锁文件，Mac 与 Windows 的源码和依赖各自管理。工作流放在仓库根目录，Mac 命令从 `mac/` 运行。原有 Windows 文件不在合并包中。

可将 [README 补充片段](ROOT_README_SNIPPET.md) 的内容手动追加到根 README，便于访问者找到 Mac 版。

### 第三步：检查、提交、推送

```bash
git add mac .github/workflows/macos.yml
git diff --cached --stat
git diff --cached --name-only
```

确认清单只有预期的 Mac 源码、文档、测试和工作流，没有构建包或凭据，再执行：

```bash
git commit -m "Add macOS client under mac/"
git push
```

若补充了根 README，再将 `README.md` 加入提交。也可用 GitHub Desktop 对同一个现有仓库执行 Pull、Commit 和 Push，无需新建仓库或更改 origin。

Mac 本地构建命令：

```bash
cd mac
./build.sh
```

## 4. 检查 GitHub Actions

push 后打开原仓库的 **Actions → macOS checks**。Mac 工作流只针对 `mac/` 或自身配置的改动触发，并在 `mac/` 中执行命令。等待静态检查、测试和构建通过。CI 会保存标记 `UNSIGNED-macos-test-package` 的 ZIP、DMG 与校验文件，不会自动发布 Release。

Mac 工作流的首次远端运行尚未执行，本机通过不保证 GitHub Runner、网络或依赖下载也会成功。若 Actions 失败，先查看红色步骤日志，不要把失败的构建作为稳定版安装包。

## 5. 生成可正式分发的 DMG

先进入仓库的 `mac/` 目录。这部分需要本机 Keychain 中有效的 **Developer ID Application** 证书及私钥，并配置公证认证。没有证书时可以先公开源码，继续本地测试。

```bash
./scripts/release.sh --check
xcrun notarytool store-credentials pi-drive-notary
```

按 `notarytool` 的本机交互提示填写认证信息。然后设置身份名称并构建：

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARYTOOL_PROFILE='pi-drive-notary'
./scripts/release.sh
```

脚本先检查身份与公证 profile，然后执行检查、测试、构建和签名。它先公证 App 并附加票据，再将该 App 放入 DMG，签署并公证 DMG、附加票据。这样 ZIP 和 DMG 内的 App 都携带自己的票据。最后通过签名结构和 Gatekeeper 检查后，生成不带 `UNSIGNED` 前缀的 ZIP、DMG、SHA-256 及两份公证结果文件。本机缺少证书，真实签名、公证和 Gatekeeper 接受流程尚未执行。[Apple 自定义公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

生成后在另一台 Mac 上通过浏览器下载，验证安装和首次启动；逐家验证真实登录、多标签并行传输、大文件哈希、暂停、取消、断网和睡眠唤醒。完整清单见 [人工验收表](RELEASE_CHECKLIST.md)。

## 6. 在 GitHub 创建 Release

1. 确认源码已经提交，Actions 已通过。
2. 打开 **Releases → Draft a new release**。
3. 为最终提交建立版本标签，例如 Mac 首个稳定版用 `mac-v1.0.0`，Target 选择 `main`。
4. 填写标题和说明。可从 [发布说明草稿](RELEASE_NOTES.md) 复制，再改成实际签名与验收状态。
5. 将已验证 DMG 和对应 `.dmg.sha256` 拖入附件区；可同时附加 ZIP 和 `.zip.sha256`。
6. 先点 **Save draft**，检查附件、标签与说明，再决定发布。

Mac 标签使用 `mac-v...` 前缀，避免与原有 Windows 标签重用。两端共用同一个 Releases 页面，发布时按需要决定是否设为 Latest。

如果主动公开未签名测试包，应保留 `UNSIGNED` 文件名，使用独立预览标签，例如 `mac-v1.0.0-beta.1`，勾选 **This is a pre-release**，说明尚未签名、公证和完整验收。应用内显示版本仍是 `1.0.0`；后续版本调整 `pubspec.yaml` 后重新构建。

GitHub 自动附加的 **Source code (zip)** 是标签对应的源码，用户安装时应下载你上传的 DMG 或应用 ZIP。安装包放在 Release 附件，源码放在仓库文件区。[GitHub Release 操作说明](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。

## 7. 普通用户如何安装

下载经过签名、公证并验收的 DMG，双击打开，将「PI 网盘.app」拖到 Applications。再从“应用程序”启动并推出镜像。升级前先完成旧版本传输并退出旧版；内存任务不会迁移。

当前本地测试 DMG 并不具备上述分发身份。本教程不把关闭系统安全保护作为安装步骤。
