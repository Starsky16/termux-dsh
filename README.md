# termux-dsh

在 **Termux / Android arm64** 上一条命令装好 [dsh](https://github.com/deepseek-ai/deepseek-harness)。

它不是 dsh 的 fork，也不是搬运别人编译好的产物：本仓维护一条自动构建流水线，
从官方 npm 包出发，打上 Android 必需的补丁、编译缺失的原生模块，在 CI 里产出可复现的安装包，
让 dsh 在 Termux 上开箱即用。构建流程的技术细节见 [`docs/architecture.md`](docs/architecture.md)。

[![Repack](https://github.com/Starsky16/termux-dsh/actions/workflows/repack.yml/badge.svg?branch=main)](https://github.com/Starsky16/termux-dsh/actions/workflows/repack.yml)
[![Release](https://img.shields.io/github/v/release/Starsky16/termux-dsh?label=release)](https://github.com/Starsky16/termux-dsh/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Termux%20arm64-informational)

> **当前状态（2026-11-07）**：上一版 `v0.2.1-rc.5-tdsh.5` 已在 Termux 真机验证通过
> （vivo iPA2575 / Android 16 / aarch64）：安装脚本与 `dsh-termux-verify` 全项 PASS、
> `dsh web` 稳定、重启后会话保留。上游已发布 `0.2.2-rc.1`（仍无稳定版），本仓补丁
> 已按该版本重新锚定，新包待 CI 构建与真机验证；在验证通过前请继续安装 tdsh.5。
> 上游出稳定版后再提供正式版。

## 它解决什么问题

dsh 官方只发 npm 包，没有适配 Android：原生模块（koffi、node-pty 等）没有 arm64 Android
版本，部分代码在 Android 的 SELinux / Bionic 环境下跑不起来。`termux-dsh` 把这些全部
处理好，你只需要执行一条安装命令。

- **归本仓管**：dsh 本体与其官方依赖在 Termux 上运行的一切问题。
- **不归本仓管**：第三方插件的适配、修复与安装（归 [dsh-compat](https://github.com/Starsky16/dsh-compat)
  或插件作者）。

## 环境要求

- Termux **原生** aarch64（非 proot）；Android 8 及以上。
- 约 1 GB 可用磁盘；首次安装约 8–9 分钟（下载 120 MB 安装包，之后不再联网拉依赖）。
- 其余依赖（Node.js、git、curl、ripgrep 等）安装脚本会自动补齐。

## 快速开始

**方式一（推荐）：一条命令自动安装**

```bash
pkg update
pkg install -y git
git clone https://github.com/Starsky16/termux-dsh.git ~/code/termux-dsh
cd ~/code/termux-dsh
bash bootstrap.sh
```

脚本会自动解析最新版本（含 pre-release）、下载校验、安装并做安装后自检。
想固定装某个历史版本：

```bash
TDSH_RELEASE_BASE=https://github.com/Starsky16/termux-dsh/releases/download/v0.2.1-rc.5-tdsh.5 \
  bash bootstrap.sh
```

**方式二：`.deb` 单文件**（不想要 npm 全局安装时）

```bash
pkg install ./dsh-termux_<版本号>_aarch64.deb
dsh-termux-verify
```

两种方式的分步说明与故障排查见 [`INSTALL.md`](INSTALL.md)。

## 启动

```bash
dsh web
```

安装脚本会同时装一个 `~/bin/dsh` 启动包装：每次启动前自动检查运行环境，
发现异常只在屏幕上提示、**不会拦住你启动**；没装配套工具时完全静默。
升级不会覆盖它，重跑 `bootstrap.sh` 可修复。

## 验证安装

```bash
dsh --version   # 应输出与所装包一致的 <上游版本>-tdsh.<rev>，如 0.2.2-rc.1-tdsh.1
bash verify.sh  # 在仓库目录执行；结果应为：全部 PASS
```

`.deb` 方式安装的用 `dsh-termux-verify`（作用相同，不必进仓库目录）。

自动检查覆盖包版本、原生模块架构、配置覆盖与技能接线。另有个别行为需要启动
`dsh web` 后在会话里手工确认（新建文件、读图、大输出、重启后会话保留），
步骤与预期见 [`docs/verify-checklist.md`](docs/verify-checklist.md)。

## 升级与卸载

升级：重新跑一遍 `bash bootstrap.sh` 即可。

卸载（按安装方式二选一）：

```bash
npm uninstall -g dsh-termux   # 方式一装的
dpkg -r dsh-termux            # 方式二装的（会一并移除 ~/bin/dsh）
```

配置备份在 `~/.dsh/profiles/web/cordis.patch.yml.bak-*`，需要时可手工恢复。

> **用了 [dsh-compat](https://github.com/Starsky16/dsh-compat) 的话**：升级/重装后包内
> 文件会回到官方原样，需重跑一次它的 `patch.mjs --apply`；启动时看到
> 「L2 补丁未就绪」提示就是这个原因。机制说明见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 已知限制

- 上游最新是 `0.2.2-rc.1`（仍为候选版）；本仓 `main` 的构建直接作为**正式 Release（Latest）**发布，
  版本号保留上游的 `rc` 段以标明基座，不冒充上游稳定版。
- **HMR（热重载）在 Termux 上禁用**；修改配置/插件后需重启 `dsh web`。
- 图像处理走 wasm 版 sharp（不是 Android 原生包）；常用读图已在真机验证，
  特殊格式仍可能受 wasm 能力限制。
- 插件适配不在本仓范围；插件升级若把官方原包拉进 profile，需按
  [`CONTRIBUTING.md`](CONTRIBUTING.md) 重跑补丁脚本。
- 本仓不生成 Flutter / WPF / WinRT 产物，也不承担这些工具链。

## 文档

- [`INSTALL.md`](INSTALL.md)：分步安装、.deb 安装、验证、升级、故障排查
- [`PATCHES.md`](PATCHES.md)：A/B 补丁原理、基线版本、重生成方法
- [`docs/architecture.md`](docs/architecture.md)：分发 / 运行时 / 接线三层与 CI 流程
- [`docs/verify-checklist.md`](docs/verify-checklist.md)：会话内行为检查
- [`CHANGELOG.md`](CHANGELOG.md)：版本与修复记录
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：开发约定、仓库结构、启动自检机制、发布流程
- [`SECURITY.md`](SECURITY.md)：漏洞与敏感信息报告

## AI 辅助声明

本仓库的补丁、脚本、CI 配置与文档在 **DeepSeek Harness（AI 编程助手）** 辅助下完成；
所有改动经过静态检查、CI repack 与 Termux 真机回归，验证范围见
[`docs/verify-checklist.md`](docs/verify-checklist.md) 与 `CHANGELOG.md`。

## 安全

本仓不读取、复制或提交任何密钥。请不要在 issue / 日志里粘贴 token、cookie、API key
或完整 profile 配置。漏洞报告方式见 [`SECURITY.md`](SECURITY.md)。

## License

MIT。上游与第三方归属见 [`NOTICE`](NOTICE)。
