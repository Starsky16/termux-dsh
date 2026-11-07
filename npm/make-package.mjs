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
