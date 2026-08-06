<div align="center">

<img src="assets/PI_Drive_Hub.png" width="200">
    
# PI Drive Hub

**Lightweight · Clean · Ad-Free · Multi-Cloud**

[![Version](https://img.shields.io/github/v/release/Adobiz/PI-Drive-Hub?color=blue&label=version)](https://github.com/Adobiz/PI-Drive-Hub/releases)
[![Size](https://img.shields.io/badge/Size-12M-brightgreen)](https://github.com/Adobiz/PI-Drive-Hub/releases/latest)

A Windows desktop cloud drive client built with Flutter, connecting to multiple cloud drives via **official client protocols**.
It offers a clean interface, no ad interruptions, no redundant icons, and supports official login pages for QR code / account-password login, with full directory operations.

</div>

---

## ✨ Features

- 🧹 **Clean & Ad-Free**: No ad placements, no redundant icons, no startup pop-ups
- 🔗 **Multi-Cloud Support**: Baidu Netdisk / Quark Cloud / 123 Cloud (unified abstraction, easily extensible)
- 🔐 **Official Login Page**: Embedded official login page for QR code / account-password login, with credentials encrypted and stored locally (Windows DPAPI)
- 📂 **Full Directory Operations**: Browse, upload, download, create folders, rename, delete, move, search (not limited to the official /apps directory)
- ⏬ **Download Capability**: Segmented downloads, resume broken downloads, concurrency control (auto-adjusted based on account membership level)
- ⏫ **Upload Capability**: Multi-protocol uploads (Baidu Form / Quark OSS / 123 S3)
- 🎨 **Lightweight UI**: Material Design, fast startup, low memory footprint

## 📦 Supported Cloud Drives

| Cloud Drive | Login Method | Notes |
|-------------|-------------|-------|
| Baidu Netdisk | Official login page (QR code / account-password) | Client protocol, any directory, SVIP supported |
| Quark Cloud | Official login page (QR code / account-password) | Client protocol, OSS segmented upload, SVIP supported |
| 123 Cloud | Account & password | Client protocol, S3 upload, SVIP supported |

> Note: All cloud drives are connected via **unofficial client protocols** (reverse-engineered from open-source projects such as BaiduPCS-Go, alist),
> for personal learning and technical exchange only. Please comply with the terms of service of each cloud drive provider.

## 🚀 Quick Start

### Requirements

- Flutter 3.29+ stable / Dart 3.7+
- Windows 10/11 (desktop)
- Visual Studio 2022 (with C++ desktop development workload), CMake
- `nuget.exe` must be in PATH (required for building `flutter_inappwebview_windows`)

### Build & Run

**One-command build** (Windows, requires Flutter environment + nuget in PATH, see below for details):

```bat
build.bat              :: Build release (Chinese, default)
build.bat en           :: Build release (English UI)
```
> ⚠️ The project path must be pure English (Chinese paths will cause build failures).

## 🏗️ Project Structure

```
lib/
├── core/
│   ├── models/            # File / account models
│   ├── providers/         # CloudProvider abstraction + registry
│   ├── storage/           # Credential encrypted storage (DPAPI)
│   └── state/             # Global state + download/upload managers
├── providers/
│   ├── baidu_client/      # Baidu Netdisk (client protocol)
│   ├── quark/             # Quark Cloud
│   └── pan123/            # 123 Cloud
└── ui/
    ├── login_page.dart    # Login page (provider selection)
    ├── file_browser_page.dart  # File browser
    └── download_page.dart # Transfer manager
```

## 📄 Disclaimer

This project is for educational and research purposes only. The project connects to various cloud drive services through unofficial protocols.
Please comply with the user agreements of each cloud drive provider and relevant laws and regulations; any consequences arising from the use of this project shall be borne by the user.
This project does not provide any form of cracking or acceleration services, nor does it contain any advertisements or promotional content.

## 📜 License

[MIT](./LICENSE)

---

**Note**: This project does not contain any user credentials. All login credentials are encrypted and stored locally on your machine (DPAPI) and will not be uploaded or leaked.
