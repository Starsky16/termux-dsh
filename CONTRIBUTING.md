# Contributing

本仓只维护 **dsh 本体（含官方依赖）在 Termux/Android arm64** 的重组与补丁。
第三方插件的适配、修复、隔离、安装不在范围内（归 `dsh-compat` 或插件作者）。

## 分支与发布口径

- `dev`：开发分支。
- `main`：默认分支 / 发布分支（2026-10-31 起）；正式版从这里出。
- `main` 只随已验证版本推进；`dev` 可以领先。上游 `@deepseek-ai/dsh` 尚无稳定版
  （latest = `0.2.2-rc.1`），版本规则 `<upstream>-tdsh.<rev>`；**本仓 `main` 的构建直接
  作为正式 Release（Latest）发布**，版本号保留上游 `rc` 段以标明基座，不冒充上游稳定版。
- 发版不变式：**dev = main = tag = 构建源**。`gh release create` 不带 `--target` 时
  tag 会落在创建那一刻的 main HEAD 而非 run 的 checkout SHA——发布后核对
  `git ls-remote` 的 tag 指向，必要时 `gh api -X PATCH .../git/refs/tags/<tag>
  -f sha=<构建源> -F force=true` 修正；根治可给工作流的 release 步骤加
  `--target "$GITHUB_SHA"`。

## 仓库结构

```
bootstrap.sh                 一条命令：依赖 → Release → 安装 → env → 覆盖 → 接线 → verify
verify.sh                    真机回归（bash 可测项）
lib/common.sh                日志 / 断言 / sha256 / 幂等下载
patches/
├─ manifest.json             每个 target：包名、包内路径、pristine/patched sha256
├─ apply.sh                  --check / --apply / --revert，只打 profile 树
├─ core/*.patch              A 类宿主补丁（6 target / 7 文件）
└─ platform/*.patch          B 类移植层补丁（koffi / node-pty / session / require-builtin）
repack/
├─ repack.sh                 本地与 CI 共用：npm 基座 → 补丁 → 平台件 → 原生 → tar → 校验
├─ native/{koffi,node-pty,require-builtin}.sh
├─ deb.sh / verify-deb.sh    可选 Termux .deb 组装与校验
├─ platforms.sh              esbuild / sharp 平台件
└─ verify-package.sh         架构 / 必需文件 / 版本 / 补丁 / libc++ 断言
profile/                     dsh 服务配置覆盖与 Termux 环境块（幂等，不含插件安装）
wiring/link-workspace.sh     两槽记忆 / 技能 / hooks / bin / plans 接线
docs/                        verify-checklist 与架构说明
.github/workflows/repack.yml 手动 dispatch 的 CI repack
```

构建流程的分步说明见 [`docs/architecture.md`](docs/architecture.md)；
补丁动机与重生成见 [`PATCHES.md`](PATCHES.md)。

## 启动自检 wrapper（L2 补丁）

`profile/setup-selfcheck.sh`（bootstrap 自动调用）安装 `~/bin/dsh` wrapper
（`~/bin` 在 PATH 前置）：先调用 `~/code/dsh-compat/bin/selfcheck.mjs` 校验
profile 树的 L2 补丁，再 `exec` 真实 `$PREFIX/bin/dsh`。缺失/漂移只向 stderr
告警，**不阻塞、不自动修复**；未安装 `dsh-compat` 时完全跳过。

覆盖面：PATH 层 wrapper，直接执行、`setsid` / `nohup` / `env` / `sh -c` 全部经过；
只有绝对路径 `$PREFIX/bin/dsh` 或不含 `~/bin` 的干净 PATH 绕过（已文档化）。
`~/bin/dsh` 不会被 `npm i -g` 覆盖，升级后仍有效；重跑 `bootstrap.sh` 或
`profile/setup-selfcheck.sh` 可修复/重写（幂等，会移除旧 `.zshenv` 自检块并备份）。

```bash
# 单独安装/重写（幂等）
bash ~/code/termux-dsh/profile/setup-selfcheck.sh

# 回退：删除 wrapper；旧 .zshenv 块若需要可从 .bak-selfcheck-* 恢复
rm -f ~/bin/dsh
```

注意：**deb 包内的 `@deepseek-ai/*` 是 pristine**，装/重装会冲掉 dsh-compat 的
L2 补丁——postinst 会 best-effort 自动重打，失败时手工：

```bash
node ~/code/dsh-compat/bin/patch.mjs --apply \
  --node-modules "$PREFIX/lib/node_modules/dsh-termux/node_modules"
```

## 本地检查

提交前至少跑：

```bash
# 所有 shell 语法
for f in $(git ls-files '*.sh'); do bash -n "$f" || exit 1; done

# workflow YAML 可解析
python -c "import yaml; yaml.safe_load(open('.github/workflows/repack.yml'))"

# 补丁锚点 / manifest 哈希（在真实 npm 安装树上）
# 见 PATCHES.md；CI 的 repack.sh 会做完整校验

# 全新 profile 不应有假失败
mkdir -p /tmp/tdsh-empty/profiles/web
DSH_HOME=/tmp/tdsh-empty bash patches/apply.sh --check
```

涉及原生产物时，不要只在本地相信 `bash -n`：

- 先用 CI `workflow_dispatch` + `dry_run=true` 跑一遍；
- 检查 `verify-package.sh` 的 ARM / libc++ / patch 断言；
- 真机验证按 `docs/verify-checklist.md` 做，结果回填到对应 handoff。

## 提交

- 中文 Conventional Commits：`feat` / `fix` / `ci` / `chore` / `docs` / `refactor`。
- 不用 `git add -A`；按文件逐个暂存。
- 不提交 `*.orig` / `*.rej` / `node_modules/` / `dist/` / `*.tgz` / 密钥。
- 不把上游 npm 包、第三方 Android 产物或 `libc++_shared.so` 直接塞进仓库。

## Release 流程

1. 在 `main` 上确认 `dev` 已合并、CI `dry_run=true` 全绿。
2. 需要新版时 dispatch（**用 `gh workflow run`，不要用 `gh api .../dispatches`
   平铺参数——inputs 必须嵌套在 `inputs` 键下，平铺会报 422 "not permitted keys"**）：
   - `upstream_version`：留空 = latest；建议显式锁定已验证版本（如 `0.2.2-rc.1`）；
   - `rev`：同一上游版本的修订号；
   - `dry_run=false`。
3. 发布后核对：附件齐全（tarball + deb + 两份 sha256）且与 `.size`/sha256 对齐、
   非 draft / 非 prerelease（`gh release view --json isLatest,isPrerelease`）、tag 指向
   构建源（见「分支与发布口径」），然后真机重装（版本号回落时需
   `apt install --reinstall --allow-downgrades`）并跑 `dsh-termux-verify`。
4. 发布步骤已内置 `--target "$GITHUB_SHA"` 与正式 Release 标记；改动发布策略时
   同步更新本节与 `docs/architecture.md`。

## 报告问题

请附：设备/Android/Termux 版本、`dsh --version`、`bash verify.sh`（或 deb 装法的
`dsh-termux-verify`）输出、复现步骤与完整报错。不要粘贴 token、cookie、API key
或完整 profile 配置。
安全问题见 [`SECURITY.md`](SECURITY.md)。
