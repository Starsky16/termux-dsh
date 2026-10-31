# PATCHES — Android/Termux 适配补丁

> **本仓范围只到 dsh 本体（含其官方依赖）在 Termux/Android 上跑得起来的问题。**
> 第三方插件的适配、修复、隔离与安装不在本文件范围；插件问题交
> [dsh-compat](https://github.com/Starsky16/dsh-compat) 或插件作者。

## 基线

| 项 | 值 |
|---|---|
| 上游基座 | 官方 npm 包 `@deepseek-ai/dsh@0.2.1-rc.5`（CI 跟随 latest，见下） |
| 补丁生成时锁定的依赖 | `koffi@3.1.1`（`dsh-fs-local` 固定）、`node-pty@1.2.0-beta.15`（`dsh-subprocess-local` 固定） |
| A 类目标文件 | 在 `0.2.1-rc.2` 与 `0.2.1-rc.5` 间逐字节一致（2026-10-31 实测） |
| 产物版本 | `<upstream>-tdsh.<rev>`，例如 `0.2.1-rc.5-tdsh.1` |

**CI 跟 latest 的策略**：`repack.yml` 每次手动 dispatch 时解析 `@deepseek-ai/dsh@latest`，
再对每个 target 做 **pristine 哈希 / 锚点断言**。任一断言失败 → 构建非 0 → 不发布
Release；上一次可用版本保留。上游改版后按本文「重生成方法」更新补丁与 manifest。

A 类补丁路径相对**目标包根**，例如 `patches/core/fs-local.patch` 作用于
`node_modules/@deepseek-ai/dsh-fs-local/`，文件为 `lib/index.js`。
`patches/apply.sh` 只负责 profile 树（`dsh plugin add` 会把 pristine 包拉进来遮蔽全局树）；
全局树在 `repack/` 阶段已经烤好。

---

## A. 宿主补丁（烤进包 + profile 树兜底）

共 7 个 target / 8 个文件（`node-addon-system` 含 `flock.js` 与新增 `softlock.js`）。

| # | 目标 | 症状 | 改法 | 补丁 |
|---|---|---|---|---|
| A1 | `@vscode/ripgrep/lib/index.js` | 平台包只有 darwin/win32/linux，Android 上 `require.resolve` 抛错，所有 `grep`/`glob` 挂 | 平台包存在时优先；否则回退 PATH 上的 `rg`（Termux：`pkg install ripgrep`） | `core/ripgrep.patch` |
| A2 | `@deepseek-ai/dsh-fs-local/lib/index.js` | SELinux 拒 `link(2)`（EACCES），`write` 新建文件必败；覆盖已存在文件正常 | `linkFile` 遇 EACCES/EPERM/ENOTSUP/EOPNOTSUPP/ENOSYS 时用 `copyFile(..., COPYFILE_EXCL)`，保持 no-replace | `core/fs-local.patch` |
| A3 | `@deepseek-ai/dsh-attachment-local/lib/index.js` | 祖先目录 `/data/data` 为 `0771`，`open(O_RDONLY)` 报 EACCES；对象发布用 hardlink 也失败，`read_image` 挂 | 祖先 durability walk 对 Android 的 EACCES/EPERM 视作已 durable；两处 `link` 同样回退 `COPYFILE_EXCL` | `core/attachment-local.patch` |
| A4 | `@deepseek-ai/dsh-spill-local/lib/index.js` | 祖先信任规则要求非 group-writable，`/data/data` 与 Termux files 目录都是 `0771`，所有 spill root 被跳过 | Android 分支：仅当祖先既非 sticky、非本进程所有、且本进程确实可写时才判不安全；否则继续向上 | `core/spill-local.patch` |
| A5 | `@deepseek-ai/dsh-sandbox-local/lib/index.js` | 无 Landlock/bwrap，`PLATFORM_CHAINS.android` 为空，`confine()` 抛 `SANDBOX_UNAVAILABLE`，所有 exec 工具拒跑 | 新增 opt-in `allowUnconfinedFallback`：无可用 rung 时告警一次并以 `enforcement: "partial"` 放行；默认关闭，上游 fail-closed 语义不变 | `core/sandbox-local.patch` |
| A6 | `@deepseek-ai/dsh-web-fetch-http/lib/index.js` | 本机 resolver 把域名解析进 `198.18.0.0/15`，SSRF 守卫全拒 | 新增 opt-in `allowBenchmarkAddresses`：只放行该保留段，不放行 loopback/private/link-local | `core/web-fetch-http.patch` |
| A7 | `@deepseek-ai/node-addon-system/lib/flock.js` + `lib/softlock.js` | 原生 flock 无 android-arm64 绑定，会话无法建立 | 原生绑定仍优先；加载失败时回退纯 JS `O_EXCL` sidecar + pid 探活；`releaseLock` 转发释放 | `core/node-addon-system-flock.patch` + `core/node-addon-system-softlock.patch` |

**A7 的 `softlock.js` 是新增文件**：manifest 中 `pristine_sha256` 为 `null`，`patched_sha256`
为该文件哈希；`apply.sh --revert` 会删除它。`flock.js` 补丁依赖 `softlock.js` 存在，
manifest 顺序固定为 softlock 先、flock 后。

---

## B. 移植层补丁（构建期，不进入 profile 树）

B 类补丁在 `repack/native/*.sh` 里对下载的源码副本执行，**不发布到 npm 包之外**。
每条都用单处精确匹配；匹配数 ≠ 1 即失败。

| # | 目标 | 性质 | 内容 | 补丁/步骤 |
|---|---|---|---|---|
| B1 | `koffi/lib/native/base/base.cc` | 源码补丁 | `StatAt` 的 `#if defined(__linux__)` 加 `&& !defined(__ANDROID__)`，Android 走 fstatat 回退（Bionic API 24 无 statx wrapper） | `platform/koffi-statx.patch` |
| B2 | 同上 | 源码补丁 | POSIX `ExecuteCommandLine` **整个函数体**用 `#if __ANDROID__ && __ANDROID_API__ < 28 → return false; #else ... #endif` 排除；不能只写 early return，编译器仍会检查不可达代码而报 `posix_spawn_*` 未声明 | `platform/koffi-commandline.patch` |
| B3 | `koffi/src/koffi/CMakeLists.txt` | 源码补丁 | Android 分支追加 `-Wl,--unresolved-symbols=ignore-all`（Node-API 符号由 Node 运行时提供） | `platform/koffi-cmake.patch` |
| B4 | `node-pty/binding.gyp` | 源码补丁 | Android 构建去掉 `-lutil`（Bionic 的 PTY API 在 libc，NDK sysroot 无 libutil） | `platform/node-pty-noutil.patch` |
| B5 | `@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js` | 源码补丁 | import 加 `rename`；`materializePosix` 在 Android 用 `rename(tmp, finalPath)` 发布，其余 POSIX 保留 `link` no-replace；**漏了会话存不住** | `platform/session-rename.patch` |
| B6 | `@deepseek-ai/dsh-hmr` | **配置替代** | 上游 rc.5 的 HMR 构造器仍要求 `ctx.loader.internal`；**禁用 HMR** 改在 `profile/overrides.yml`，`dsh-plugin-manager` 对 `hmr === undefined` 有 `no-hmr` 回退。**注意**：缺 `node-addon-require-builtin` 发生在 `cordis-plugin-loader` 的 host preparation，早于 HMR；禁用 HMR **不能**替代 B11 | `profile/overrides.yml` |
| B11 | `node-addon-require-builtin` | 原生构建 | `cordis-plugin-loader` 启动必经 `require('node-addon-require-builtin')`；上游 optionalDependencies **无 android 包**（`node-addon-require-builtin-android-arm64` 404）。从 public 源码 `a58d359…`（0.1.9）NDK 交叉编译 nodeabi backend，产物落到 loader 的 `build/nodeabi/node-v<modules>-android-arm64/require_builtin.node`；ABI 本机 = 137 | `repack/native/require-builtin.sh` |
| B7 | koffi 原生构建 | 构建步骤 | NDK toolchain + `cnoke.cjs -t android_arm64 --release`，API 24 / arm64-v8a；libc++ 静态链接（与 koffi 官方 Android 预编译一致，避免运行时 `libc++_shared.so` 依赖） | `repack/native/koffi.sh` |
| B8 | node-pty 原生构建 | 构建步骤 | Node headers + `node-gyp rebuild --arch=arm64 --nodedir=...`，CC/CXX/AR/LD/RANLIB 指向 NDK；产物入 `prebuilds/android-arm64/pty.node` | `repack/native/node-pty.sh` |
| B9 | esbuild / sharp | 平台件 | 显式装 `@esbuild/android-arm64@<ver>`；sharp 走 `@img/sharp-wasm32@<ver>` + `@emnapi/runtime`（native 平台包无 Android 条目） | `repack/platforms.sh` |
| B10 | `@deepseek-ai/dsh/lib/bin.js` | 源码补丁 | `dsh --version` 原本读 `dsh-app-boot/package.json`（上游版本）；重打包后改读根 `dsh-termux/package.json` 的 `version`，只影响显示，插件兼容性仍用上游 runtime version | `platform/tdsh-version.patch` |

> **B5 为什么不能漏**：官方 npm 包没有向日葵构建期那层 `rename` 兜底。Android 上
> `link(2)` 被 SELinux 拒绝，首次会话创建就会失败。
>
> **B6 的边界**：禁用 HMR 只影响热重载，不影响插件安装与运行；但它**不能**替代
> B11。`cordis-plugin-loader` 在 host preparation 阶段就 require
> `node-addon-require-builtin`，缺该 addon 时 `dsh web` 直接 fatal（2026-10-31
> 真机实测）。若上游将来把 HMR 改成可降级，删除 `profile/overrides.yml` 里的
> `hmr` 覆盖即可；B11 仍需保留，直到上游发布 android 预编译包。

---

## 重生成方法

### A 类（宿主 JS）

```bash
# 1) 取 pristine（版本与 manifest.base 一致）
mkdir -p /tmp/base && cd /tmp/base
npm pack "@deepseek-ai/dsh-fs-local@0.2.1-rc.5"
mkdir -p pkg && tar -xzf deepseek-ai-dsh-fs-local-0.2.1-rc.5.tgz -C pkg --strip-components=1

# 2) 对比 patches/core/fs-local.patch 的 b 侧，确认仍是预期修改
#    b 侧可先 `git apply` 到 pkg，再与仓库内维护的 patched 副本比对

# 3) 重新生成（路径相对包根）
diff -u --label a/lib/index.js --label b/lib/index.js \
  pkg/lib/index.js /path/to/patched/lib/index.js > patches/core/fs-local.patch

# 4) 校验 + 更新 manifest 的 pristine/patched 哈希
git -C pkg apply --check patches/core/fs-local.patch
sha256sum pkg/lib/index.js /path/to/patched/lib/index.js
```

`patches/manifest.json` 每个 target 的 `rel` 是相对包根的路径；`pristine_sha256` 来自
npm tarball，`patched_sha256` 来自打完后文件。两者任一不匹配都应视为漂移并停下。

### B 类（源码）

```bash
# 版本由 dsh 的依赖固定，不要用 latest
npm pack koffi@3.1.1
npm pack node-pty@1.2.0-beta.15

cd koffi-src && patch -p1 --dry-run < ../../patches/platform/koffi-statx.patch
patch -p1 --dry-run < ../../patches/platform/koffi-commandline.patch
patch -p1 --dry-run < ../../patches/platform/koffi-cmake.patch

cd node-pty-src && patch -p1 --dry-run < ../../patches/platform/node-pty-noutil.patch
```

源码补丁的锚点均取自对应 MIT 源码；**不要**从 `sunflower2333/dsh-android` 复制
`build-termux.sh` 或 `patch-dsh.mjs`（该仓无 LICENSE）。本项目只依据其 `PATCHES.md`
的**事实描述**，从 koffi / node-pty / `@deepseek-ai/*` 各自的 MIT 源码独立实现等价补丁。

### B6 / profile 覆盖

```bash
# profile 覆盖是幂等追加；已存在 allowUnconfinedFallback 时不会重复写
bash profile/apply-overrides.sh
```

`profile/overrides.yml` 同时包含 `hmr` 的 `disabled: true`。升级 dsh 后若上游已修复
HMR 的可降级路径，可删除该条并重跑 `apply-overrides.sh`（脚本只追加缺失的块，
不会自动删除旧条目；需手工编辑 profile 的 `cordis.patch.yml`）。

### B11 / require-builtin

```bash
BUILD=... WORK=... REPO_ROOT=... bash repack/native/require-builtin.sh
```

源码固定 commit `a58d3599a2e551d7d706d1ff796c9fd4bbaff63c`（公开仓
`deepseek-ai/dsh-node-addon-require-builtin`，0.1.9）。`node-gyp` 以
`narb_backend=nodeabi narb_product=require-builtin` 编译；产物必须落在
`node-addon-require-builtin/build/nodeabi/node-v<process.versions.modules>-android-arm64/require_builtin.node`
（本机 Node 24.22.1 → 137）。升级 dsh 带来的 ABI 变化时，重新 `--dump-config` 后真正
boot 一次；`--version` / `--help` / `--dump-config` 不触发 host preparation，CI 不能只靠它们。
