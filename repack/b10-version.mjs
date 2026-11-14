#!/usr/bin/env node
// B10：让 `dsh --version` 显示 <upstream>-tdsh.<rev>。
//
// 上游 0.2.2-rc.2 起把 CLI 拆成 lib/bin.js（re-export 壳）+ lib/bin-<hash>.js
// （真正逻辑）。hash 文件名随每次构建变化，patch 锚点不可持续，所以改用
// 构建期脚本替换：扫描 bin chunk，把版本读取改成优先读包根 package.json。
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const pkgDir = process.argv[2];
if (!pkgDir) {
  console.error("用法：node b10-version.mjs <dsh-package-dir>");
  process.exit(1);
}

const ANCHOR = "const version = getDshRuntimeVersion();";
const REPLACEMENT = `const version = (() => {
	try {
		const manifest = JSON.parse(__tdshReadFileSync(new URL("../package.json", import.meta.url), "utf8"));
		if (manifest.name === "dsh-termux" && manifest.tdsh?.upstream && typeof manifest.version === "string") return manifest.version;
	} catch {}
	return getDshRuntimeVersion();
})();`;

const IMPORTS = 'import { join } from "node:path";';
const IMPORTS_PATCHED = `${IMPORTS}\nimport { readFileSync as __tdshReadFileSync } from "node:fs";`;

const libDir = join(pkgDir, "lib");
const candidates = readdirSync(libDir).filter((f) => /^bin(-.*)?\.js$/.test(f));
let changed = 0;

for (const name of candidates) {
  const full = join(libDir, name);
  let text = readFileSync(full, "utf8");
  if (!text.includes(ANCHOR)) continue;
  if (!text.includes("__tdshReadFileSync")) {
    if (!text.includes(IMPORTS)) {
      console.error(`B10：${name} 缺少预期的 import 锚点，上游结构又变了`);
      process.exit(1);
    }
    text = text.replace(IMPORTS, IMPORTS_PATCHED);
  }
  text = text.replace(ANCHOR, REPLACEMENT);
  writeFileSync(full, text);
  changed += 1;
  console.log(`B10：已处理 ${name}`);
}

if (changed === 0) {
  console.error("B10：没有找到版本读取锚点，上游结构可能又变了");
  process.exit(1);
}
console.log(`B10：共替换 ${changed} 个文件`);
