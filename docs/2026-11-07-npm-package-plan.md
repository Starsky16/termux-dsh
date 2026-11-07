# npm 包发布实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: 按任务顺序执行；每个 Task 完成后跑该任务的验证命令再进入下一个。
> 设计依据：`docs/2026-11-07-npm-package-design.md`（已批准）。

**Goal:** 让 `npm i -g termux-dsh` 能在 Termux 上装出可用的 dsh，并通过 CI 用 OIDC 自动发布。

**Architecture:** npm 包只含 bootstrapper；`postinstall` 按包版本从 GitHub Release 下载
`dsh-termux.tgz`、校验 sha256、解压到包内 `runtime/`，随后修复 bin shebang 并 best-effort
初始化 profile。CI 复用 `repack.yml`，在发布 Release 之后用 `npm publish --provenance`
以 Trusted Publishing 发布。

**Tech Stack:** Node 24（内置 `fetch`/`node:test`/ESM）、bash、GitHub Actions、npm CLI ≥ 11.5.1。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `npm/package.json.tmpl` | npm 包模板：name/version 占位/bin/scripts/files/engines |
| `npm/bin/cli.mjs` | `dsh` / `termux-dsh` 启动器，exec `runtime/lib/bin.js` |
| `npm/bin/install.mjs` | postinstall 主流程（平台检查 → 下载 → 校验 → 解压 → 收尾） |
| `npm/lib/download.mjs` | `releaseTag()`、`download()`、`verifySha256()` 纯函数/IO |
| `npm/lib/setup.mjs` | `fixBinShebang()`、`runProfileSetup()`、`repatchL2()` |
| `npm/make-package.mjs` | 构建期生成 `dist/npm/`：注入版本、复制 bin/lib、复制 share/ |
| `npm/test/download.test.mjs` | node:test 单测：tag 拼接、sha256 校验、URL 构造 |
| `.github/workflows/repack.yml` | 改：`id-token: write`、Build npm package、Publish to npm |
| `README.md` / `INSTALL.md` / `CHANGELOG.md` / `CONTRIBUTING.md` | 安装方式与发布说明 |

`share/` 在构建时从仓库根复制：`lib/ profile/ patches/ docs/verify-checklist.md verify.sh`，
与 deb 的 `$PREFIX/share/dsh-termux` 同构，安装后 `share/verify.sh` 可用
（`DSH_PKG=<runtime>` 指向包内运行时）。

---

## Task 1: download 工具与单测

**Files:**
- Create: `npm/lib/download.mjs`
- Create: `npm/test/download.test.mjs`

- [ ] **Step 1: 写失败测试**

```js
// npm/test/download.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { releaseTag, releaseUrl, verifySha256 } from "../lib/download.mjs";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";

test("releaseTag 加 v 前缀", () => {
  assert.equal(releaseTag("0.2.2-rc.1-tdsh.1"), "v0.2.2-rc.1-tdsh.1");
});

test("releaseUrl 指向 GitHub Release 资产", () => {
  assert.equal(
    releaseUrl("0.2.2-rc.1-tdsh.1", "dsh-termux.tgz"),
    "https://github.com/Starsky16/termux-dsh/releases/download/v0.2.2-rc.1-tdsh.1/dsh-termux.tgz"
  );
});

test("TDSH_RELEASE_BASE 覆盖基址", () => {
  const old = process.env.TDSH_RELEASE_BASE;
  process.env.TDSH_RELEASE_BASE = "https://mirror.example/rel";
  try {
    assert.equal(releaseUrl("1.0.0", "x.tgz"), "https://mirror.example/rel/v1.0.0/x.tgz");
  } finally {
    if (old === undefined) delete process.env.TDSH_RELEASE_BASE;
    else process.env.TDSH_RELEASE_BASE = old;
  }
});

test("verifySha256 校验通过", async () => {
  const dir = await mkdtemp(join(tmpdir(), "tdsh-dl-"));
  const file = join(dir, "a.bin");
  await writeFile(file, "hello");
  const digest = createHash("sha256").update("hello").digest("hex");
  assert.equal(await verifySha256(file, digest), true);
});

test("verifySha256 不匹配返回 false", async () => {
  const dir = await mkdtemp(join(tmpdir(), "tdsh-dl-"));
  const file = join(dir, "a.bin");
  await writeFile(file, "hello");
  assert.equal(await verifySha256(file, "0".repeat(64)), false);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `node --test npm/test/download.test.mjs`
Expected: FAIL（`Cannot find module '../lib/download.mjs'`）

- [ ] **Step 3: 实现 download.mjs**

```js
// npm/lib/download.mjs
import { createHash } from "node:crypto";
import { createWriteStream } from "node:fs";
import { readFile } from "node:fs/promises";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

