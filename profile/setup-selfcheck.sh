#!/data/data/com.termux/files/usr/bin/bash
# Install the ~/bin/dsh wrapper for the dsh-compat L2 self-check.
#
# The wrapper is PATH-first and survives `npm i -g dsh-termux` upgrades; it
# runs selfcheck (if dsh-compat is present) and then execs the real dsh.
# It replaces the old ~/.zshenv shell-function variant (which setsid/nohup
# bypassed) and removes that block after backing up .zshenv.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

ZSHRC="${ZSHRC:-$HOME/.zshenv}"
BIN="${TDSH_BIN_DIR:-$HOME/bin}"
WRAPPER="$BIN/dsh"
LEGACY_MARK="# >>> termux-dsh selfcheck >>>"
WRAPPER_MARK="# termux-dsh selfcheck wrapper"
REAL="${TDSH_REAL_DSH:-${PREFIX:-/data/data/com.termux/files/usr}/bin/dsh}"

[[ -x "$REAL" ]] || die "找不到真实 dsh：$REAL（先完成 bootstrap 安装）"
mkdir -p "$BIN"

# Drop the old shell-function block first: keeping it would run selfcheck twice.
if [[ -f "$ZSHRC" ]] && grep -qF "$LEGACY_MARK" "$ZSHRC"; then
  cp -p "$ZSHRC" "$ZSHRC.bak-selfcheck-$(date +%s)"
  sed -i '/^# >>> termux-dsh selfcheck >>>$/,/^# <<< termux-dsh selfcheck <<<$/d' "$ZSHRC"
  info "已移除旧 .zshenv 自检块（备份 $ZSHRC.bak-selfcheck-*）"
fi

if [[ -e "$WRAPPER" ]] && ! grep -qF "$WRAPPER_MARK" "$WRAPPER" 2>/dev/null; then
  mv "$WRAPPER" "$WRAPPER.bak-$(date +%s)"
  warn "已备份原有 $WRAPPER"
fi

tmp="$(mktemp "$BIN/.dsh.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# termux-dsh selfcheck wrapper (remove this file to undo)
if [ -z "${DSH_COMPAT_NM:-}" ]; then
  DSH_COMPAT_NM="$(npm root -g 2>/dev/null)/dsh-termux/node_modules"
  export DSH_COMPAT_NM
fi
if [ -f "$HOME/code/dsh-compat/bin/selfcheck.mjs" ] && [ -d "$DSH_COMPAT_NM" ]; then
  node "$HOME/code/dsh-compat/bin/selfcheck.mjs" --node-modules "$DSH_COMPAT_NM" >&2 || true
fi
exec "${TDSH_REAL_DSH:-${PREFIX:-/data/data/com.termux/files/usr}/bin/dsh}" "$@"
EOF
chmod 755 "$tmp"
mv "$tmp" "$WRAPPER"
trap - EXIT
info "已写入 dsh wrapper：$WRAPPER → $REAL"
