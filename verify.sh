#!/data/data/com.termux/files/usr/bin/bash
# Device regression for the Termux dsh repack. Runs only bash-testable checks;
# the behavioural checklist is docs/verify-checklist.md.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"
set +e

fail=0
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }
skip() { printf 'SKIP  %s\n' "$*"; }

chk() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else bad "$label"; fi
}
chk_optional() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else skip "$label"; fi
}

# Locate the installed package (dsh-termux by design; tolerate a local dev tree).
NPM_ROOT="$(npm root -g 2>/dev/null)"
DSH_PKG="${DSH_PKG:-$NPM_ROOT/dsh-termux}"
[[ -d "$DSH_PKG" ]] || DSH_PKG="$NPM_ROOT/@deepseek-ai/dsh"

echo "== 包与启动 =="
chk "dsh 可执行" dsh --version
chk "包版本含 -tdsh." bash -c 'dsh --version 2>/dev/null | grep -q -- "-tdsh\."'
chk "profile 组合有效" dsh --profile web --dump-config

echo
echo "== 原生模块 =="
KOFFI="$DSH_PKG/node_modules/koffi/build/koffi/android_arm64/koffi.node"
PTY="$DSH_PKG/node_modules/node-pty/prebuilds/android-arm64/pty.node"
chk "koffi 是 arm64" bash -c "file '$KOFFI' 2>/dev/null | grep -q 'ARM aarch64'"
chk "node-pty 是 arm64" bash -c "file '$PTY' 2>/dev/null | grep -q 'ARM aarch64'"

echo
echo "== 补丁 =="
SESSION="$DSH_PKG/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js"
chk "B5 会话 rename 已生效" grep -q 'process.platform === "android"' "$SESSION"
chk "B5 rename 调用存在" grep -q 'rename(tmp, finalPath)' "$SESSION"
chk "profile 树补丁就位" bash "$HERE/patches/apply.sh" --check

echo
echo "== profile 配置 =="
chk "sandbox 放行已配置" bash -c 'dsh --profile web --dump-config 2>/dev/null | grep -q allowUnconfinedFallback'
chk "web-fetch 放行已配置" bash -c 'dsh --profile web --dump-config 2>/dev/null | grep -q allowBenchmarkAddresses'
chk "HMR 已禁用" bash -c 'dsh --profile web --dump-config 2>/dev/null | grep -A2 -E "^[[:space:]]*- id: hmr" | grep -q "disabled: true"'

echo
echo "== 工作区接线（可选） =="
if [[ -d "${CODE:-$HOME/code}/workflow-sync" ]]; then
  chk "技能 22 条" bash -c '[[ $(ls ~/.dsh/skills 2>/dev/null | wc -l) -eq 22 ]]'
  chk "pre-commit 钩子" test -x "$HOME/code/workflow-sync/.git/hooks/pre-commit"
else
  skip "未安装 workflow-sync，跳过记忆/技能检查"
fi

echo
if [[ "$fail" -ne 0 ]]; then
  echo "结果：有失败项，见上。"
  exit 1
fi
echo "结果：全部 PASS。手工项见 docs/verify-checklist.md"
