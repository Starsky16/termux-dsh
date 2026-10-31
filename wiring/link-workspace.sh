#!/data/data/com.termux/files/usr/bin/bash
# Wire a Termux workspace to workflow-sync:
#   - each repo's two memory slots (AGENTS.md / AGENTS.local.md, ClassIsland exception)
#   - ~/.dsh/AGENTS.md and ~/.dsh/skills/*
#   - ~/bin helper commands and each repo's pre-commit hook
#   - ~/code/dev/plans -> workflow-sync/plans
#
# The links are read-only pointers. Never edit through a link: resolve the real
# path under workflow-sync first (see rules/global_rules.md).
#
# Usage: link-workspace.sh [--dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

CODE="${CODE:-$HOME/code}"
WS="$CODE/workflow-sync"
DSH="${DSH_HOME:-$HOME/.dsh}"
KEY="-d-code--p2-231095bd5d06244ef5dc"
MEM="$WS/memory/projects/$KEY"
DIGEST="$MEM/global_digest.md"

[[ -d "$WS" ]] || die "缺 workflow-sync：$WS"
[[ -d "$MEM" ]] || die "缺记忆目录：$MEM"
[[ -f "$DIGEST" ]] || die "缺全局摘要：$DIGEST"
[[ -f "$WS/rules/global_rules.md" ]] || die "缺规则：$WS/rules/global_rules.md"

lnk() {
  if [[ "$DRY" == "1" ]]; then
    info "ln -sfn $1 $2"
  else
    ln -sfn "$1" "$2"
  fi
}

backup_if_regular() {
  local path="$1"
  [[ -e "$path" && ! -L "$path" ]] || return 0
  local bak="$path.bak-$(date +%s)"
  if [[ "$DRY" == "1" ]]; then
    warn "would back up $path → $bak"
    return 0
  fi
  if [[ -d "$path" ]]; then
    mv "$path" "$bak"
  else
    cp -p "$path" "$bak"
  fi
  warn "已备份：$path → $bak"
}

mkdir_maybe() {
  if [[ "$DRY" == "1" ]]; then info "mkdir -p $1"; else mkdir -p "$1"; fi
}

append_exclude() {
  local repo="$1" slot="$2"
  if [[ "$DRY" == "1" ]]; then
    info "echo $slot >> $repo/.git/info/exclude"
    return
  fi
  local file="$repo/.git/info/exclude"
  mkdir -p "$(dirname "$file")"
  grep -qxF "$slot" "$file" 2>/dev/null || echo "$slot" >>"$file"
}

# 1) ~/.dsh root + skills
mkdir_maybe "$DSH"
mkdir_maybe "$DSH/skills"
backup_if_regular "$DSH/AGENTS.md"
lnk "$WS/rules/global_rules.md" "$DSH/AGENTS.md"

# Remove stale links that point into workflow-sync and no longer resolve.
if [[ "$DRY" != "1" ]]; then
  for link in "$DSH"/skills/*; do
    [[ -L "$link" ]] || continue
    target="$(readlink "$link")"
    case "$target" in
      "$WS"/skills/*) [[ -e "$link" ]] || rm -f "$link" ;;
    esac
  done
fi

skill_count=0
for src in "$WS"/skills/project/* "$WS"/skills/market/*; do
  [[ -e "$src" ]] || continue
  name="$(basename "$src")"
  backup_if_regular "$DSH/skills/$name"
  lnk "$src" "$DSH/skills/$name"
  skill_count=$((skill_count + 1))
done
info "技能链接：$skill_count 条（期望 22）"

# 2) each repo's two memory slots + pre-commit
for d in "$CODE"/*/; do
  [[ -d "$d/.git" ]] || continue
  d="${d%/}"
  r="$(basename "$d")"
  mem="$MEM/repos/$r.md"
  [[ -f "$mem" ]] || continue
  if [[ "$r" == "ClassIsland" ]]; then
    # Upstream ships its own controlled AGENTS.md; don't touch it.
    slots=("AGENTS.local.md" "CLAUDE.local.md")
    targets=("$mem" "$DIGEST")
  else
    slots=("AGENTS.md" "AGENTS.local.md")
    targets=("$mem" "$DIGEST")
  fi
  for i in "${!slots[@]}"; do
    slot="${slots[$i]}"
    dest="$d/$slot"
    backup_if_regular "$dest"
    lnk "${targets[$i]}" "$dest"
    append_exclude "$d" "$slot"
  done
  hook="$d/.git/hooks/pre-commit"
  if [[ -f "$WS/linux/git-hooks/pre-commit" ]]; then
    mkdir_maybe "$d/.git/hooks"
    backup_if_regular "$hook"
    lnk "$WS/linux/git-hooks/pre-commit" "$hook"
  fi
  info "接线：$r"
done

# 3) ~/bin helpers
mkdir_maybe "$HOME/bin"
for src in "$WS"/linux/bin/*; do
  [[ -f "$src" ]] || continue
  name="$(basename "$src")"
  backup_if_regular "$HOME/bin/$name"
  lnk "$src" "$HOME/bin/$name"
done

# 4) plans
mkdir_maybe "$CODE/dev"
backup_if_regular "$CODE/dev/plans"
lnk "$WS/plans" "$CODE/dev/plans"

echo
if [[ "$DRY" == "1" ]]; then
  info "dry-run 完成；未修改文件系统"
else
  info "接线完成。"
fi
