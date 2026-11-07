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

## 1.1 单文件 .deb（可选）

Release 若附带 `dsh-termux_<version>_aarch64.deb`，可跳过 clone/bootstrap 直接安装：

```bash
# 如果之前用 npm 装过，先卸掉，避免 $PREFIX/bin/dsh 冲突
npm uninstall -g dsh-termux 2>/dev/null || true

pkg install ./dsh-termux_<version>_aarch64.deb
```

重装（幂等验证）请用 `pkg install --reinstall ./dsh-termux_<version>_aarch64.deb`。

包内包含完整运行时（`$PREFIX/lib/node_modules/dsh-termux`）、`$PREFIX/bin/dsh`
启动器、`$PREFIX/bin/dsh-termux-setup` 和 profile/补丁脚本。`postinst` 会尽力执行：

- `setup-env.sh`（`.zshenv` 环境块）
- `apply-overrides.sh`（sandbox / approval / HMR）
- `setup-selfcheck.sh`（`~/bin/dsh` wrapper）

需要重跑时：

```bash
dsh-termux-setup
exec zsh -l
dsh --version
dsh-termux-verify
```

卸载：

```bash
dpkg -r dsh-termux
# postrm 只删除本项目创建的 ~/bin/dsh；~/.dsh 与 .zshenv 保留
```

**L2 补丁会被覆盖：** `.deb` 内是运行时树，`@deepseek-ai/dsh-client-modules/lib/client.js`
是 **pristine**；如果装了 `dsh-compat`，安装/重装/卸载后必须重打 L2：

```bash
NM="$PREFIX/lib/node_modules/dsh-termux/node_modules"
node ~/code/dsh-compat/bin/patch.mjs --apply --node-modules "$NM"
```

T7B 的 `~/bin/dsh` selfcheck 会在缺失时告警，但不会自动重打。重装验证请用
`pkg install --reinstall ./dsh-termux_...deb`；启动日志写到 `"$TMPDIR/..."`，不要用 `/tmp`。

注意：`.deb` 依赖 `bash`、`nodejs-lts (>= 24.2)`、`ripgrep`、`coreutils`、`patch`、`pnpm`（市场页与 `dsh plugin add` 装插件走 `pnpm add`，必须依赖）；
原生件按当前 Node ABI（137）编译，Node 大版本升级后需重新出包。

## 2. 分步等价操作（排查时用）

```bash
# 1) 依赖
pkg install -y nodejs-lts python git curl ripgrep patch pnpm

# 2) 下载 Release 重组包（public 仓库，无需 token）
# 取最新 Release tag（main 的构建即正式 Release；旧版曾标 pre-release，故按 tag 取更稳）。
TAG="$(curl -fsSL 'https://api.github.com/repos/Starsky16/termux-dsh/releases?per_page=10' \
  | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$TAG" ] || { echo "无法解析最新 Release tag"; exit 1; }
BASE="https://github.com/Starsky16/termux-dsh/releases/download/$TAG"
curl -fL -o "$TMPDIR/dsh-termux.tgz" "$BASE/dsh-termux.tgz"
curl -fL -o "$TMPDIR/dsh-termux.tgz.sha256" "$BASE/dsh-termux.tgz.sha256"
( cd "$TMPDIR" && sha256sum -c dsh-termux.tgz.sha256 )

# 3) 全局安装（包内已含原生模块与 A/B 类补丁）
npm i -g --ignore-scripts "$TMPDIR/dsh-termux.tgz"
# npm 的 bin shebang 是 #!/usr/bin/env node，Termux 没有 /usr/bin/env
termux-fix-shebang "$(command -v dsh)" "$(npm root -g)/dsh-termux/lib/bin.js"

# 4) 环境变量（写入 ~/.zshenv 的 termux-dsh 标记块，幂等）
bash ~/code/termux-dsh/profile/setup-env.sh

# 5) profile 覆盖（sandbox / approval / HMR，幂等）
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

重组包版本形如 `0.2.2-rc.1-tdsh.1`，与上游 `-termux.` 包明确区分。
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
| `web_fetch` 全拒 | 0.2.2 起上游已移除 SSRF 校验；仍失败时查网络/代理与 `dsh --profile web --dump-config` |
| 会话无法保存 | 包内 B5（session-persistence 的 `rename` 兜底）是否生效；`verify.sh` 的会话补丁项 |
| 启动即崩、HMR 报缺 `--expose-internals` | 包内 B6（HMR 守卫）是否生效 |
| 安装原生模块时编译失败 | 不要自行编译：Release 包已含 `android-arm64` 产物 |

## 7. 已知限制

- 无 Landlock/bwrap ⇒ 沙箱只能降级为 `danger-full-access`，见 `PATCHES.md` A 类；
- 本机 DNS 把域名解析进 `198.18.0.0/15`，`web_fetch` 需要显式放行该保留段；
- `libreoffice` 缺失，office 转换不可用；
- Flutter/Android 出包、WPF/WinRT 构建不在 Termux 能力范围内。
