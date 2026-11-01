#!/data/data/com.termux/files/usr/bin/bash
# Idempotently add the dsh-compat L2 self-check wrapper to ~/.zshenv.
# Only appends once; removing the marked block is safe. Warning-only: never
# blocks or repairs the installed tree.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

ZSHRC="${ZSHRC:-$HOME/.zshenv}"
MARK="# >>> termux-dsh selfcheck >>>"
touch "$ZSHRC"
if grep -qF "$MARK" "$ZSHRC"; then
  info "自检块已存在：$ZSHRC"
  exit 0
fi
cat >>"$ZSHRC" <<'EOF'

# >>> termux-dsh selfcheck >>>
# Added by termux-dsh; remove this block to undo.
# L2 补丁启动自检：只告警、不阻塞。实现见 dsh-compat/bin/selfcheck.mjs
dsh() {
  if [ -z "${DSH_COMPAT_NM:-}" ]; then
    DSH_COMPAT_NM="$(npm root -g 2>/dev/null)/dsh-termux/node_modules"
    export DSH_COMPAT_NM
  fi
  if [ -f "$HOME/code/dsh-compat/bin/selfcheck.mjs" ] && [ -d "$DSH_COMPAT_NM" ]; then
    node "$HOME/code/dsh-compat/bin/selfcheck.mjs" --node-modules "$DSH_COMPAT_NM" >&2 || true
  fi
  command dsh "$@"
}
# <<< termux-dsh selfcheck <<<
EOF
info "已写入自检块：$ZSHRC"
