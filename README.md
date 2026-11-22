# termux-dsh

> ⚠️ **已归档（2026-11-21，GitHub 只读）**：唯一的 Termux 使用者已把运行层迁到
> **DSHBox（PRoot Debian + 上游 dsh）**，本仓停止维护。最后一个产物 `v0.2.2-rc.3-tdsh.2`
> （tarball 与 deb）仍可正常下载，老 Termux 环境可照旧安装；上游基线停在 `0.2.2-rc.3`，
> rc.4 / rc.5 未跟进。**归档时尚未完成的事项见文末「归档时未完成」**。

在 **Termux / Android arm64** 上一条命令装好 [dsh](https://github.com/deepseek-ai/deepseek-harness)。

它不是 dsh 的 fork，也不是搬运别人编译好的产物：本仓维护一条自动构建流水线，
从官方 npm 包出发，打上 Android 必需的补丁、编译缺失的原生模块，在 CI 里产出可复现的安装包，
让 dsh 在 Termux 上开箱即用。构建流程的技术细节见 [`docs/architecture.md`](docs/architecture.md)。

[![Repack](https://github.com/Starsky16/termux-dsh/actions/workflows/repack.yml/badge.svg?branch=main)](https://github.com/Starsky16/termux-dsh/actions/workflows/repack.yml)
[![Release](https://img.shields.io/github/v/release/Starsky16/termux-dsh?label=release)](https://github.com/Starsky16/termux-dsh/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Termux%20arm64-informational)

> **归档前状态（2026-11-14，历史）**：`v0.2.2-rc.3-tdsh.1` 已在 Termux 真机验证通过
> （vivo Android 16 / aarch64）：CI 构建全绿、`dsh-termux-verify` 全项 PASS、
> `dsh web` 冒烟启动正常。上游 `0.2.2-rc.3` 仍无稳定版，但本仓 `main` 的构建直接作为
> 正式 Release（Latest）发布，版本号保留上游 `rc` 段。
>
> rc.3 依赖膨胀：安装包约 261 MB（deb 108 MB），安装后运行时约 1.5 GB，请预留 **2 GB** 磁盘。

## 它解决什么问题

dsh 官方只发 npm 包，没有适配 Android：原生模块（koffi、node-pty 等）没有 arm64 Android
版本，部分代码在 Android 的 SELinux / Bionic 环境下跑不起来。`termux-dsh` 把这些全部
处理好，你只需要执行一条安装命令。

- **归本仓管**：dsh 本体与其官方依赖在 Termux 上运行的一切问题。
- **不归本仓管**：第三方插件的适配、修复与安装（归 [dsh-compat](https://github.com/Starsky16/dsh-compat)
  或插件作者）。

## 环境要求

- Termux **原生** aarch64（非 proot）；Android 8 及以上。
- 约 **2 GB** 可用磁盘；首次安装 10–20 分钟（rc.3 起安装包 261 MB / deb 108 MB，取决于网络）。
- 其余依赖（Node.js、git、curl、ripgrep 等）安装脚本会自动补齐。

## 快速开始

**方式零：npm（⚠️ 从未端到端验证，不推荐）**

> ⛔ **这条渠道从来没有跑通过**：CI 的 OIDC 自动发布尝试过四次均告失败（npm 强制 passkey 2FA，
> trusted publisher 未配成）；公共 npm 上只有 2026-11-07 手工发的一次
> `0.2.2-rc.1-tdsh.1`，**没有任何安装回归记录**，包内仍是 rc.1 时代的内容（含后来已删除的补丁）。
> 请改用方式一 / 方式二，或直接从 GitHub Release 下载。以下命令与说明仅作历史记录：

```bash
npm i -g termux-dsh
termux-fix-shebang "$PREFIX/bin/dsh" "$PREFIX/bin/termux-dsh"
dsh --version
```

npm 包只是安装器：运行时按版本从 GitHub Release 下载并校验 sha256，首次启动会自动补下载
（约 133 MB）。npm 12 默认拦截 `postinstall`，所以需要手动跑一次 `termux-fix-shebang`；
若你愿意审批脚本（`npm install-scripts approve termux-dsh`），安装时就会先下载好。
`npm i -g termux-dsh@next` 为 dev 构建；非 Termux/arm64 环境会拒绝安装。

**方式一（推荐）：一条命令自动安装**

```bash
pkg update
pkg install -y git
git clone https://github.com/Starsky16/termux-dsh.git ~/code/termux-dsh
cd ~/code/termux-dsh
bash bootstrap.sh
```

脚本会自动解析最新的**正式** Release、下载校验、安装并做安装后自检。
分支上的 `-dev.<N>` 预发布构建不会被自动选中（需要时用 `TDSH_RELEASE_BASE` 指定）。
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
dsh --version   # 应输出与所装包一致的 <上游版本>-tdsh.<rev>，如 0.2.2-rc.3-tdsh.1
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
npm uninstall -g termux-dsh   # 方式零（npm 包）装的
npm uninstall -g dsh-termux   # 方式一（bootstrap 的 tarball）装的
dpkg -r dsh-termux            # 方式二装的（会一并移除 ~/bin/dsh）
```

配置备份在 `~/.dsh/profiles/web/cordis.patch.yml.bak-*`，需要时可手工恢复。

> **用了 [dsh-compat](https://github.com/Starsky16/dsh-compat) 的话**：升级/重装后包内
> 文件会回到官方原样，需重跑一次它的 `patch.mjs --apply`；启动时看到
> 「L2 补丁未就绪」提示就是这个原因。机制说明见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 已知限制

- 上游最新是 `0.2.2-rc.3`（仍为候选版）；本仓 `main` 的构建直接作为**正式 Release（Latest）**发布，
  版本号保留上游的 `rc` 段以标明基座，不冒充上游稳定版。
- **HMR（热重载）在 Termux 上禁用**；修改配置/插件后需重启 `dsh web`。
- 图像处理走 wasm 版 sharp（不是 Android 原生包）；常用读图已在真机验证，
  特殊格式仍可能受 wasm 能力限制。
- 插件适配不在本仓范围；插件升级若把官方原包拉进 profile，需按
  [`CONTRIBUTING.md`](CONTRIBUTING.md) 重跑补丁脚本。
- 本仓不生成 Flutter / WPF / WinRT 产物，也不承担这些工具链。

## 归档时未完成（2026-11-21）

归档原因是运行层迁移，而非技术失败，所以下列事项**没有做完**，记录备查。

### 构建与性能

- **wrapper 性能**：`~/bin/dsh` 每次启动仍跑 `npm root -g`（实测 617 ms）与
  `node selfcheck.mjs`（430 ms，相对裸调用多约 1 秒）；「编译期写死
  `${PREFIX}/lib/node_modules` + selfcheck stamp 缓存」的方案未落地。
- **补丁面 7 → 5 未做**：`patches/core/ripgrep.patch` 未换成 `repack/platforms.sh` 里的伪造平台包
  （`@vscode/ripgrep-android-arm64` 壳）；`patches/core/node-addon-system-softlock.patch`
  （108 行软锁）未换成 koffi 绑定真 `flock(2)` 的极小补丁；`patches/manifest.json` 与
  `repack/verify-package.sh` 的对应断言也未更新。

### 兼容性与验证

- **Android 16 硬链接兜底未实现**：`/data` 禁止 `link(2)`，本仓未加 `lib/fs-link-fallback.cjs`，
  wrapper 也未注入 `NODE_OPTIONS=--require`，因此 `ds-harness-remote` 0.6.5 的 `publishExclusive`
  会失败、只能停在 0.6.4；上游 issue 未提。
- **L2 加载器隔离补丁未再判定**：随上游结构变化，`dsh-client-modules/lib/client.js` 的补丁锚点
  未重锚，「保留 / 缩减 / 退役」未做结论（该补丁由姊妹仓维护，不在本仓）。
- **版本身份垫片的 v3 证据未独立留档**：构建生成与双校验断言已完成，唯
  `harness.remote.v3` capabilities 证据未留存。
- 插件安装（可选项）与 HMR 降级行为未验证。

### 发布与分发

- **npm 渠道从未跑通**：CI 的 OIDC 自动发布四次尝试均失败（passkey 2FA / trusted publisher 未配成）；
  公共 npm 上只有 2026-11-07 手工发的 `0.2.2-rc.1-tdsh.1`，**没有任何安装回归记录**，
  包内仍是 rc.1 时代内容（含后来已删除的补丁），且未弃用（需登录 + 2FA）。
- CI 缺一条 `dsh web --no-open --port 0` 的端口存活冒烟（此前出现过静默回归）。
- 手机侧兼容软链 `~/code/dsh-termux-patches` 未纳入任何脚本（换机后需手工重建）。

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
