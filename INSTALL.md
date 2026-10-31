# 安装与验证

> 本仓只处理 **dsh 本体（含其官方依赖）在 Termux/Android 上跑得起来**的问题。
> 第三方插件的适配、修复、隔离与安装不在范围内：需要插件时自行 `dsh plugin add`。

## 0. 前提

- Termux（原生，非 proot），`uname -m` 为 `aarch64`；
- Node.js **>= 24.2**（`pkg install nodejs-lts` 当前满足）；
- 能访问 GitHub Releases 与 npm registry；
- 建议先 `termux-wake-lock`，避免长安装被 Android 杀进程。

## 1. 一条命令安装

```bash
pkg install -y git
git clone https://github.com/Starsky16/termux-dsh.git ~/code/termux-dsh
bash ~/code/termux-dsh/bootstrap.sh
```

`bootstrap.sh` 依次完成：环境检查 → 下载本仓 Release 重组包 → 校验 sha256 →
全局安装 → 写环境变量 → 写 profile 覆盖 → 接线记忆/技能 → 跑 `verify.sh`。

装完直接启动：

```bash
dsh web
```

## 2. 分步等价操作（排查时用）

```bash
# 1) 依赖
pkg install -y nodejs-lts python git curl ripgrep patch

# 2) 下载 Release 重组包（public 仓库，无需 token）
BASE=https://github.com/Starsky16/termux-dsh/releases/latest/download
curl -fL -o "$TMPDIR/dsh-termux.tgz" "$BASE/dsh-termux.tgz"
curl -fL -o "$TMPDIR/dsh-termux.tgz.sha256" "$BASE/dsh-termux.tgz.sha256"
( cd "$TMPDIR" && sha256sum -c dsh-termux.tgz.sha256 )

# 3) 全局安装（包内已含原生模块与 A/B 类补丁）
npm i -g --ignore-scripts "$TMPDIR/dsh-termux.tgz"

# 4) 环境变量（写入 ~/.zshenv 的 termux-dsh 标记块，幂等）
bash ~/code/termux-dsh/profile/setup-env.sh

# 5) profile 覆盖（sandbox / approval / web-fetch，幂等）
bash ~/code/termux-dsh/profile/apply-overrides.sh

# 6) 接线（两槽记忆、技能、hooks、bin、plans）
bash ~/code/termux-dsh/wiring/link-workspace.sh

# 7) 回归
bash ~/code/termux-dsh/verify.sh
```

> 只有当你之后自行 `dsh plugin add` 把 pristine 的 `@deepseek-ai/*` 拉进 profile 树时，
> 才需要额外跑 `bash ~/code/termux-dsh/patches/apply.sh --apply` 兜底。
> 这不是安装步骤，也不处理插件自身问题。

## 3. 验证清单

自动项：

```bash
bash ~/code/termux-dsh/verify.sh
```

期望全部 `PASS`。手工项见 [`docs/verify-checklist.md`](docs/verify-checklist.md)，
包括：新建文件、重复新建被拒、读取图片、大输出落盘、会话重启后仍在。

## 4. 升级

```bash
git -C ~/code/termux-dsh pull --ff-only
bash ~/code/termux-dsh/bootstrap.sh
```

重组包版本形如 `0.2.1-rc.5-tdsh.1`，与上游 `-termux.` 包明确区分。
升级后 `verify.sh` 仍须全 PASS；不绿就不要继续使用。

## 5. 回滚

```bash
npm uninstall -g dsh-termux
# 可选：清理 profile 覆盖与接线
```

本仓不保留应急回退安装路径：CI 锚点不绿时不会发布新 Release，
继续使用上一次可用的 Release 即可。

## 6. 常见故障

| 症状 | 先查 |
|---|---|
| `dsh` 命令不存在 / shebang 报错 | Node 是否 >= 24.2；`termux-fix-shebang "$(command -v dsh)"` |
| `grep`/`glob` 全部失败 | `pkg install ripgrep`；`node -e "import('@vscode/ripgrep')"` |
| 所有 `bash`/exec 工具被拒 | profile 覆盖是否写入 `allowUnconfinedFallback` |
| `web_fetch` 全拒 | profile 覆盖是否写入 `allowBenchmarkAddresses` |
| 会话无法保存 | 包内 B5（session-persistence 的 `rename` 兜底）是否生效；`verify.sh` 的会话补丁项 |
| 启动即崩、HMR 报缺 `--expose-internals` | 包内 B6（HMR 守卫）是否生效 |
| 安装原生模块时编译失败 | 不要自行编译：Release 包已含 `android-arm64` 产物 |

## 7. 已知限制

- 无 Landlock/bwrap ⇒ 沙箱只能降级为 `danger-full-access`，见 `PATCHES.md` A 类；
- 本机 DNS 把域名解析进 `198.18.0.0/15`，`web_fetch` 需要显式放行该保留段；
- `libreoffice` 缺失，office 转换不可用；
- Flutter/Android 出包、WPF/WinRT 构建不在 Termux 能力范围内。
