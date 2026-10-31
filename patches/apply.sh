#!/data/data/com.termux/files/usr/bin/bash
#
# Re-apply the A-class host patches to a dsh *profile* tree.
#
# Why only the profile tree: the repack pipeline bakes the same patches into
# the global dsh-termux install. `dsh plugin add` makes pnpm materialise
# pristine @deepseek-ai/* copies inside ${DSH_HOME}/profiles/<name>/node_modules,
# which shadow the global tree; only that copy still needs a runtime patch.
#
# Usage:
#   apply.sh [--check|--apply|--revert] [--profile <name|path>]
#
#   --check   (default) report only; exit 1 when a patch is missing
#   --apply   patch the profile tree; refuses on any drift (no half-applied set)
#   --revert  restore pristine files (or remove files created by the patch)
#
# Missing packages are skipped: a profile that never installed them is normal.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

MODE="--check"
PROFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|--apply|--revert) MODE="$1"; shift ;;
    --profile)
      [[ $# -ge 2 ]] || die "--profile 需要一个值"
      PROFILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  PROFILE="${DSH_HOME:-$HOME/.dsh}/profiles/web"
elif [[ "$PROFILE" != /* ]]; then
  PROFILE="${DSH_HOME:-$HOME/.dsh}/profiles/$PROFILE"
fi
NM="$PROFILE/node_modules"
MANIFEST="$HERE/manifest.json"

[[ -f "$MANIFEST" ]] || die "缺 manifest：$MANIFEST"
have node || die "需要 node 解析 manifest.json"
have patch || die "需要 patch（Termux：pkg install patch）"

# section=core only: platform/* patches belong to the repack build, never to a
# profile tree. Order is the manifest order (softlock before flock).
TARGETS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && TARGETS+=("$line")
done < <(node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const t of m.targets) {
  if (t.section !== "core") continue;
  process.stdout.write([t.pkg, t.rel, t.patch, t.pristine_sha256 ?? "", t.patched_sha256 ?? "", t.create ? "1" : "0"].join("\u001f") + "\n");
}' "$MANIFEST")

[[ ${#TARGETS[@]} -gt 0 ]] || die "manifest 里没有 core target"

# 0 skip / 1 missing / 2 pristine / 3 patched / 4 drift
CLASS=0
CLASS_WHY=""
classify() {
  local pkg="$1" rel="$2" pristine="$3" patched="$4" create="$5"
  local dest="$NM/$pkg/$rel"
  # A create target only exists after the package itself is installed. In a
  # fresh profile tree (no node_modules), every target is "not installed" —
  # treating the missing softlock.js as "to be created" makes --check fail on
  # a healthy install with no plugins.
  if [[ ! -d "$NM/$pkg" ]]; then CLASS=0; CLASS_WHY="not installed"; return; fi
  if [[ ! -f "$dest" ]]; then
    if [[ "$create" == "1" ]]; then CLASS=1; CLASS_WHY="missing (to be created)"
    else CLASS=0; CLASS_WHY="not installed"; fi
    return
  fi
  local got; got="$(sha "$dest")"
  if [[ -n "$pristine" && "$got" == "$pristine" ]]; then CLASS=2; CLASS_WHY="pristine"; return; fi
  if [[ "$got" == "$patched" ]]; then CLASS=3; CLASS_WHY="patched"; return; fi
  CLASS=4; CLASS_WHY="drift (sha256=$got)"
}

label() {
  case "$1" in
    0) echo "skip  " ;; 1) echo "create" ;; 2) echo "patch " ;; 3) echo "ok    " ;; 4) echo "DRIFT " ;;
  esac
}

SCAN_TODO=0
SCAN_PATCHED=0
SCAN_SKIPPED=0
SCAN_DRIFTED=0
scan() {
  SCAN_TODO=0; SCAN_PATCHED=0; SCAN_SKIPPED=0; SCAN_DRIFTED=0
  for line in "${TARGETS[@]}"; do
    IFS=$'\x1f' read -r pkg rel patchref pristine patched create <<<"$line"
    classify "$pkg" "$rel" "$pristine" "$patched" "$create"
    printf '%s %s/%s  (%s)\n' "$(label "$CLASS")" "$pkg" "$rel" "$CLASS_WHY"
    case "$CLASS" in
      0) SCAN_SKIPPED=$((SCAN_SKIPPED + 1)) ;;
      1|2) SCAN_TODO=$((SCAN_TODO + 1)) ;;
      3) SCAN_PATCHED=$((SCAN_PATCHED + 1)) ;;
      4) SCAN_DRIFTED=$((SCAN_DRIFTED + 1)) ;;
    esac
  done
  echo
  echo "总计：需打 $SCAN_TODO，已打 $SCAN_PATCHED，跳过 $SCAN_SKIPPED，漂移 $SCAN_DRIFTED"
  [[ "$SCAN_DRIFTED" -eq 0 ]]
}

apply_one() {
  local pkg="$1" rel="$2" patchref="$3" pristine="$4" patched="$5" create="$6"
  local pkg_root="$NM/$pkg" dest="$NM/$pkg/$rel"
  classify "$pkg" "$rel" "$pristine" "$patched" "$create"
  case "$CLASS" in
    0|3) return 0 ;;
    4) die "漂移，拒绝打半套：$pkg/$rel（$CLASS_WHY）" ;;
  esac
  [[ -f "$HERE/$patchref" ]] || die "缺补丁：$HERE/$patchref"
  if [[ "$create" != "1" ]]; then
    [[ -f "$dest.orig" ]] || cp -p "$dest" "$dest.orig"
  fi
  ( cd "$pkg_root" && patch -p1 --forward --batch < "$HERE/$patchref" ) \
    || die "打补丁失败：$pkg/$rel"
  local got; got="$(sha "$dest")"
  if [[ "$got" != "$patched" ]]; then
    [[ "$create" == "1" ]] && rm -f "$dest" || { [[ -f "$dest.orig" ]] && cp -p "$dest.orig" "$dest"; }
    die "补丁后哈希不符：$pkg/$rel（得到 $got）"
  fi
  echo "patched $pkg/$rel"
}

revert_one() {
  local pkg="$1" rel="$2" patchref="$3" pristine="$4" patched="$5" create="$6"
  local pkg_root="$NM/$pkg" dest="$NM/$pkg/$rel"
  classify "$pkg" "$rel" "$pristine" "$patched" "$create"
  case "$CLASS" in
    0) return 0 ;;
    2) return 0 ;;
    4) die "漂移，拒绝回滚：$pkg/$rel（$CLASS_WHY）" ;;
  esac
  if [[ "$create" == "1" ]]; then
    rm -f "$dest"
    echo "removed $pkg/$rel"
    return 0
  fi
  ( cd "$pkg_root" && patch -p1 -R --forward --batch < "$HERE/$patchref" ) \
    || die "回滚失败：$pkg/$rel"
  local got; got="$(sha "$dest")"
  [[ "$got" == "$pristine" ]] || die "回滚后哈希不符：$pkg/$rel（得到 $got）"
  rm -f "$dest.orig"
  echo "reverted $pkg/$rel"
}

if [[ "$MODE" == "--check" ]]; then
  scan || exit 1
  [[ "$SCAN_TODO" -eq 0 ]] || exit 1
  exit 0
fi

if [[ "$MODE" == "--apply" ]]; then
  scan || die "存在漂移，未做任何修改"
  for line in "${TARGETS[@]}"; do
    IFS=$'\x1f' read -r pkg rel patchref pristine patched create <<<"$line"
    apply_one "$pkg" "$rel" "$patchref" "$pristine" "$patched" "$create"
  done
  echo
  echo "profile 树已处理。若刚有改动，重启 dsh 后生效："
  echo "  pkill -f 'dsh web' ; dsh web"
  exit 0
fi

# --revert: reverse order so flock is restored before softlock disappears.
scan || die "存在漂移，未做任何修改"
for ((i = ${#TARGETS[@]} - 1; i >= 0; i--)); do
  IFS=$'\x1f' read -r pkg rel patchref pristine patched create <<<"${TARGETS[$i]}"
  revert_one "$pkg" "$rel" "$patchref" "$pristine" "$patched" "$create"
done
echo
echo "profile 树已回滚为 pristine；重启 dsh 后生效。"