const DEFAULT_REPO = "Starsky16/termux-dsh";
const DEFAULT_BASE = `https://github.com/${DEFAULT_REPO}/releases/download`;

export function releaseTag(version) {
  return `v${version}`;
}

export function releaseUrl(version, asset) {
  const base = (process.env.TDSH_RELEASE_BASE || DEFAULT_BASE).replace(/\/+$/, "");
  return `${base}/${releaseTag(version)}/${asset}`;
}

export async function download(url, dest) {
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`下载失败 ${res.status} ${url}`);
  if (!res.body) throw new Error(`响应无 body：${url}`);
  await pipeline(Readable.fromWeb(res.body), createWriteStream(dest));
  return dest;
}

export async function verifySha256(file, expected) {
  const hash = createHash("sha256");
  hash.update(await readFile(file));
  return hash.digest("hex") === String(expected).trim().toLowerCase();
}

export function parseSha256File(text) {
  const m = String(text).trim().match(/^([0-9a-fA-F]{64})/);
  if (!m) throw new Error("sha256 文件格式不正确");
  return m[1].toLowerCase();
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `node --test npm/test/download.test.mjs`
Expected: `# pass 5`、`# fail 0`

- [ ] **Step 5: 提交**

```bash
git add npm/lib/download.mjs npm/test/download.test.mjs
git commit -m "feat(npm): 下载与 sha256 校验工具"
```

---

## Task 2: 启动器与包模板

**Files:**
- Create: `npm/bin/cli.mjs`
- Create: `npm/package.json.tmpl`

- [ ] **Step 1: 写 cli.mjs**

```js
#!/usr/bin/env node
// termux-dsh 启动器：把参数透传给解压后的运行时 bin.js。
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const runtimeBin = join(here, "..", "runtime", "lib", "bin.js");

if (!existsSync(runtimeBin)) {
  console.error("termux-dsh: runtime 未安装，请重跑 `npm rebuild -g termux-dsh` 或重新安装。");
  process.exit(1);
}

const child = spawn(process.execPath, [runtimeBin, ...process.argv.slice(2)], {
  stdio: "inherit",
  env: process.env,
});
child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});
```

- [ ] **Step 2: 写 package.json.tmpl**

```json
{
  "name": "termux-dsh",
  "version": "__VERSION__",
  "description": "Termux/Android arm64 repack of dsh: installs the prebuilt runtime from GitHub Releases",
  "license": "MIT",
  "type": "module",
  "bin": {
    "dsh": "bin/cli.mjs",
    "termux-dsh": "bin/cli.mjs"
  },
  "scripts": {
    "postinstall": "node bin/install.mjs"
  },
  "files": [
    "bin/",
    "lib/",
    "share/"
  ],
  "engines": {
    "node": ">=24.9.0"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/Starsky16/termux-dsh.git"
  },
  "bugs": {
    "url": "https://github.com/Starsky16/termux-dsh/issues"
  },
  "homepage": "https://github.com/Starsky16/termux-dsh#readme",
  "keywords": ["dsh", "termux", "android", "arm64", "deepseek-harness"]
}
```

- [ ] **Step 3: 语法检查**

Run: `node --check npm/bin/cli.mjs`
Expected: 无输出（exit 0）

- [ ] **Step 4: 提交**

```bash
git add npm/bin/cli.mjs npm/package.json.tmpl
git commit -m "feat(npm): 启动器与包模板"
```

---

## Task 3: 安装脚本与 setup 辅助

**Files:**
- Create: `npm/lib/setup.mjs`
- Create: `npm/bin/install.mjs`

- [ ] **Step 1: 写 setup.mjs**

```js
// npm/lib/setup.mjs
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/** 把 npm 生成的 bin shim 首行换成当前 node，Termux 没有 /usr/bin/env。 */
export function fixBinShebang(binDir, names = ["dsh", "termux-dsh"]) {
  for (const name of names) {
    const file = join(binDir, name);
    if (!existsSync(file)) continue;
    const text = readFileSync(file, "utf8");
    if (!text.startsWith("#!")) continue;
    const nl = text.indexOf("\n");
    const body = nl === -1 ? "" : text.slice(nl + 1);
    writeFileSync(file, `#!${process.execPath}\n${body}`);
    chmodSync(file, 0o755);
  }
}

