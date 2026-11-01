# Changelog

本仓版本规则：`<upstream-dsh-version>-tdsh.<rev>`。上游仍是 `0.2.1-rc.5` 时，
所有 Release 都保留上游的 `rc` 段；本仓**不冒充上游稳定版**。

## Unreleased

- 等 `@deepseek-ai/dsh` 发布稳定版后，从 `main` 发 `0.2.1-tdsh.1`（或对应上游版本）。
- 发布前给 `.github/workflows/repack.yml` 增加 `prerelease` 开关（当前 `gh release create`
  硬编码 `--prerelease`），并在 Termux 回归通过后标记 Latest。

## [0.2.1-rc.5-tdsh.4] — 2026-11-01

### Added

- 可选 Termux `.deb`：`repack/deb.sh` 把同一运行时树组装成
  `dsh-termux_<version>_aarch64.deb`，含 `$PREFIX/bin/dsh`、`dsh-termux-setup`、
  `dsh-termux-verify`、profile/补丁脚本与 `postinst` 首次配置。
- 包内 `verify.sh` / `docs/verify-checklist.md`，`dsh-termux-verify` 可直接跑回归。
- T7B `~/bin/dsh` selfcheck wrapper（`setsid`/`nohup`/`env`/`sh -c` 全覆盖）。

### Verified

- CI dry-run `41263482295`：tarball + `.deb` + `verify-deb.sh` 全 PASS；发布 `41263800744`。
- `.deb` 38,972,226 B，sha256 `5eeab825…`；tarball 121,726,911 B，sha256 `ed976c79…`。
- `.deb` Termux 安装/重装/卸载真机通过；`dsh-termux-verify` 12/12 PASS。
- 注意：deb 内 `client.js` 为 pristine，若装 dsh-compat 需在装/重装后重跑 `patch.mjs --apply`。

## [0.2.1-rc.5-tdsh.3] — 2026-10-31

**Termux 真机验证通过。** 首个可用的正式验收版本（GitHub 上仍是 pre-release，因为上游是 rc）。

### Added

- B11：交叉编译 `node-addon-require-builtin` 的 nodeabi backend，修复 `dsh web`
  在 host preparation 阶段 fatal（`No usable native binding ...`）。
- `verify-package.sh` 增加 require-builtin 文件/ELF 校验，以及三个原生件的
  `libc++_shared` 依赖断言。
- `repack/native/require-builtin.sh`；`patches/platform/require-builtin-static.patch`。
- `bootstrap.sh` 通过 GitHub API 解析最新 tag，支持 pre-release。

### Fixed

- node-pty / require-builtin 的 `binding.gyp` 加 `-static-libstdc++`，避免 Termux 缺
  `libc++_shared.so`。
- `patches/apply.sh --check` 在全新 profile（没有 profile 树）时误报 create 目标；现在先判断包是否存在。
- 非交互 shell 下 `bootstrap.sh` 未导出 `PREFIX` 时自动补 Termux 默认路径。

### Verified

- Termux 原生 aarch64 / Android 16 / Node 24.22.1。
- `bootstrap.sh` 8 步无 `die`；`verify.sh` 12/12 PASS；`dsh web` 稳定。
- 5 项行为：新建文件、重复新建被拒、`read_image`、`spill`、会话持久化跨重启全部通过。
- 发布资产：`dsh-termux.tgz` 121,772,701 B，sha256
  `0f027406fc0ba62993aa73120c72e5bdc2385a974c14d42d90591fa970592c25`。

## [0.2.1-rc.5-tdsh.2] — 2026-10-31

- 首次加入 B11；但原生件仍动态依赖 `libc++_shared`，真机未通过加载，已被 `tdsh.3` 取代。

## [0.2.1-rc.5-tdsh.1] — 2026-10-31

- 首个 repack Release；`dsh web` 因缺 `node-addon-require-builtin` android 绑定而
  启动失败，已被 `tdsh.3` 取代。
