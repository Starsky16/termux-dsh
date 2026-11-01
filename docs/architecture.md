# 架构

`termux-dsh` 分成三层，目标是让“官方 npm 包 + 可复现补丁 + Termux 接线”各自独立。

## 1. 分发层（CI / repack）

`.github/workflows/repack.yml` 只能手动 dispatch，输入 `upstream_version`、`rev`、`dry_run`。

`repack/repack.sh`：

1. `npm install --os=android --cpu=arm64 --ignore-scripts @deepseek-ai/dsh@<ver>`；
2. 按 `patches/manifest.json` 打 A 类宿主补丁，再打 B5 / B10；
3. `repack/platforms.sh` 补 esbuild（若存在）与 `@img/sharp-wasm32` + `@emnapi/runtime`；
4. `repack/native/*.sh` 用 NDK 交叉编译：
   - koffi（CMake / cnoke，`android_arm64`，`c++_static`）
   - node-pty（node-gyp，`prebuilds/android-arm64/pty.node`，静态 libc++）
   - node-addon-require-builtin（nodeabi backend，`build/nodeabi/node-v<ABI>-android-arm64/`）
5. 清理 host 平台预编译件，组装 `dsh-termux` 包；
6. `tar | gzip` 生成 asset，`repack/verify-package.sh` 做架构、文件、版本、补丁、
   `libc++_shared` 断言；
7. 可选：`repack/deb.sh` 把同一运行时树组装成 Termux `.deb`（含 launcher、profile 脚本与 `dsh-termux-setup`），`verify-deb.sh` 校验；
8. `dry_run=false` 时 `gh release create --prerelease`，上传 tarball 与 `.deb`。

## 2. 运行时层（profile 树）

`dsh plugin add` 会把 pristine `@deepseek-ai/*` 安装到
`~/.dsh/profiles/<name>/node_modules`，这会**遮蔽**全局安装树。

`patches/apply.sh` 因此只处理 profile 树：

- `--check`：只读，发现待打/漂移返回非 0；
- `--apply`：按 manifest 打补丁，`.orig` 备份；
- `--revert`：恢复 pristine；
- 先做全量漂移扫描，拒绝“打半套”。

全局安装树由 Release 自带补丁，不再在 Termux 上手工打。

## 3. 接线层（bootstrap / profile / wiring）

`bootstrap.sh`：

```
依赖 → 解析最新 tag（含 pre-release）→ 下载 + sha256
→ npm i -g --ignore-scripts → termux-fix-shebang
→ setup-env.sh → apply-overrides.sh
→ workflow-sync 存在时 link-workspace.sh
→ patches/apply.sh --check → verify.sh
```

- `profile/setup-env.sh`：在 `~/.zshenv` 写幂等 `termux-dsh` 标记块。
- `profile/apply-overrides.sh`：把 sandbox / approval / web-fetch / HMR 覆盖追加到
  profile 的 `cordis.patch.yml`，处理新 profile 的 `[]` 空数组。
- `wiring/link-workspace.sh`：两槽记忆、技能、hooks、bin、plans；目录型目标先备份。

## 补丁分类

- **A 类（host）**：dsh 官方依赖的 JS 源码补丁，锁 pristine / patched sha256，
  用于 SELinux 硬链接、spill 祖先、sandbox、web-fetch、ripgrep 回退等。
- **B 类（port）**：koffi / node-pty / session-persistence / HMR / 版本显示 /
  require-builtin 等移植层改动；B6 是 profile 配置替代，B11 是原生构建。

详细表与重生成方法见 [`../PATCHES.md`](../PATCHES.md)。

## 失败模式

- 上游版本变化 → manifest 哈希或 B 类锚点不匹配，CI 非 0，不发布。
- runner NDK 差异 → `verify-package.sh` 的架构 / libc++ 断言失败。
- 真机启动失败 → 先看 `dsh web` 的 host preparation，再查是否有新的 native addon 缺件；
  `--version` / `--help` / `--dump-config` **不触发** host preparation，不能作为启动冒烟。
