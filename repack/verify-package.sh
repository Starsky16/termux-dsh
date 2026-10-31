#!/usr/bin/env bash
# Hard checks on the produced Termux tarball. Any failure is fatal: the CI
# publish step only runs when repack.sh (which calls this) exits 0.
#
# Usage: verify-package.sh <dist/dsh-termux.tgz> [version]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

TGZ="${1:?用法：verify-package.sh <tgz> [version]}"
[[ -f "$TGZ" ]] || die "缺 tarball：$TGZ"
VER="${2:-$(cat "$(dirname "$TGZ")/version.txt" 2>/dev/null || true)}"
[[ -n "$VER" ]] || die "缺版本号（version.txt 或第二参数）"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$TGZ" -C "$TMP"
PKG="$TMP/package"
[[ -d "$PKG" ]] || die "tarball 缺 package/ 根目录"

fail=0
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }

check_file() { [[ -f "$1" ]] && pass "exists $2" || bad "missing $2 ($1)"; }
check_grep() {
  local file="$1" pat="$2" label="$3"
  if [[ -f "$file" ]] && grep -q -- "$pat" "$file"; then pass "$label"; else bad "$label"; fi
}
check_elf() {
  local file="$1" label="$2"
  if [[ -f "$file" ]] && file "$file" | grep -q 'ARM aarch64'; then pass "$label"; else bad "$label ($(file "$file" 2>/dev/null || echo missing))"; fi
}
check_no_libcxx() {
  local file="$1" label="$2"
  if ! command -v readelf >/dev/null 2>&1; then
    skip "$label (no readelf)"
    return
  fi
  if readelf -d "$file" 2>/dev/null | grep -q 'libc++_shared'; then
    bad "$label links libc++_shared (Termux has no such library)"
  else
    pass "$label static libc++"
  fi
}

# Identity
jsonval() {
  node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const v=process.argv[2].split(".").reduce((o,k)=>o==null?o:o[k],p);process.stdout.write(v==null?"":String(v))' "$1" "$2"
}
NAME="$(jsonval "$PKG/package.json" name)"
GOT_VER="$(jsonval "$PKG/package.json" version)"
[[ "$NAME" == "dsh-termux" ]] && pass "package name dsh-termux" || bad "package name: $NAME"
[[ "$GOT_VER" == "$VER" ]] && pass "package version $VER" || bad "package version: $GOT_VER != $VER"
[[ "$(jsonval "$PKG/package.json" bin.dsh)" == "lib/bin.js" ]] \
  && pass "bin.dsh -> lib/bin.js" || bad "bin.dsh 缺失或不为 lib/bin.js"
[[ ! -e "$PKG/node_modules/@deepseek-ai/dsh" ]] \
  && pass "bundled runtime excludes @deepseek-ai/dsh" || bad "tarball 内仍有 @deepseek-ai/dsh"

# Native payloads
KOFFI="$PKG/node_modules/koffi/build/koffi/android_arm64/koffi.node"
PTY="$PKG/node_modules/node-pty/prebuilds/android-arm64/pty.node"
NODE_ABI="$(node -p 'process.versions.modules')"
RB="$PKG/node_modules/node-addon-require-builtin/build/nodeabi/node-v$NODE_ABI-android-arm64/require_builtin.node"
check_file "$KOFFI" "koffi android-arm64 binary"
check_file "$PTY" "node-pty android-arm64 prebuild"
check_file "$RB" "require-builtin android-arm64 binary"
check_elf "$KOFFI" "koffi is ARM aarch64"
check_elf "$PTY" "node-pty is ARM aarch64"
check_elf "$RB" "require-builtin is ARM aarch64"
check_no_libcxx "$KOFFI" "koffi"
check_no_libcxx "$PTY" "node-pty"
check_no_libcxx "$RB" "require-builtin"

# A-class patch markers (these are the reasons the package is Termux-specific)
check_grep "$PKG/node_modules/@vscode/ripgrep/lib/index.js" 'systemRipgrep' "A1 ripgrep fallback"
check_grep "$PKG/node_modules/@deepseek-ai/dsh-fs-local/lib/index.js" 'HARD_LINK_UNAVAILABLE' "A2 fs link fallback"
check_grep "$PKG/node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js" 'TERMUX PATCH' "A3 attachment durability"
check_grep "$PKG/node_modules/@deepseek-ai/dsh-spill-local/lib/index.js" 'writableByMe' "A4 spill ancestor rule"
check_grep "$PKG/node_modules/@deepseek-ai/dsh-sandbox-local/lib/index.js" 'allowUnconfinedFallback' "A5 sandbox fallback"
check_grep "$PKG/node_modules/@deepseek-ai/dsh-web-fetch-http/lib/index.js" 'allowBenchmarkAddresses' "A6 web-fetch benchmark range"
check_grep "$PKG/node_modules/@deepseek-ai/node-addon-system/lib/flock.js" 'softTryLockExclusive' "A7 flock softlock"
check_file "$PKG/node_modules/@deepseek-ai/node-addon-system/lib/softlock.js" "A7 softlock file"

# B5: session publication must use rename on Android.
check_grep "$PKG/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js" 'process.platform === "android"' "B5 session android publish"
check_grep "$PKG/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js" 'rename(tmp, finalPath)' "B5 rename call"

# B10: `dsh --version` must report the repack version, not the upstream
# dsh-app-boot version. The unpacked package root is dsh-termux.
check_grep "$PKG/lib/bin.js" 'manifest.name === "dsh-termux"' "B10 CLI version"

# No host binaries may ride along (they would make the tarball look valid while
# failing at runtime on the phone).
if find "$PKG/node_modules" -path '*koffi/build/koffi/linux_*' -o -path '*node-pty/prebuilds/linux-*' -o -path '*@esbuild/linux-*' | grep -q .; then
  bad "tarball 含 host 平台二进制"
else
  pass "no host-platform native binaries"
fi

if [[ "$fail" -ne 0 ]]; then
  echo
  die "产物校验失败（$TGZ）"
fi
echo
info "产物校验全部通过：$TGZ ($VER)"
