# termux-dsh

在 Termux（Android arm64）上一条命令装好 [dsh](https://github.com/deepseek-ai/deepseek-harness)，并打上 Android 必需补丁。

## 安装

```bash
pkg install -y git && git clone https://github.com/Starsky16/termux-dsh.git ~/code/termux-dsh
bash ~/code/termux-dsh/bootstrap.sh
```

## 能力边界

| 能做 | 不能做（走 WIN/CI） |
|---|---|
| dsh web + 插件 + LAN 远程 | Flutter `test` / `build apk` |
| `flutter analyze` / `pub get` | WPF / WinRT 目标 |
| `dotnet build` 插件类（EnableWindowsTargeting） | office 转换（缺 soffice） |

## 结构

```
bootstrap.sh                 一条命令：环境 → 装本仓 Release → env → 覆盖 → 接线 → verify
verify.sh                    真机回归（bash 可测项）
lib/common.sh                日志/断言/hash/幂等下载
patches/
├─ manifest.json             每个 target：包名、包内路径、pristine/patched sha256
├─ apply.sh                  --check/--apply/--revert，只打 profile 树
├─ core/*.patch              A 类宿主补丁（7 target / 8 文件）
└─ platform/*.patch          B 类移植层补丁（koffi/node-pty/session）
repack/
├─ repack.sh                 本地与 CI 共用：官方 npm 基座 → 原生 → 补丁 → pack → 校验
├─ native/{koffi,node-pty}.sh
├─ platforms.sh              esbuild/sharp 平台件
└─ verify-package.sh         产物架构/必需文件/版本/补丁断言
profile/{overrides.yml,apply-overrides.sh,setup-env.sh}   dsh 本体服务配置覆盖与环境块（幂等，不含插件）
wiring/link-workspace.sh     两槽记忆/技能/hooks/bin/plans 接线
docs/verify-checklist.md     需在会话里跑的行为项
.github/workflows/repack.yml 手动 dispatch 的重组构建
```

安装与分步验证见 [`INSTALL.md`](INSTALL.md)，补丁原理与重生成见 [`PATCHES.md`](PATCHES.md)。

> **M0 状态**：CI 重组包与首个 Release 尚未产出。发布前 `bootstrap.sh` 会在下载步骤
> 明确失败；开发/验证期请按 `INSTALL.md` 的分步操作。首个 Release 发布后本节删除。

## 已知问题

见 [`PATCHES.md`](PATCHES.md)（每条补丁：症状 → 根因 → 改法 → 适用版本 → 重生成方法）。

## 范围

**本仓只管 dsh 本体（含其官方依赖）在 Termux/Android 上跑得起来的问题。插件（第三方 npm 包）的适配、修复、隔离、安装一律不管。**

- 归属本仓：`@deepseek-ai/dsh-*` 宿主服务包补丁、koffi / node-pty / esbuild / sharp 原生与平台件、session-persistence / HMR 等 dsh 自身 JS 补丁、profile 配置覆盖。
- 不属本仓：L2 加载器隔离（归 [dsh-compat](https://github.com/Starsky16/dsh-compat)）、第三方插件文件修复、插件安装编排。

## 关联

- [dsh-compat](https://github.com/Starsky16/dsh-compat)：插件兼容层（L2 隔离 + L3 垫片 + L4 门禁）。本仓不再承担 L2。
- 分层说明见 workflow-sync 仓 `plans/2026-10-27-termux-dsh自建仓库.md` 与 `plans/2026-10-27-dsh插件兼容层.md`。

## License

MIT。上游与第三方归属见 `NOTICE`。