/** 依次执行 share/profile 下的初始化脚本；任一失败只告警。 */
export function runProfileSetup(shareDir) {
  const scripts = ["setup-env.sh", "apply-overrides.sh", "setup-selfcheck.sh"];
  for (const name of scripts) {
    const script = join(shareDir, "profile", name);
    if (!existsSync(script)) continue;
    try {
      execFileSync("bash", [script], { stdio: "inherit", env: process.env });
    } catch (error) {
      console.warn(`termux-dsh: ${name} 失败（可稍后跑 dsh-termux-setup 重试）：${error.message}`);
    }
  }
}

/** 装了 dsh-compat 就 best-effort 重打 L2。 */
export function repatchL2(runtimeDir) {
  const patch = join(process.env.HOME || "", "code", "dsh-compat", "bin", "patch.mjs");
  if (!existsSync(patch)) return;
  try {
    execFileSync(process.execPath, [patch, "--apply", "--node-modules", join(runtimeDir, "node_modules")], {
      stdio: "inherit",
    });
  } catch (error) {
    console.warn(`termux-dsh: L2 重打失败（可手动跑 dsh-compat patch.mjs --apply）：${error.message}`);
  }
}

/** 返回全局 bin 目录（Termux 是 $PREFIX/bin）。 */
export function globalBinDir() {
  if (process.env.PREFIX) return join(process.env.PREFIX, "bin");
  try {
    const prefix = execFileSync("npm", ["prefix", "-g"], { encoding: "utf8" }).trim();
    return join(prefix, "bin");
  } catch {
    return null;
  }
}
```

- [ ] **Step 2: 写 install.mjs**

```js
#!/usr/bin/env node
// npm postinstall：下载并解压对应 Release 的运行时。
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { download, parseSha256File, releaseUrl, verifySha256 } from "../lib/download.mjs";
import { fixBinShebang, globalBinDir, repatchL2, runProfileSetup } from "../lib/setup.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const pkgRoot = join(here, "..");
const pkg = JSON.parse(readFileSync(join(pkgRoot, "package.json"), "utf8"));
const runtimeDir = join(pkgRoot, "runtime");

const skipPlatform = process.env.TDSH_NPM_SKIP_PLATFORM_CHECK === "1";
if (!skipPlatform) {
  if (process.platform !== "android" || process.arch !== "arm64") {
    console.error(
      `termux-dsh 只支持 Termux/Android arm64（当前 ${process.platform}-${process.arch}）。\n` +
        `请改用 GitHub Release 的 .deb 或 bootstrap.sh。`
    );
    process.exit(1);
  }
}

const version = pkg.version;
const tgzName = "dsh-termux.tgz";
const shaName = "dsh-termux.tgz.sha256";

