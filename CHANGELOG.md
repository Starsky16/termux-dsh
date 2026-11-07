# Changelog

本仓版本规则：`<upstream-dsh-version>-tdsh.<rev>`。上游当前为 `0.2.2-rc.1`，
所有 Release 都保留上游的 `rc` 段；本仓**不冒充上游稳定版**。

## Unreleased

- 等 `@deepseek-ai/dsh` 发布稳定版后，从 `main` 发 `0.2.1-tdsh.1`（或对应上游版本）。
- 2026-11-07 起：本仓 `main` 的构建直接作为正式 Release（Latest）发布，
  `gh release create` 已去掉 `--prerelease` 并加 `--target "$GITHUB_SHA"`；
  版本号仍保留上游 `rc` 段。

## [0.2.2-rc.1-tdsh.1] — 2026-11-07

### Added

- npm 分发：`npm i -g termux-dsh` 安装器包（bootstrapper），运行时按版本从 Release
  下载并校验 sha256；CI 用 Trusted Publishing（OIDC）发布，不保存长期 token，
  `latest` ← main、`next` ← dev。npm 12 会拦 `postinstall`，安装后跑一次
  `termux-fix-shebang`，首次启动自动补下载。

### Changed

- 上游基线 `0.2.1-rc.5` → `0.2.2-rc.1`；`patches/manifest.json` 全部 A 类锚点按新版重新生成。
- A2 `fs-local`：上游重写了 `writeFileAtomic` 的上下文，补丁重建（语义不变：硬链接
  不可用时回退 `copyFile(..., COPYFILE_EXCL)`）。
- A3 `attachment-local`、A5 `sandbox-local`：补丁文本不变，pristine/patched 哈希更新。
- 平台层未变：koffi `3.1.1`、node-pty `1.2.0-beta.15`、require-builtin `0.1.9`；
  B1–B5、B10 锚点在新版上全部匹配。

### Removed

- A6 `web-fetch-http` 补丁与 `profile/overrides.yml` 的 web-fetch 覆盖：上游 0.2.2
  移除了公网 IP/SSRF 校验与 `allowBenchmarkAddresses` 配置项，补丁已无作用。
  `apply-overrides.sh` 会顺手清理旧 profile 中残留的该键。

### Verified

- 在隔离目录安装 `0.2.2-rc.1`、应用全部 A 类补丁：7 target / 7 文件哈希全匹配；
  B1–B5、B10 `patch --dry-run` 全通过；补丁后文件 `node --check` 通过。
- CI：dry-run `42330686925` 与发布 `42330930342` 全绿；A1–A7、B5/B10、三个原生件
  `static libc++`、`verify-package.sh` / `verify-deb.sh` 全 PASS。
- 真机（vivo iPA2575 / Android 16）：`dsh --version` = `0.2.2-rc.1-tdsh.1`；
  `dsh-termux-verify` 全项 PASS；`dsh web --no-open --port 0` 冒烟启动成功。
- 已知：`dsh-compat` 的 L2 补丁锚点尚未适配 0.2.2 的 `dsh-client-modules/lib/client.js`
  （安装后 `postinst` 重打报 drift），属姊妹仓跟进项，不阻塞 dsh 本体。

### Release

- 发布策略调整（2026-11-07 拍板）：从 `main` 的构建**直接作为正式 Release（Latest）**
  发布，`gh release create` 去掉 `--prerelease`；同时补上 `--target "$GITHUB_SHA"`，
  根治 tag 指向漂移。版本号仍保留上游 `rc` 段。
- 两条发布通道：`main` = 正式版；其它分支 = pre-release dev build，版本追加
  `-dev.<run_number>`，`bootstrap.sh` 自动跳过 dev tag。

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
