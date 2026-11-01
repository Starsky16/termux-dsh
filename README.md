# termux-dsh

在 **Termux / Android arm64** 上一条命令装好 [dsh](https://github.com/deepseek-ai/deepseek-harness)：
从官方 npm 包出发，交叉编译 Android 原生模块，打上 SELinux / Bionic / Node-API 必需补丁，
再按 CI 产物分发。

[![Repack](https://github.com/Starsky16/termux-dsh/actions/workflows/repack.yml/badge.svg?branch=main)](https://github.com/Starsky16/termux-dsh/actions/workflows/repack.yml)
[![Release](https://img.shields.io/github/v/release/Starsky16/termux-dsh?include_prereleases&label=release)](https://github.com/Starsky16/termux-dsh/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Termux%20arm64-informational)

> **当前状态（2026-10-31）**：`v0.2.1-rc.5-tdsh.3` 已在 Termux 真机验证通过
> （vivo iPA2575 / Android 16 / aarch64）：`bootstrap.sh` 8 步无 `die`、`verify.sh` 12/12 PASS、
> `dsh web` 稳定、5 项行为与会话持久化全部通过。上游 dsh 目前**没有稳定版**（latest 仍是
> `0.2.1-rc.5`），所以本仓也先以 pre-release 分发。

## 这是什么

`termux-dsh` **不是** dsh 的 fork，也不是把第三方 Android 产物搬过来。它是一条可复现的
**repack 流水线**：

1. 从官方 `@deepseek-ai/dsh` npm 包安装 android/arm64 依赖树；
2. 对 dsh 自身与官方依赖打 A/B 类补丁（硬链接、PTY、koffi、会话发布、原生 addon 等）；
3. 用 Android NDK 交叉编译 koffi / node-pty / node-addon-require-builtin；
4. 显式补 esbuild / sharp 的 Android 平台件；
5. 组装成 `dsh-termux` tarball，发布为 GitHub Release；
6. Termux 侧 `bootstrap.sh` 下载、校验、全局安装、写环境、应用 profile 覆盖、接线、回归。

补丁动机、适用版本与重生成方法见 [`PATCHES.md`](PATCHES.md)；分步安装见 [`INSTALL.md`](INSTALL.md)。

## 适用范围

**本仓只管 dsh 本体（含其官方依赖）在 Termux/Android 上跑得起来的问题。**

- 归属本仓：`@deepseek-ai/dsh-*` 宿主补丁、koffi / node-pty / esbuild / sharp 原生与平台件、
  session-persistence / HMR 等 dsh 自身 JS、profile 配置覆盖、Termux 安装/回归脚本。
- 不属本仓：第三方插件适配/修复/隔离/安装（归 [dsh-compat](https://github.com/Starsky16/dsh-compat)
  或插件作者）；Flutter / WPF / WinRT 等非 dsh 工具链。

## 环境要求

- Termux **原生** aarch64（非 proot）；Android 8+（原生 API 24 起）。
- Node.js ≥ 24.2（`pkg install nodejs-lts`）。
- 约 1 GB 可用磁盘；首次 `npm i -g` 约 8–9 分钟（120 MB 本地 tarball，不再联网拉依赖）。
- 已安装 `git` / `curl` / `patch` / `file` / `ripgrep`（`bootstrap.sh` 会补）。

## 快速开始

```bash
pkg update
pkg install -y git
git clone https://github.com/Starsky16/termux-dsh.git ~/code/termux-dsh
cd ~/code/termux-dsh
bash bootstrap.sh
```

`bootstrap.sh` 会通过 GitHub API 解析**最新 tag**（因为 Release 是 pre-release，
`/releases/latest` 不包含它），然后自动完成安装与回归。也可以显式指定：

```bash
TDSH_RELEASE_BASE=https://github.com/Starsky16/termux-dsh/releases/download/v0.2.1-rc.5-tdsh.3 \
  bash bootstrap.sh
```

启动：

```bash
dsh web
```

## 验证

```bash
dsh --version     # 0.2.1-rc.5-tdsh.3
bash verify.sh    # 应为：结果：全部 PASS
```

`verify.sh` 覆盖包版本、koffi / node-pty 架构、B5 会话发布、profile 树补丁、sandbox /
web-fetch / HMR 配置、技能与 hooks 接线。以下项目需要启动 `dsh web` 后在会话里手工做：

- 新建文件（SELinux `link(2)` 的 `COPYFILE_EXCL` 兜底）
- 对同一路径重复新建被拒（不得静默覆盖）
- `read_image` 读取本机 PNG
- `seq 1 200000` 大输出 spill
- 新建会话 → 重启 `dsh web` → 会话仍在

完整步骤与预期见 [`docs/verify-checklist.md`](docs/verify-checklist.md)。

## 启动自检（L2 补丁）

`bootstrap.sh` 会在 `~/.zshenv` 写入一个独立的 `dsh()` 函数（标记块
`# >>> termux-dsh selfcheck >>>`）：如果 `~/code/dsh-compat/bin/selfcheck.mjs`
存在，就在每次交互式 `dsh` 调用前校验全局树里的 L2 补丁；缺失/漂移只向 stderr
告警，**不阻塞、不自动修复**。未安装 `dsh-compat` 时完全跳过。

写入后重开 shell（或 `exec zsh -l`）生效；`bootstrap.sh` 当前 shell 不会自动加载这个函数。

```bash
# 单独重写（幂等）
bash ~/code/termux-dsh/profile/setup-selfcheck.sh

# 回退：删除整个标记块后重开 shell
sed -i '/^# >>> termux-dsh selfcheck >>>$/,/^# <<< termux-dsh selfcheck <<<$/d' ~/.zshenv
```

注意：只覆盖交互 shell 里**直接执行**的 `dsh`；`command dsh`、绝对路径、桌面快捷方式，
以及 `setsid` / `nohup` / `env` / `sh -c` 等外部命令都会绕过这个函数——日常
`setsid nohup dsh web` 也覆盖不到。升级 `dsh-termux` 后若看到
“L2 补丁未就绪”，需手动用 `dsh-compat` 的 `patch.mjs --apply` 重打。

## 升级与回滚

升级：重新跑 `bootstrap.sh` 即可（会覆盖全局 `dsh-termux`）。若之后执行过
`dsh plugin add`，pristine `@deepseek-ai/*` 可能被拉进 profile 树，需要：

```bash
bash ~/code/termux-dsh/patches/apply.sh --check
bash ~/code/termux-dsh/patches/apply.sh --apply
```

回滚：

```bash
npm uninstall -g dsh-termux
# profile 覆盖的备份在 ~/.dsh/profiles/web/cordis.patch.yml.bak-*
# ~/.zshenv 中的 termux-dsh 标记块按 setup-env.sh 的标记手工删除
```

## 分支与发布

- `dev`：开发分支。
- `main`：默认分支 / 发布分支（2026-10-31 起）；正式版从这里出。
- `main` 只随已验证版本推进；`dev` 可以领先（当前 T7 自检待真机验证）。最新 Release 仍是 **pre-release**。
- 正式 Release 等上游 `@deepseek-ai/dsh` 发布稳定版后再切；版本规则
  `<upstream>-tdsh.<rev>`，上游 rc 阶段不冒充稳定版。

## 目录

```
bootstrap.sh                 一条命令：依赖 → Release → 安装 → env → 覆盖 → 接线 → verify
verify.sh                    真机回归（bash 可测项）
lib/common.sh                日志 / 断言 / sha256 / 幂等下载
patches/
├─ manifest.json             每个 target：包名、包内路径、pristine/patched sha256
├─ apply.sh                  --check / --apply / --revert，只打 profile 树
├─ core/*.patch              A 类宿主补丁（7 target / 8 文件）
└─ platform/*.patch          B 类移植层补丁（koffi / node-pty / session / require-builtin）
repack/
├─ repack.sh                 本地与 CI 共用：npm 基座 → 补丁 → 平台件 → 原生 → tar → 校验
├─ native/{koffi,node-pty,require-builtin}.sh
├─ platforms.sh              esbuild / sharp 平台件
└─ verify-package.sh         架构 / 必需文件 / 版本 / 补丁 / libc++ 断言
profile/                     dsh 服务配置覆盖与 Termux 环境块（幂等，不含插件安装）
wiring/link-workspace.sh     两槽记忆 / 技能 / hooks / bin / plans 接线
docs/                        verify-checklist 与架构说明
.github/workflows/repack.yml 手动 dispatch 的 CI repack
```

## 已知限制

- 上游仍是 `0.2.1-rc.5`，所以当前 Release 是 pre-release；正式版等上游稳定。
- **HMR 在 Termux 上禁用**（profile 覆盖）；修改配置/插件后需重启 `dsh web`。
- `sharp` 走 `@img/sharp-wasm32`（不是 Android native 包）；图像路径已在真机读图项验证，
  但特殊格式仍可能受 wasm 能力限制。
- 插件适配不在本仓范围；插件升级后若把 pristine 包拉进 profile 树，需重跑 `patches/apply.sh`。
- 本仓不生成 Flutter / WPF / WinRT 产物，也不承担这些工具链。

## 文档

- [`INSTALL.md`](INSTALL.md)：分步安装、验证、升级、故障排查
- [`PATCHES.md`](PATCHES.md)：A/B 补丁原理、基线版本、重生成方法
- [`docs/architecture.md`](docs/architecture.md)：分发 / 运行时 / 接线三层与 CI 流程
- [`docs/verify-checklist.md`](docs/verify-checklist.md)：会话内行为检查
- [`CHANGELOG.md`](CHANGELOG.md)：版本与修复记录
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：开发、自检、发布约定
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