async function main() {
  const work = await mkdtemp(join(tmpdir(), "termux-dsh-npm-"));
  const tgz = join(work, tgzName);
  const shaFile = join(work, shaName);
  try {
    console.log(`termux-dsh: 下载 ${version} 运行时（约 133 MB）…`);
    await download(releaseUrl(version, tgzName), tgz);
    await download(releaseUrl(version, shaName), shaFile);
    const expected = parseSha256File(readFileSync(shaFile, "utf8"));
    if (!(await verifySha256(tgz, expected))) {
      throw new Error("sha256 校验失败，拒绝安装");
    }

    rmSync(runtimeDir, { recursive: true, force: true });
    mkdirSync(runtimeDir, { recursive: true });
    execFileSync("tar", ["-xzf", tgz, "-C", runtimeDir, "--strip-components=1"], { stdio: "inherit" });
    if (!existsSync(join(runtimeDir, "lib", "bin.js"))) {
      throw new Error("解压后缺少 lib/bin.js，运行时包不完整");
    }

    const binDir = globalBinDir();
    if (binDir) fixBinShebang(binDir);
    runProfileSetup(join(pkgRoot, "share"));
    repatchL2(runtimeDir);
    console.log(`termux-dsh: 安装完成（${version}）。`);
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(`termux-dsh: 安装失败：${error.message}`);
  rmSync(runtimeDir, { recursive: true, force: true });
  console.error("可改用 bootstrap.sh 或 GitHub Release 的 .deb 安装。");
  process.exit(1);
});
```

- [ ] **Step 3: 语法检查**

Run: `node --check npm/lib/setup.mjs && node --check npm/bin/install.mjs`
Expected: 无输出（exit 0）

- [ ] **Step 4: 提交**

```bash
git add npm/lib/setup.mjs npm/bin/install.mjs
git commit -m "feat(npm): postinstall 下载解压与 profile 初始化"
```

---

## Task 4: 打包脚本 make-package.mjs

**Files:**
- Create: `npm/make-package.mjs`

- [ ] **Step 1: 写脚本**

```js
#!/usr/bin/env node
// 生成 dist/npm/（可 npm pack/publish 的 bootstrapper 包）。
// 用法：node npm/make-package.mjs <dist-dir> <version>
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, "..");
const outDir = join(process.cwd(), process.argv[2] || "dist/npm");
const version = process.argv[3];
if (!version) {
  console.error("用法：node npm/make-package.mjs <dist-dir> <version>");
  process.exit(1);
}

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

const tmpl = readFileSync(join(here, "package.json.tmpl"), "utf8");
const pkg = JSON.parse(tmpl.replaceAll("__VERSION__", version));
writeFileSync(join(outDir, "package.json"), JSON.stringify(pkg, null, 2) + "\n");

for (const dir of ["bin", "lib"]) {
  cpSync(join(here, dir), join(outDir, dir), { recursive: true });
}

// share/ 与 deb 的 $PREFIX/share/dsh-termux 同构
const share = join(outDir, "share");
mkdirSync(share, { recursive: true });
for (const item of ["lib", "profile", "patches", "verify.sh"]) {
  const src = join(repoRoot, item);
  if (!existsSync(src)) throw new Error(`缺 ${item}`);
  cpSync(src, join(share, item), { recursive: true });
}
mkdirSync(join(share, "docs"), { recursive: true });
cpSync(join(repoRoot, "docs", "verify-checklist.md"), join(share, "docs", "verify-checklist.md"));

