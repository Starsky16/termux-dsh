import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/** 把 npm 生成的 bin shim 首行换成当前 node，Termux 没有 /usr/bin/env。
 *  只处理 `#!/usr/bin/env node` 的 shim，绝不碰 deb 装的 bash 启动器。 */
export function fixBinShebang(binDir, names = ["dsh", "termux-dsh"]) {
  for (const name of names) {
    const file = join(binDir, name);
    if (!existsSync(file)) continue;
    const text = readFileSync(file, "utf8");
    if (!text.startsWith("#!/usr/bin/env node")) continue;
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
