# PI 网盘 macOS 版 · 从零到发布教程

> 配套代码库：`Pi-Drive-Hub-Mac`（本仓库）
> Windows 版原仓库：`Pi-Drive-Hub`（功能与本版一致，仅平台层不同）

本教程面向"第一次接触这个项目的人"，按**装环境 → 跑起来 → 改代码 → 发版本**的顺序讲解。
已在你机器上验证过的步骤会标注 ✅。

---

## 目录

1. [项目全景](#1-项目全景)
2. [环境准备（一次性）](#2-环境准备一次性)
3. [第一次构建](#3-第一次构建)
4. [日常运行与调试](#4-日常运行与调试)
5. [代码结构与常见开发任务](#5-代码结构与常见开发任务)
6. [界面文案：中英文](#6-界面文案中英文)
7. [图标与品牌](#7-图标与品牌)
8. [与 Windows 版同步代码](#8-与-windows-版同步代码)
9. [发布与分发](#9-发布与分发)
10. [疑难解答](#10-疑难解答)
11. [命令速查](#11-命令速查)

---

## 1. 项目全景

一句话：**用 Flutter 写的 macOS 桌面网盘客户端**，通过模拟各网盘官方客户端的接口协议，
实现无广告、全目录操作的多网盘（百度 / 夸克 / 123）聚合。

```text
用户界面 (Flutter UI)
    │  CloudProvider 抽象接口
    ▼
三个网盘实现 (baidu_client / quark / pan123)
    │  各自私有协议 API（HTTP + 签名）
    ▼
百度网盘 / 夸克网盘 / 123云盘
```

关键设计决策（改代码前必须理解）：

| 决策 | 原因 |
|------|------|
| UI 只依赖 `CloudProvider` 抽象，不感知具体网盘 | 新增网盘只需写一个实现类并注册，UI 零改动 |
| 文件模型统一为 `CloudFile`（含 raw 原始字段） | 各家 API 返回字段不同，UI 只看归一化字段 |
| 登录 = 内嵌官方登录页 (WKWebView) + 提取 cookie | 复用官方扫码/验证码能力，不自己实现登录 |
| 凭据存 macOS Keychain（`flutter_secure_storage`） | 系统级加密，随用户钥匙串走 |
| 下载 = 1MB 分片 + 断点续传 + 并发池 + 会员分级限流 | 普通账号并发下载会被限速甚至封号 |
| 关闭了 App Sandbox | 下载要写任意目录 + 访问 Keychain，个人分发不上架 |
| `lib/` 已包含独立的 macOS 传输安全修复 | 双端同步前逐文件比较，并运行回归测试 |

---

## 2. 环境准备（一次性）

| 组件 | 本机状态 | 安装方法 |
|------|---------|---------|
| macOS 12+ | ✅ | — |
| Xcode（完整版，非仅命令行工具） | ✅ Xcode 26.6 | App Store 搜索 "Xcode"，安装后运行一次 |
| Flutter SDK 3.29+ | ✅ 3.44.7 @ `~/development/flutter` | 见下方说明 |
| CocoaPods | ✅ 1.17.0 | `brew install cocoapods` |
| 命令行开发者工具切换 | ✅ | `sudo xcode-select -s /Applications/Xcode.app` |

### 2.1 验证命令

```bash
xcodebuild -version        # 应输出 Xcode 版本号（不是报 xcrun 错）
flutter --version          # 应输出 Flutter 版本
pod --version              # 应输出 1.x
```

### 2.2 Flutter 未安装时怎么装（参考）

```bash
# 国内网络推荐走官方中国镜像，速度 ~5MB/s（直接下载官方源仅 ~40KB/s）
mkdir -p ~/development
curl -L -o /tmp/flutter.zip \
  https://storage.flutter-io.cn/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.44.7-stable.zip
unzip /tmp/flutter.zip -d ~/development    # 得到 ~/development/flutter

# 写入 shell 配置（zsh）
cat >> ~/.zshrc <<'EOF'
export PATH="$HOME/development/flutter/bin:$PATH"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
EOF
source ~/.zshrc
flutter --version
flutter config --no-enable-swift-package-manager --no-analytics
```

> 为什么关闭 SPM：`flutter_inappwebview_macos`、`flutter_secure_storage_macos`
> 两个插件尚未适配 Swift Package Manager，本项目用 CocoaPods（仓库已内置标准 Podfile）。

---

## 3. 第一次构建

### 3.1 一条命令构建（本机已验证流程）

```bash
cd ~/GitHub/Pi-Drive-Hub-Mac
./build.sh              # 中文界面，release
./build.sh en           # 英文界面
```

脚本包含以下步骤：

1. **`flutter pub get`**：拉 Dart 依赖（走中国镜像）。
2. **`flutter build macos --release`**：内部自动执行 `pod install`（拉原生依赖，首次约 1-3 分钟）
   然后调用 Xcode 编译，产物在 `build/macos/Build/Products/Release/pi_pan.app`。
3. **本地签名与打包**：修复 ad-hoc 签名结构，生成 `build/distribution/UNSIGNED-*.zip`、DMG 及校验文件，仅供本地开发测试。
4. 脚本找不到 `flutter` 时会自动查找 `~/development/flutter` 与 `~/flutter`。

### 3.2 手动分步构建（想看每一层的输出）

```bash
flutter pub get
cd macos && pod install && cd ..   # 原生依赖，网络不稳定就多试几次
flutter build macos --release
open build/macos/Build/Products/Release/pi_pan.app   # 直接打开产物
```

### 3.3 运行产物

- 双击 `pi_pan.app`（Finder 中右键 → 打开 亦可）。
- 单击菜单栏云朵打开传输面板：汇总所有窗口的任务、实时速率和最近 60 秒曲线。右键可新建窗口、标签页或退出。
- ⌘N 新建窗口，⌘T 新建网盘标签页，⌘W 关闭标签页，⇧⌘W 关闭窗口，Control + Tab 切换标签页。
- 关闭标签页不取消传输；关闭窗口后有任务时继续在后台运行。菜单栏或 Dock 可重新打开，⌘Q 或「退出 PI 网盘」才退出应用。
- 首次写入凭据时，macOS 会弹 **"pi_pan 想要访问钥匙串"**，点"始终允许"即可（沙箱已关，无额外配置）。

---

## 4. 日常运行与调试

### 4.1 调试运行（热重载）

```bash
flutter run -d macos
# 运行中按:
#   r  热重载（改 Dart 代码即时生效）
#   R  热重启
#   q  退出
```

### 4.2 用 VS Code 开发（推荐）

```bash
cd ~/GitHub/Pi-Drive-Hub-Mac && code .
```

- 左下角选设备 → 选 `macOS` → F5 运行（首次会创建 `.vscode/launch.json`）。
- 安装 Dart/Flutter 扩展后自带断点调试、代码跳转、自动补全。

### 4.3 日志在哪里

- `flutter run` 的控制台 = 实时日志。
- release 包日志不落盘；需要排查时用 debug 模式复现。
- 网盘 API 的响应解析失败会抛异常并在任务列表显示"失败: xxx"——先看这个文案再定位代码。

---

## 5. 代码结构与常见开发任务

### 5.1 目录速查

```text
lib/
├── main.dart                 # 每个窗口的 Dart 入口 + 原生菜单栏通道
├── core/
│   ├── constants.dart        # 品牌色、分片大小、并发上限、超时
│   ├── models/               # CloudFile（统一文件模型）/ CloudAccount
│   ├── providers/            # CloudProvider 抽象 + AuthProvider 抽象 + 注册中心
│   ├── storage/token_store.dart   # Keychain 凭据存取（token_<providerId>）
│   ├── state/                # 标签页状态、传输队列、速率采样
│   └── i18n/strings.dart     # 全部界面文案（中/英双套）
├── providers/
│   ├── baidu_client/         # 百度网盘：auth(BDUSS) + api(rest/2.0/pcs) + config
│   ├── quark/                # 夸克网盘：auth(__puus cookie) + api(OSS 分片) + config
│   └── pan123/               # 123云盘：auth(账密) + api(S3 上传) + sign
└── ui/
    ├── app.dart              # 网盘标签栏 + 每个标签页独立导航
    ├── login_page.dart       # 登录页（选网盘通道）
    ├── official_login_view.dart  # 内嵌官方登录页（WKWebView + cookie 轮询）
    ├── file_browser_page.dart    # 文件浏览（列表/操作/搜索）
    ├── download_page.dart    # 传输管理（下载/上传列表）
    └── app_tray.dart         # 菜单栏托盘
macos/Runner/                 # DesktopWindows + MenuBarController + SwiftUI 传输面板
third_party/tray_manager_local/   # tray_manager fork（修复 Windows 菜单 bug，双端共用）
```

### 5.2 想加一个新网盘

1. 新建 `lib/providers/mydrive/`，实现 `CloudProvider`（`list/createFolder/rename/delete/upload/download` + 可选 `move/copy`）与 `AuthProvider`。
2. 在 `lib/core/providers/provider_registry.dart` 的 `createDefaultProviders()` 中加入新 Provider，让每个标签页获得独立实例。
3. UI 自动出现新通道——**不需要改任何 UI 代码**。
4. 传输进度回调统一用 `TransferProgress (doneBytes, totalBytes?)`；分片续传参数参考夸克实现的 `download()`。

### 5.3 想改下载并发策略

`lib/core/constants.dart`：

```dart
const int kSvipMaxConcurrent = 8;      // 会员并发
const int kNormalMaxConcurrent = 1;    // 普通账号并发（>1 会被百度限速/封禁）
const int kDownloadChunkSize = 1 * 1024 * 1024;  // 断点续传分片粒度
```

账号登录后设置该 Provider 的并发权限：`downloadManager.applyVipConcurrency(vip, provider: provider)`。窗口共用最多 8 个下载名额，调度器同时约束各账号的并发上限。

### 5.4 想改窗口默认大小

macOS 的默认窗口为 1080 × 720，最小 880 × 600。在 `macos/Runner/DesktopWindows.swift` 的 `install`、`newWindow` 和 `configure` 中调整。每个窗口使用独立 Flutter 引擎；`MainFlutterWindow.swift` 安装主窗口，`AppDelegate.swift` 处理 Dock 重新打开。

### 5.5 版本号

编辑 `pubspec.yaml` 的 `version: 1.0.0+1`（`+` 前是展示版本，后是构建号），重新构建即生效
（写入 .app 的 CFBundleShortVersionString）。

---

## 6. 界面文案：中英文

Dart 通用文案集中在 `lib/core/i18n/strings.dart`；原生面板在 `MenuBarModel.text` 中提供中英双语。新增窗口和标签页控件也按 `APP_LANG` 选择文案。

- 加一句文案 = 在 `AppStrings` 里加一个 getter（成对的中/英）。
- 构建时注入语言：`./build.sh` 默认中文；`./build.sh en` 英文（`--dart-define=APP_LANG=en`）。

---

## 7. 图标与品牌

| 资源 | 位置 | 用途 |
|------|------|------|
| 应用图标 | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` | Dock / Finder 全套尺寸 |
| 菜单栏云朵 | `macos/Runner/MenuBarModel.swift` → `CloudGlyph` | 原生单色矢量，自动适配系统主题 |
| 界面 Logo | `lib/ui/pi_logo.dart` | 登录页和标签栏使用矢量绘制 |
| 品牌 PNG | `assets/PI_Drive_Hub.png` | 1024 像素导出图 |

云朵由连续贝塞尔曲线绘制，应用图标使用蓝色圆角底和圆润的 π 笔画。修改原生 `CloudGlyph` 后，可重新生成全部 PNG：

```bash
xcrun swiftc macos/Runner/MenuBarModel.swift tools/generate_app_icon.swift -o /tmp/pi-icon-generator
/tmp/pi-icon-generator "$PWD"
```

Dart 的 `roundedCloud` 与原生路径保持一致，修改时同步两处。`assets/tray_icon.png` 仅供非 macOS 回退使用。预览图在 `docs/previews/`，曲线和任务均为离线演示数据。

---

## 8. 与 Windows 版同步代码

本次传输安全修复后，两个仓库的协议、状态与 UI 已有独立变化。不要直接运行整目录覆盖同步；下列旧命令仅供理解原始结构，同步前应逐文件比较并运行全部回归。旧同步示例：

```bash
# 从 Windows 版同步代码过来（排除 Mac 适配文件）
rsync -av --exclude 'lib/main.dart' \
          --exclude 'lib/ui/app_tray.dart' \
          --exclude 'lib/core/i18n/strings.dart' \
          --exclude 'lib/core/providers/provider_registry.dart' \
          --exclude 'lib/core/storage/token_store.dart' \
          --exclude 'lib/ui/official_login_view.dart' \
          ../Pi-Drive-Hub/lib/ lib/
```

同步后重新 `flutter analyze`，人工复查上述 6 个文件的差异（Mac 适配注释/窗口逻辑）即可。
反向（Mac → Windows）同理，只是 Windows 版需要把 `main.dart` 的窗口初始化恢复为 Windows 形态。

---

## 9. 发布与分发

当前源码可作为开发中项目公开。稳定版发布必须先完成真实账号、安装兼容性、签名与公证验收。历史未签名 ZIP 不是正式发行版本。

### 9.1 本地测试包

```bash
./build.sh
```

输出为 `build/distribution/UNSIGNED-Pi-Drive-Hub-macos-架构-版本.zip`、同名 DMG 及各自 SHA-256。DMG 提供 App 和 Applications 拖拽入口。未完成分发签名、公证的包仅供本地开发，不应指导普通用户关闭系统保护来安装。

### 9.2 一次性准备 Developer ID 和公证 profile

在 Apple Developer 账号中获取 **Developer ID Application** 证书，并将证书及私钥安装到发布机器的登录 Keychain。不要将 `.p12`、私钥或 Apple 账号凭据提交到 GitHub。

```bash
./scripts/release.sh --check
xcrun notarytool store-credentials pi-drive-notary
```

按 `notarytool` 的交互提示在本机保存 Apple ID、Team ID 和适用的公证认证信息，不要把密码写进源码或聊天记录。

### 9.3 创建正式发行包

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARYTOOL_PROFILE='pi-drive-notary'
./scripts/release.sh       # 英文版可加 en
```

脚本先验证身份和 profile，再运行静态检查、全部测试及 Release 构建。它从内到外签名，启用 hardened runtime，先公证并为 App 附加票据，再创建、签署、公证 DMG 并附加票据。两种安装包内的 App 都携带票据；通过签名及 Gatekeeper 检查后生成 ZIP、DMG、SHA-256 及两份公证结果 JSON。本机尚无有效身份，实际签名、公证流程仍待发布机器验证。

参考：[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

### 9.4 上传 GitHub

首次上传的点击步骤、命令、DMG 与 ZIP 区别见 [GitHub 发布教程](docs/GITHUB_PUBLISHING.md)。

1. 检查源码暂存内容，不包含构建目录、旧 ZIP、Cookie、证书或本地日志。
2. 推送源码，等待 macOS Actions 的静态检查、测试和构建通过。
3. 真实账号逐家验证登录、文件操作、二进制和大文件、取消、切换账号与下载哈希。
4. 使用发布脚本生成的已验证 DMG 或 ZIP，在浏览器下载后于全新 Mac 验收。
5. 建立与版本对应的标签，填写 Release 说明，上传安装包和 SHA-256。

Actions 测试制品标记为 UNSIGNED，不会自动发布为正式安装包。首次外部验收可选择 prerelease；仍须先验证数据安全和安装行为。

---

## 10. 疑难解答

| 现象 | 原因 | 解决 |
|------|------|------|
| `zsh: permission denied: ./build.sh` | 脚本没执行权限 | `chmod +x build.sh`（本仓库已设置） |
| `flutter: command not found` | PATH 没配置 | `export PATH="$HOME/development/flutter/bin:$PATH"` 写入 `~/.zshrc` |
| `xcrun: error: unable to find utility "xcodebuild"` | 只装了命令行工具，没装完整 Xcode | App Store 装 Xcode，然后 `sudo xcode-select -s /Applications/Xcode.app` |
| 构建时报 `plugins do not support Swift Package Manager` | inappwebview / secure_storage 未适配 SPM | 忽略；项目已用 Podfile 走 CocoaPods（`flutter config --no-enable-swift-package-manager`） |
| `pod install` 卡在 clone OrderedSet / Empty reply | 国内网络访问 GitHub 不稳定 | 重试；或 `git config --global http.version HTTP/1.1` 后重试 |
| 首次运行弹"想要访问钥匙串" | 正常的安全提示 | 点"始终允许" |
| 登录页白屏/打不开 | 网络问题或 WebView 缓存了失效登录态 | 登录页右上角刷新；重启应用（登录页会先清 cookie 再加载） |
| 打开 .app 提示"来自身份不明的开发者" | 本地测试包没有 Developer ID 分发身份 | 使用第 9 节的签名、公证流程，正式用户下载已验证版本 |
| 找不到构建产物 | 构建失败在编译阶段 | 看构建日志末尾错误；`flutter build macos --verbose` 出详情 |
| 改动没生效 | 忘了重编译 | `flutter run` 热重载只对 Dart 生效；原生/Xcode 改动要重新 `flutter build` |
| 菜单栏云朵显示异常 | 原生矢量路径或状态按钮尺寸被修改 | 检查 `CloudGlyph.image()` 和 `MenuBarController.swift` 的状态按钮 |

---

## 11. 命令速查

```bash
./build.sh                # 构建 release（中文）+ 本地 ZIP / DMG
./build.sh en             # 构建 release（英文）
flutter run -d macos      # 调试运行（r 热重载）
flutter analyze           # 静态检查（改代码后必跑，应 0 issue）
flutter test              # 跑 test/ 传输安全与生命周期回归
flutter build macos --release --dart-define=APP_LANG=en   # 手动构建英文版
cd macos && pod install   # 单独装原生依赖（一般不需要手动跑）
```

---

*最后更新：2026-11-03。本机工具链为 macOS arm64、Xcode 26.6、Flutter 3.44.7、CocoaPods。当前验证和发行状态以 [最新复查记录](audit/PRE_GITHUB_REVIEW.md) 为准。*
