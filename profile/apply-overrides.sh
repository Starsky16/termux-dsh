#!/data/data/com.termux/files/usr/bin/bash
# Append the Termux host-service overrides to a profile's cordis.patch.yml.
#
# Each block in overrides.yml is appended only when its marker is absent, so
# legacy installs that already have the sandbox block get just the missing
# web-fetch / HMR rows. The profile file is backed up before any change.
#
# Usage: apply-overrides.sh [profile-name]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

PROFILE="${DSH_HOME:-$HOME/.dsh}/profiles/${1:-web}"
TARGET="$PROFILE/cordis.patch.yml"
SRC="$HERE/overrides.yml"
[[ -f "$SRC" ]] || die "缺覆盖文件：$SRC"
mkdir -p "$PROFILE"
if [[ -f "$TARGET" ]]; then
  cp -p "$TARGET" "$TARGET.bak-$(date +%s)"
fi
touch "$TARGET"

changed=0

# extract_block <first> <next|-> prints the YAML rows of one block without the
# "# --- block" markers or the file header.
extract_block() {
  local first="$1" next="$2"
  if [[ "$next" == "-" ]]; then
    sed -n "/^# --- block: $first ---$/,\$p" "$SRC" | sed '1d' | sed '/./,$!d'
  else
    sed -n "/^# --- block: $first ---$/,/^# --- block: $next ---$/p" "$SRC" | sed '1d;$d' | sed '/./,$!d'
  fi
}

append_block() {
  local first="$1" next="$2" marker="$3"
  if grep -qF "$marker" "$TARGET" 2>/dev/null; then
    info "已存在：$marker"
    return
  fi
  {
    echo
    extract_block "$first" "$next"
  } >>"$TARGET"
  changed=1
  info "已追加：$first"
}

append_block sandbox web-fetch "allowUnconfinedFallback"
append_block web-fetch hmr "allowBenchmarkAddresses"
if grep -qE '(^|[[:space:]])id: hmr([[:space:]]|$)' "$TARGET" 2>/dev/null; then
  info "已存在：hmr"
else
  {
    echo
    extract_block hmr -
  } >>"$TARGET"
  changed=1
  info "已追加：hmr"
fi

if [[ "$changed" == "1" ]]; then
  echo
  echo "profile 覆盖已更新：$TARGET"
  echo "重启 dsh 后生效：pkill -f 'dsh web' ; dsh web"
else
  info "profile 覆盖已是最新：$TARGET"
fi
