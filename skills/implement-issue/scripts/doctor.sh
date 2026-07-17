#!/usr/bin/env bash
# Verifies this machine has everything implement-issue needs, and reports
# clear remediation for anything missing. Safe to re-run any time — read-only.
#
# Usage: doctor.sh

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

fail=0

check() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then
    ok "OK    $desc"
  else
    err "MISS  $desc"
    fail=1
  fi
}

echo "implement-issue environment check"
echo "---"

check "git installed"            command -v git
check "gh installed"             command -v gh
check "jq installed"             command -v jq
check "gh authenticated"         gh auth status
check "inside a git repository"  git rev-parse --is-inside-work-tree
check "origin is a GitHub repo"  gh repo view

# Advisory only (never fails the check): the recommended permission allowlist
# lets a run — coordinator and sub-agents — proceed without approval prompts.
# The skill works without it; it just prompts more. See sync-permissions.sh.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$repo_root" ]]; then
  local_settings="$repo_root/.claude/settings.local.json"
  if [[ -f "$local_settings" ]] && grep -q '/\.claude/worktrees/\*\*' "$local_settings" 2>/dev/null; then
    ok "OK    permission allowlist installed (settings.local.json)"
  else
    info "INFO  permission allowlist not installed (optional) — run to reduce approval prompts:"
    info "        $DIR/sync-permissions.sh"
  fi
fi

echo "---"
if [[ $fail -eq 0 ]]; then
  ok "All checks passed — implement-issue is ready to use here."
else
  err "Some checks failed."
  echo
  echo "Remediation:"
  command -v git >/dev/null 2>&1 || echo "  - install git: https://git-scm.com/downloads"
  command -v gh  >/dev/null 2>&1 || echo "  - install gh:  https://cli.github.com"
  command -v jq  >/dev/null 2>&1 || echo "  - install jq:  brew install jq  (or your OS package manager)"
  gh auth status >/dev/null 2>&1 || echo "  - authenticate: gh auth login"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || echo "  - run this from inside a git repository"
  gh repo view >/dev/null 2>&1 || echo "  - the current repo's 'origin' remote must point to GitHub"
fi
exit $fail
