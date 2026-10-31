# Contributing

本仓只维护 **dsh 本体（含官方依赖）在 Termux/Android arm64** 的重组与补丁。
第三方插件的适配、修复、隔离、安装不在范围内（归 `dsh-compat` 或插件作者）。

## 分支

- `dev`：开发。
- `main`：默认/发布分支；正式 Release 从这里出。
- 小改动可以直接在 `dev` 提交；大改动先开分支，合并回 `dev` 后再快进 `main`。

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

涉及原生产物时，不要只在 WIN 上相信 `bash -n`：

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
2. 需要新版时 dispatch：
   - `upstream_version`：留空 = latest，或指定 npm 版本；
   - `rev`：同一上游版本的修订号；
   - `dry_run=false`。
3. 正式 Release 只在上游稳定版发布后做。当前 workflow 的 `gh release create` 硬编码
   `--prerelease`；正式发版前要加 `prerelease` 开关，并确认 `main` 的默认分支设置。
4. 发布后核对 asset 大小 / sha256，并在 Termux 上重跑 bootstrap + verify。

## 报告问题

请附：设备/Android/Termux 版本、`dsh --version`、`bash verify.sh` 输出、
复现步骤与完整报错。不要粘贴 token、cookie、API key 或完整 profile 配置。
安全问题见 [`SECURITY.md`](SECURITY.md)。
