# npm 包发布设计（termux-dsh）

> 状态：已定稿（2026-11-07）· 决策：bootstrapper + Trusted Publishing（OIDC）
>
> 相关：`docs/architecture.md`、`CONTRIBUTING.md`「分支与发布口径」

## 1. 背景与目标

本仓目前通过 GitHub Release 分发 `dsh-termux.tgz` 与 `.deb`。增加 npm 分发，让用户可以用
`npm i -g termux-dsh` 安装。

**目标**

- 用户一条 `npm i -g termux-dsh` 得到可用的 Termux dsh 运行时
- npm 包与 GitHub Release 版本严格一一对应
- 发布凭据零长期存储：用 GitHub Actions OIDC（Trusted Publishing），不建 `NPM_TOKEN`

**非目标**

- 不做桌面/非 Termux 平台的 npm 包
- 不改变现有 tarball / deb 产物与安装路径
- 不把 133 MB 运行时塞进 npm 包

## 2. 为什么是 bootstrapper

npm registry 对大包有硬限制（社区实测 `ETOOLARGE` / 413），我们 gzip 后的运行时约 133 MB，
直接整包发布风险高。因此 npm 包只含安装器（< 100 KB）：

1. `postinstall` 按包版本从 GitHub Release 下载 `dsh-termux.tgz` 与 sha256
2. 校验后解压到包内 `runtime/`
3. 修 shebang、初始化 profile 覆盖
4. 之后 `dsh` / `termux-dsh` 两个 bin 直接 exec `runtime/lib/bin.js`

代价：安装时需要 133 MB 下载；好处：npm 包秒级发布、registry 存储与带宽压力小。

## 3. 包结构

```text
npm/
├─ package.json.tmpl     模板：version/bin/scripts.files/engines/tdsh 元数据
├─ bin/cli.mjs           启动器：解析 runtime 路径并 exec runtime/lib/bin.js
├─ bin/install.mjs       postinstall：下载 → 校验 → 解压 → 修 shebang → profile 初始化
├─ lib/download.mjs      Release 下载 + sha256 校验（支持 TDSH_RELEASE_BASE 镜像）
├─ lib/setup.mjs         shebang 修复、profile 覆盖、L2 重打（best-effort）
└─ share/                与 deb 的 $PREFIX/share/dsh-termux 同构：
                         lib/ profile/ patches/ docs/ verify.sh（从本仓复制）
```

生成的发布目录 `dist/npm/`：

- `package.json`：`name: termux-dsh`、`version`（注入）、`bin: { dsh, termux-dsh }`
- `files` 只含上述脚本与 profile，不含运行时

## 4. 安装流程（install.mjs）

1. 平台检查：`process.platform === "android"` 且 `process.arch === "arm64"`；
   否则报错退出并提示用 GitHub Release / deb。CI 测试用 `TDSH_NPM_SKIP_PLATFORM_CHECK=1` 绕过
2. 解析版本：取本包 `package.json.version`，拼 `v<version>` 作为 Release tag
3. 下载 `dsh-termux.tgz` 与 `dsh-termux.tgz.sha256`（`https://github.com/Starsky16/termux-dsh/releases/download/<tag>/`，
   `TDSH_RELEASE_BASE` 可覆盖）
4. 校验 sha256；不匹配即失败
5. `tar -xzf` 解压到包内 `runtime/`（要求系统有 tar；Termux 自带 bsdtar）
6. 修补 npm 生成的 bin shim：首行 `#!/usr/bin/env node` → `#!<process.execPath>`
7. best-effort：跑包内 `share/profile/` 的 setup-env / apply-overrides / setup-selfcheck
   （脚本结构与本仓 `profile/` 一致，`source ../lib/common.sh` 可直接工作）；
   若存在 `~/code/dsh-compat/bin/patch.mjs` 则重打 L2。失败只告警
8. 检测 `dsh` bin 是否被官方 `@deepseek-ai/dsh` 占用并提示（不会阻止安装）

### npm 12 的脚本审批（实测结论）

npm 12 默认拦截未审批的 `postinstall`，`--allow-scripts` 在项目级安装被拒、用户级
`.npmrc` 实测也未放行。因此**安装不能依赖 postinstall**：