console.log(`npm 包已生成：${outDir}（version ${version}）`);
```

- [ ] **Step 2: 本地生成并检查**

Run:
```bash
node npm/make-package.mjs dist/npm 0.2.2-rc.1-tdsh.1
node -e 'const p=require("./dist/npm/package.json"); console.log(p.name, p.version, JSON.stringify(p.bin))'
du -sh dist/npm
```
Expected: 输出 `termux-dsh 0.2.2-rc.1-tdsh.1 {"dsh":"bin/cli.mjs","termux-dsh":"bin/cli.mjs"}`，体积 < 1 MB

- [ ] **Step 3: 检查 npm pack 清单**

Run: `cd dist/npm && npm pack --dry-run 2>&1 | tail -20`
Expected: 文件清单含 `bin/`、`lib/`、`share/`、`package.json`，**不含** `runtime/`

- [ ] **Step 4: 提交**

```bash
git add npm/make-package.mjs
git commit -m "feat(npm): 生成 bootstrapper 发布包"
```

---

## Task 5: 本地端到端演练（跳过平台检查）

**Files:** 无新增（验证 Task 1–4）

- [ ] **Step 1: 生成包并模拟安装**

Run:
```bash
cd ~/code/termux-dsh
node npm/make-package.mjs dist/npm 0.2.2-rc.1-tdsh.1
REPO="$PWD"
TMPD="$(mktemp -d)"
cd "$TMPD" && npm init -y >/dev/null 2>&1
npm i "file:$REPO/dist/npm" 2>&1 | tail -5
node node_modules/termux-dsh/bin/install.mjs 2>&1 | tail -5
ls -d node_modules/termux-dsh/runtime/lib/bin.js && echo RUNTIME_OK
```
Expected: npm 12 会拦 postinstall（正常），手动执行 install 后出现 `安装完成` 与 `RUNTIME_OK`。

> 实测补充：`file:` 安装是软链，要验证真实安装请用 `npm pack` 出的 tgz；
> 且 npm 12 的 `.bin` 是 symlink，需 `termux-fix-shebang` 或由 cli 兜底下载。

- [ ] **Step 2: 验证 bin 与版本**

Run:
```bash
cd "$TMPD" && ./node_modules/.bin/termux-dsh --version
```
Expected: 输出 `0.2.2-rc.1-tdsh.1`（若 shim 已修好）

- [ ] **Step 3: 清理**

Run: `rm -rf "$TMPD"`

- [ ] **Step 4: 记录结果**

在 `docs/verify-checklist.md` 末尾追加一行：

```markdown
- npm 包端到端（本地/CI）：`TDSH_NPM_SKIP_PLATFORM_CHECK=1 npm i file:dist/npm` → runtime 就位、`termux-dsh --version` 正常。
```

- [ ] **Step 5: 提交**

```bash
git add docs/verify-checklist.md
git commit -m "docs: 记录 npm 包端到端验证方式"
```

---

## Task 6: CI 集成

**Files:**
- Modify: `.github/workflows/repack.yml`

- [ ] **Step 1: 加 `id-token: write` 权限**

把现有：

```yaml
permissions:
  contents: write
```

改为：

```yaml
permissions:
  contents: write
  id-token: write
```

- [ ] **Step 2: 在 `Publish release` 之后加 npm 构建与发布步骤**

```yaml
      - name: Build npm package
        run: |
          node npm/make-package.mjs dist/npm "$(cat dist/version.txt)"
          ( cd dist/npm && npm pack --dry-run >/dev/null )

      - name: Publish to npm
        # 配置 Trusted Publishing 后把仓库变量 NPM_PUBLISH_ENABLED 置为 true 才发布
        if: ${{ inputs.dry_run != true && vars.NPM_PUBLISH_ENABLED == 'true' }}
        env:
          NPM_CONFIG_PROVENANCE: "true"
        run: |
          npm install -g npm@latest >/dev/null 2>&1 || true
          npm --version
          V=$(cat dist/version.txt)
          if [ "${GITHUB_REF_NAME}" = "main" ]; then
            npm publish dist/npm --tag latest --provenance
          else
            npm publish dist/npm --tag next --provenance
          fi
          echo "published termux-dsh@$V to npm"
```

- [ ] **Step 3: YAML 校验**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/repack.yml')); print('YAML OK')"`
Expected: `YAML OK`

- [ ] **Step 4: 提交**

```bash
git add .github/workflows/repack.yml
git commit -m "ci(npm): 构建并以 Trusted Publishing 发布 termux-dsh"
```

