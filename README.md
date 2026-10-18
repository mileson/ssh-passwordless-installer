<a id="ssh-passwordless-installer"></a>

<div align="center">

<p align="center">
  <img src="./assets/brand/logo.svg" width="160" alt="SSH Passwordless Installer" />
</p>

# SSH 免密配置器 · 新手安装工具

**下载、输入服务器信息，再按引导完成免密登录配置。**

新手引导 · 本地配置 · macOS 应用 · 脚本运行

[![中文说明](https://img.shields.io/badge/%E8%AF%B4%E6%98%8E-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-059669)](#readme-detail-14)
[![项目类型](https://img.shields.io/badge/%E9%A1%B9%E7%9B%AE-%E5%B7%A5%E5%85%B7-6366f1)](#readme-detail-14)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-supported-black?logo=apple)](./scripts/macos)
[![Windows](https://img.shields.io/badge/Windows-supported-blue?logo=windows)](./scripts/windows)
[![SSH](https://img.shields.io/badge/SSH-passwordless-22c55e)](https://www.openssh.com/)
[![App Bundle](https://img.shields.io/badge/macOS-.app_ready-0ea5e9)](./tools_build_macos_apps.sh)

[✨ 核心特性](#readme-detail-14) · [👀 效果预览](#readme-detail-16) · [✅ 适用场景](#readme-detail-audience) · [🚀 快速开始](#readme-detail-18) · [🔒 安全说明](#readme-detail-30) · [🔄 工作流程](#readme-detail-20)

</div>

---

> 给新手准备的 SSH 免密配置器：下载、双击、输入服务器信息和密码，就能完成新的免密登录配置。

<a id="readme-section-1"></a>

<a id="功能亮点"></a>

<a id="readme-detail-14"></a>

## ✨ 核心特性

- macOS 和 Windows 都提供双击入口
- 为每个服务器别名生成独立的 Ed25519 密钥
- 自动把公钥安装到远端服务器
- 自动写入受控的 `~/.ssh/config` 配置块
- 自动验证直连和别名登录是否都可用
- 支持打包为可分发的 macOS `.app` 和 Windows zip

<a id="readme-section-2"></a>

<a id="预览"></a>

<a id="readme-detail-16"></a>

## 👀 效果预览

![SSH 免密配置器预览](./assets/preview/setup-flow-cn.svg)

<a id="readme-detail-audience"></a>

## ✅ 适用场景

适合需要配置 SSH 免密登录的使用者。

<a id="readme-section-3"></a>

<a id="快速开始"></a>

<a id="readme-detail-18"></a>

## 🚀 快速开始

从下面的现有入口开始，按顺序准备环境、配置并完成首次运行。

### 方式 1：使用 macOS App

构建并解压 macOS `.app` 后双击运行：

```bash
chmod +x ./tools_build_macos_apps.sh
./tools_build_macos_apps.sh
```

生成：

```text
build/macos-apps/final/SSH-Passwordless-Setup-macOS.zip
```

这个 App 会在双击后打开 Terminal，并执行内置的命令行配置流程。

### 方式 2：直接本地运行脚本

#### macOS

```bash
chmod +x ./scripts/macos/setup-passwordless-ssh.command
./scripts/macos/setup-passwordless-ssh.command
```

#### Windows

双击：

```text
scripts\windows\setup-passwordless-ssh.bat
```

### 方式 3：构建可分发安装包

#### 只构建 macOS `.app`

```bash
chmod +x ./tools_build_macos_apps.sh
./tools_build_macos_apps.sh
```

生成：

```text
build/macos-apps/final/SSH-Passwordless-Setup-macOS.zip
```

#### 同时构建 macOS 和 Windows 分发包

```bash
chmod +x ./tools_build_release_bundles.sh
./tools_build_release_bundles.sh
```

生成：

```text
build/release-bundles/final/SSH-Passwordless-Setup-macOS.zip
build/release-bundles/final/SSH-Passwordless-Setup-Windows-Download-Then-Double-Click.zip
```

### 运行时会提示输入什么

1. 服务器 IP 或域名
2. SSH 用户名，默认 `root`
3. SSH 端口，默认 `22`
4. 本地备注名，例如 `vultr-root`
5. 服务器密码

如果服务器禁用了密码登录，或 SSH 端口被服务器防火墙拦截，macOS 脚本会进入控制台接力模式：生成一条可粘贴到服务商 VNC/Console 的命令，用于写入公钥、尝试放行 SSH 端口，然后回到本地继续验证免密登录。

配置完成后，可以直接：

```bash
ssh vultr-root
```

<a id="readme-section-4"></a>

<a id="工作流程"></a>

<a id="readme-detail-20"></a>

## 🔄 工作流程

1. 采集服务器地址、用户名、端口和本地别名
2. 生成本地排查日志，并预检 SSH 端口连通性
3. 在本机生成新的 SSH 密钥，避免复用旧密钥
4. 通过 `ssh-copy-id`、回退逻辑或控制台接力安装公钥
5. 写入带标记的 `~/.ssh/config` 片段，避免污染原配置
6. 分别验证直连和别名免密登录

<a id="readme-section-5"></a>

<a id="技术栈"></a>

<a id="readme-detail-22"></a>

## 🏗️ 技术栈

SSH 免密配置器 的实现按下列技术与模块组织，接入和维护时可据此定位。

| 层级 | 技术 |
|---|---|
| 本地执行 | Bash、PowerShell |
| SSH 能力 | OpenSSH、`ssh-copy-id` |
| macOS 打包 | `qlmanage`、`sips`、`iconutil`、`ditto` |
| Windows 分发 | `.bat` 启动器 + `.ps1` 主逻辑 |

<a id="readme-section-6"></a>

<a id="macos-app-签名与公证"></a>

<a id="readme-detail-24"></a>

## 📌 macOS `.app` 签名与公证

如果需要构建签名后的 macOS 发布包，可选传入：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="YOUR_NOTARY_PROFILE" \
./tools_build_macos_apps.sh
```

未提供这些变量时，脚本会生成适合测试或内部使用的未签名 zip。

<a id="readme-section-7"></a>

<a id="版本说明"></a>

<a id="readme-detail-26"></a>

## ⬆️ 版本说明

- [v0.1.0](./docs/releases/v0.1.0.md)

<a id="readme-section-8"></a>

<a id="仓库结构"></a>

<a id="readme-detail-28"></a>

## 📁 仓库结构

下面按实现职责列出目录位置，便于把修改放回对应模块。

```text
assets/
  brand/
    logo.svg
  preview/
    setup-flow-cn.svg
    setup-flow.svg

docs/
  releases/
    v0.1.0.md

scripts/
  macos/
    setup-passwordless-ssh.command
  windows/
    setup-passwordless-ssh.bat
    setup-passwordless-ssh.ps1

.github/
  ISSUE_TEMPLATE/
  workflows/

tools_build_macos_apps.sh
tools_build_release_bundles.sh
```

<a id="readme-section-9"></a>

<a id="安全说明"></a>

<a id="readme-detail-30"></a>

## 🔒 安全说明

- 服务器密码只会由本机 `ssh` 或 `ssh-copy-id` 读取
- 密码不会写入脚本、配置文件或仓库
- 工具只会新增新的公钥，不会自动删除旧密钥
- 私钥始终保存在用户自己的 `~/.ssh/` 目录中

更多说明见 [SECURITY.md](./SECURITY.md)。

<a id="readme-section-10"></a>

<a id="贡献"></a>

<a id="readme-detail-32"></a>

## 🤝 贡献

欢迎提交 bug 报告、改进建议和跨平台兼容性修复。开始贡献前请先阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。

<a id="readme-section-11"></a>

<a id="许可证"></a>

<a id="readme-detail-34"></a>

## 📄 许可证

MIT License，见 [LICENSE](./LICENSE)。

<a id="readme-section-12"></a>

<a id="作者"></a>

<a id="readme-detail-36"></a>

## 👤 作者

- X: [Mileson07](https://x.com/Mileson07)
- 小红书: [超级峰](https://xhslink.com/m/4LnJ9aB1f97)
- 抖音: [超级峰](https://v.douyin.com/rH645q7trd8/)