- 入口兜底：`bin/cli.mjs` 启动时若 `runtime/` 缺失，自动执行一次安装流程再启动
- shebang：npm 的 `.bin` 是 symlink 指向 `bin/cli.mjs`，只需修入口文件；
  推荐安装后用 Termux 自带工具修一次：
  `termux-fix-shebang "$PREFIX/bin/dsh" "$PREFIX/bin/termux-dsh"`
- 若用户愿意审批脚本（`npm install-scripts approve termux-dsh`），postinstall 会在安装时
  就把运行时备好，首次启动无需等待

文档里的推荐命令因此是两条：`npm i -g termux-dsh` + `termux-fix-shebang …`。

## 5. CI 集成

`repack.yml` 步骤顺序：Repack → Upload build → **Publish release** → **Publish npm**。

1. 生成 npm 包：`node npm/make-package.mjs dist/npm "$(cat dist/version.txt)"`
2. 发布（`dry_run != true`）：
   - `main` → `npm publish dist/npm --tag latest --provenance`
   - 其它分支 → `npm publish dist/npm --tag next --provenance`
3. workflow 权限增加 `id-token: write`

失败策略：**npm 发布失败让 job 失败**以引起注意，但 GitHub Release 已经发布、不回收
（重跑该步骤即可补发 npm；npm 对已存在版本会报错，需要先确认版本未发过）。

## 6. 认证：Trusted Publishing

- npm 侧配置：包 `termux-dsh` → Settings → Trusted publishing →
  Repository `Starsky16/termux-dsh`、Workflow `repack.yml`、Environment 留空
- 配置有 **48 小时激活窗口**：配置后必须在此期间完成一次 OIDC 发布
- CI 不设 `NODE_AUTH_TOKEN`；npm CLI ≥ 11.5.1 自动走 OIDC
- 不创建、不使用 `NPM_TOKEN`

## 7. 首次发布引导（一次性）

1. 本地生成完整 bootstrapper 包（`node npm/make-package.mjs dist/npm 0.2.2-rc.1-tdsh.1`）
2. 本地 `npm publish dist/npm --tag latest`（交互 2FA）创建包
3. npm 网页配置 Trusted publishing
4. **48 小时内**触发一次 CI 发布（dev 分支 `next` 版本，版本号不同不会冲突）激活 OIDC
5. 之后所有发布由 CI 完成

## 8. 版本与通道

- npm 版本 = Release 版本（`<upstream>-tdsh.<rev>`；dev 构建带 `-dev.<run>`）
- `latest` ← `main` 构建；`next` ← dev 构建
- `npm i -g termux-dsh` = 最新正式版；`npm i -g termux-dsh@next` = dev 构建

## 9. 错误处理

| 情况 | 行为 |
|---|---|
| 非 Termux / 非 arm64 | install 直接失败并给出说明 |
| 下载失败 / 404 | 失败，提示手动 `bootstrap.sh` 或下载 deb |
| sha256 不匹配 | 失败，删除半成品 runtime |
| tar 缺失或解压失败 | 失败，删除半成品 |
| profile 初始化失败 | 仅告警，不阻塞 |
| npm 发布失败 | CI job 失败；GitHub Release 保留 |

## 10. 验证

- CI（ubuntu）：`TDSH_NPM_SKIP_PLATFORM_CHECK=1 npm i -g ./termux-dsh-*.tgz` 完整跑通下载/解压/校验
- 本地：`npm pack` 检查包体积 < 100 KB、文件清单正确
- 真机：`npm i -g termux-dsh` → `dsh --version`；`DSH_PKG=<runtime> bash share/verify.sh` 全绿
  （verify.sh 通过 `DSH_PKG` 指向 npm 包装内的 runtime）
- 回归：重复安装（幂等）、`npm uninstall -g termux-dsh` 后无残留 bin

## 11. 风险

- 133 MB 下载受网络影响；镜像/代理不可控
- npm 包依赖对应 Release 存在，删 Release 等于废掉该版本安装
- `dsh` bin 与官方包同名，全局安装会覆盖（有意，与 deb 一致）
- Trusted publishing 配置 48 小时未激活即失效
