#!/usr/bin/env bash
# Assemble the optional Termux .deb from the already-built dsh-termux tree.
#
# Layout (Termux prefix is fixed):
#   $PREFIX/lib/node_modules/dsh-termux/   full runtime tree
#   $PREFIX/bin/dsh                        launcher (node lib/bin.js)
#   $PREFIX/bin/dsh-termux-setup           re-run env/profile setup
#   $PREFIX/share/dsh-termux/              lib/profile/patches scripts
#
# Usage: deb.sh <package-dir> <dist-dir> <version> <repo-root>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

PKGDIR="${1:?用法：deb.sh <package-dir> <dist-dir> <version> <repo-root>}"
DIST="${2:?}"
VER="${3:?}"
ROOT="${4:?}"
PREFIX="${TDSH_DEB_PREFIX:-/data/data/com.termux/files/usr}"
ARCH="${TDSH_DEB_ARCH:-aarch64}"
DEB="$DIST/dsh-termux_${VER}_${ARCH}.deb"

[[ -f "$PKGDIR/package.json" ]] || die "缺 package 树：$PKGDIR"
if [[ "${TDSH_DEB_STAGE_ONLY:-0}" != "1" ]]; then
  have dpkg-deb || die "缺 dpkg-deb（Ubuntu runner 自带；本地构建可跳过）"
fi

DEBROOT="$(mktemp -d "$DIST/.debroot.XXXXXX")"
trap 'rm -rf "$DEBROOT"' EXIT

RUNTIME="$DEBROOT$PREFIX/lib/node_modules/dsh-termux"
mkdir -p "$RUNTIME"
cp -a "$PKGDIR/." "$RUNTIME/"

BIN="$DEBROOT$PREFIX/bin"
mkdir -p "$BIN"
cat >"$BIN/dsh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# Installed by dsh-termux.deb. Replaces the npm bin shim on Termux.
exec "\${TDSH_NODE:-node}" "$PREFIX/lib/node_modules/dsh-termux/lib/bin.js" "\$@"
EOF
chmod 755 "$BIN/dsh"

SHARE="$DEBROOT$PREFIX/share/dsh-termux"
mkdir -p "$SHARE"
cp -a "$ROOT/lib" "$ROOT/profile" "$ROOT/patches" "$ROOT/docs" "$ROOT/verify.sh" "$SHARE/"

cat >"$BIN/dsh-termux-setup" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# Re-apply Termux env/profile/selfcheck after an upgrade or profile reset.
set -euo pipefail
export PREFIX="$PREFIX"
for s in setup-env apply-overrides setup-selfcheck; do
  bash "$PREFIX/share/dsh-termux/profile/\$s.sh"
done
EOF
chmod 755 "$BIN/dsh-termux-setup"

cat >"$BIN/dsh-termux-verify" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# Run the same verify.sh that bootstrap uses (package runtime tree).
exec bash "$PREFIX/share/dsh-termux/verify.sh"
EOF
chmod 755 "$BIN/dsh-termux-verify"

DEBIAN="$DEBROOT/DEBIAN"
mkdir -p "$DEBIAN"
chmod 755 "$DEBROOT" "$DEBIAN"
cat >"$DEBIAN/control" <<EOF
Package: dsh-termux
Version: $VER
Architecture: $ARCH
Maintainer: Starsky16 <Starsky16@users.noreply.github.com>
Depends: bash, nodejs-lts (>= 24.2), ripgrep, coreutils, patch
Section: utils
Priority: optional
Installed-Size: $(du -sk "$DEBROOT" | awk '{print $1}')
Description: dsh for Termux/Android arm64 (repack)
 Complete android-arm64 runtime of dsh, including koffi, node-pty and
 node-addon-require-builtin, plus Termux host/profile setup.
EOF

cat >"$DEBIAN/postinst" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Best-effort first-run setup. Never fail dpkg configuration because the user
# has no writable HOME or has not installed dsh-compat yet.
set -u
PREFIX=/data/data/com.termux/files/usr
export PREFIX
SHARE="$PREFIX/share/dsh-termux"
if [ -n "${HOME:-}" ] && [ -d "$SHARE/profile" ]; then
  bash "$SHARE/profile/setup-env.sh" || echo "dsh-termux: setup-env failed (rerun dsh-termux-setup)" >&2
  bash "$SHARE/profile/apply-overrides.sh" || echo "dsh-termux: apply-overrides failed (rerun dsh-termux-setup)" >&2
  bash "$SHARE/profile/setup-selfcheck.sh" || echo "dsh-termux: selfcheck setup skipped" >&2
fi
# deb 内的 @deepseek-ai/* 是 pristine：装/升级会冲掉 dsh-compat 的 L2 补丁。
# 若 dsh-compat 已 clone 就 best-effort 重打；失败只告警（后续由 ~/bin/dsh
# wrapper 的启动自检兜底提示），绝不阻塞 dpkg。
if [ -n "${HOME:-}" ] && [ -f "$HOME/code/dsh-compat/bin/patch.mjs" ]; then
  NM="$PREFIX/lib/node_modules/dsh-termux/node_modules"
  node "$HOME/code/dsh-compat/bin/patch.mjs" --apply --node-modules "$NM" \
    || echo "dsh-termux: L2 repatch failed (run: node ~/code/dsh-compat/bin/patch.mjs --apply --node-modules $NM)" >&2
fi
echo "dsh-termux installed. Start with: dsh web"
exit 0
EOF
chmod 755 "$DEBIAN/postinst"

cat >"$DEBIAN/postrm" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Remove only the wrapper this package created; leave ~/.dsh and .zshenv alone.
set -u
if [ "${1:-}" = "remove" ] || [ "${1:-}" = "purge" ]; then
  if [ -n "${HOME:-}" ] && [ -f "$HOME/bin/dsh" ] \
    && grep -qF 'termux-dsh selfcheck wrapper' "$HOME/bin/dsh" 2>/dev/null; then
    rm -f "$HOME/bin/dsh"
  fi
fi
exit 0
EOF
chmod 755 "$DEBIAN/postrm"

if [[ "${TDSH_DEB_STAGE_ONLY:-0}" == "1" ]]; then
  info "仅暂存（TDSH_DEB_STAGE_ONLY=1）：$DEBROOT"
  trap - EXIT
  exit 0
fi

rm -f "$DEB"
dpkg-deb --build --root-owner-group "$DEBROOT" "$DEB" >/dev/null
[[ -s "$DEB" ]] || die ".deb 为空：$DEB"
sha256sum "$DEB" | awk '{print $1"  dsh-termux.deb"}' > "$DIST/dsh-termux.deb.sha256"
info "完成：$DEB ($(du -h "$DEB" | cut -f1))"