---

## Task 7: 文档

**Files:**
- Modify: `README.md`
- Modify: `INSTALL.md`
- Modify: `CHANGELOG.md`
- Modify: `CONTRIBUTING.md`

- [ ] **Step 1: README 增加 npm 安装方式**

在「方式一：一条命令」之前加：

```markdown
**方式零：npm（推荐给习惯 npm 的用户）**

```bash
npm i -g termux-dsh
dsh --version
```

npm 包只是安装器：首次安装会从 GitHub Release 下载约 133 MB 运行时并校验 sha256。
dev 构建用 `npm i -g termux-dsh@next`。非 Termux/arm64 环境会拒绝安装。
```

- [ ] **Step 2: INSTALL 补 npm 路径**

在分步等价操作里加一节：

```markdown
## npm 安装

```bash
npm i -g termux-dsh
```

镜像/代理：`TDSH_RELEASE_BASE=https://<镜像>/releases/download npm i -g termux-dsh`。
```

- [ ] **Step 3: CHANGELOG 增加 Added 条目**

在 `[0.2.2-rc.1-tdsh.1]` 的 `### Changed` 之前加：

```markdown
### Added

- npm 分发：`npm i -g termux-dsh` 安装器包（bootstrapper，运行时按版本从 Release 下载并校验），
  CI 用 Trusted Publishing（OIDC）发布，不保存长期 token；`latest` ← main、`next` ← dev。
```

- [ ] **Step 4: CONTRIBUTING 记录发布通道**

在「Release 流程」第 4 条后追加：

```markdown
5. npm 发布在 Release 之后执行：`main` → `latest`，其它分支 → `next`；凭据走 OIDC
   （Trusted Publishing），失败会让 job 失败但已发的 Release 不回收。改 workflow 文件名
   需同步更新 npm 包设置里的 trusted publisher 配置。
```

- [ ] **Step 5: 提交**

```bash
git add README.md INSTALL.md CHANGELOG.md CONTRIBUTING.md
git commit -m "docs: npm 安装方式与发布说明"
```

---

## Task 8: 首次发布引导（人工，一次性）

**Files:** 无

- [ ] **Step 1: 本地生成真版本包**

```bash
cd ~/code/termux-dsh
node npm/make-package.mjs dist/npm 0.2.2-rc.1-tdsh.1
( cd dist/npm && npm pack )
```

- [ ] **Step 2: 本地发布（交互 2FA）**

```bash
npm publish dist/npm --tag latest --access public
```

Expected: 输出 `+ termux-dsh@0.2.2-rc.1-tdsh.1`

- [ ] **Step 3: 配置 Trusted Publishing**

npmjs.com → `termux-dsh` → Settings → Trusted publishing：

- Repository：`Starsky16/termux-dsh`
- Workflow filename：`repack.yml`
- Environment：留空

- [ ] **Step 4: 48 小时内激活**

触发一次 dev 构建（版本不同，不会撞版本）：

```bash
gh workflow run repack.yml --ref dev -f upstream_version=0.2.2-rc.1 -f dry_run=false
```

Expected: job 成功；`npm view termux-dsh dist-tags` 出现 `next`

- [ ] **Step 5: 真机验证**

```bash
npm i -g termux-dsh
dsh --version
DSH_PKG="$PREFIX/lib/node_modules/termux-dsh/runtime" bash "$PREFIX/lib/node_modules/termux-dsh/share/verify.sh"
```

Expected: 版本正确、verify 全 PASS

---

## 自查

- 规格覆盖：包结构/安装流程（Task 1–4）、CI（Task 6）、文档（Task 7）、首次引导（Task 8）、验证（Task 5 + 8）
- 无占位符：每个代码步骤含完整代码
- 命名一致：`releaseUrl`/`verifySha256`/`parseSha256File`/`fixBinShebang`/`runProfileSetup`/`repatchL2`/`globalBinDir` 全程一致
