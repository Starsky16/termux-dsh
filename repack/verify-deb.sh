#!/usr/bin/env bash
# Verify the optional Termux .deb layout and metadata.
# Usage: verify-deb.sh <deb> <version> [arch]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

DEB="${1:?用法：verify-deb.sh <deb> <version> [arch]}"
VER="${2:?}"
ARCH="${3:-aarch64}"
[[ -f "$DEB" ]] || die "缺 .deb：$DEB"
have dpkg-deb || die "缺 dpkg-deb"

PREFIX=/data/data/com.termux/files/usr
fail=0
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }
check_file() { [[ -f "$1" ]] && pass "exists $2" || bad "missing $2"; }
check_exec() { [[ -x "$1" ]] && pass "executable $2" || bad "not executable $2"; }

GOT_PKG="$(dpkg-deb -f "$DEB" Package)"
GOT_VER="$(dpkg-deb -f "$DEB" Version)"
GOT_ARCH="$(dpkg-deb -f "$DEB" Architecture)"
[[ "$GOT_PKG" == "dsh-termux" ]] && pass "package dsh-termux" || bad "package: $GOT_PKG"
[[ "$GOT_VER" == "$VER" ]] && pass "version $VER" || bad "version: $GOT_VER != $VER"
[[ "$GOT_ARCH" == "$ARCH" ]] && pass "arch $ARCH" || bad "arch: $GOT_ARCH != $ARCH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
dpkg-deb -x "$DEB" "$TMP"

RUNTIME="$TMP$PREFIX/lib/node_modules/dsh-termux"
check_file "$RUNTIME/package.json" "runtime package.json"
check_file "$RUNTIME/lib/bin.js" "runtime bin.js"
check_exec "$TMP$PREFIX/bin/dsh" "dsh launcher"
check_exec "$TMP$PREFIX/bin/dsh-termux-setup" "dsh-termux-setup"
check_file "$TMP$PREFIX/share/dsh-termux/profile/setup-selfcheck.sh" "setup-selfcheck"
check_file "$TMP$PREFIX/share/dsh-termux/patches/manifest.json" "patches manifest"

if [[ -f "$RUNTIME/package.json" ]]; then
  GOT_RUNTIME_VER="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).version)' "$RUNTIME/package.json")"
  [[ "$GOT_RUNTIME_VER" == "$VER" ]] && pass "runtime version" || bad "runtime version: $GOT_RUNTIME_VER"
fi

check_no_libcxx() {
  local file="$1" label="$2"
  if ! command -v readelf >/dev/null 2>&1; then return 0; fi
  if readelf -d "$file" 2>/dev/null | grep -q 'libc++_shared'; then bad "$label links libc++_shared"; else pass "$label static libc++"; fi
}
KOFFI="$RUNTIME/node_modules/koffi/build/koffi/android_arm64/koffi.node"
PTY="$RUNTIME/node_modules/node-pty/prebuilds/android-arm64/pty.node"
RB="$RUNTIME/node_modules/node-addon-require-builtin/build/nodeabi/node-v$(node -p 'process.versions.modules')-android-arm64/require_builtin.node"
check_file "$KOFFI" "koffi"
check_file "$PTY" "node-pty"
check_file "$RB" "require-builtin"
check_no_libcxx "$KOFFI" "koffi"
check_no_libcxx "$PTY" "node-pty"
check_no_libcxx "$RB" "require-builtin"

[[ "$fail" -eq 0 ]] || die ".deb 校验失败"
info "完成：$DEB ($(du -h "$DEB" | cut -f1))"
