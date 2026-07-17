#!/usr/bin/env bash
# Tests for sync-permissions.sh (pure/offline: no gh, no network). Every run
# uses temp REPO_ROOT/SKILL_DIR/SETTINGS_FILE overrides so nothing touches
# real config.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

SYNC="$SCRIPTS_DIR/sync-permissions.sh"

echo "sync-permissions.sh"

run() { # run with fixed fake paths, writing to the given settings file
  REPO_ROOT="/tmp/fake-repo" SKILL_DIR="/tmp/fake-skill" SETTINGS_FILE="$1" \
    "$SYNC" >/dev/null 2>&1
}

# --- creates file with substituted rules ---------------------------------
sf=$(mktemp); rm -f "$sf"
run "$sf"
assert_success "settings file created" bash -c "[[ -f '$sf' ]]"
assert_success "skill-dir placeholder substituted (single-slash command path)" \
  bash -c "jq -e '.permissions.allow | index(\"Bash(/tmp/fake-skill/scripts/state.sh:*)\")' '$sf'"
assert_success "repo-root worktree rule substituted (// path anchor)" \
  bash -c "jq -e '.permissions.allow | index(\"Edit(//tmp/fake-repo/.claude/worktrees/**)\")' '$sf'"
assert_success "no placeholder token left behind" \
  bash -c "! grep -q '__SKILL_DIR__\|__REPO_ROOT__' '$sf'"
rm -f "$sf"

# --- idempotent: second run adds nothing ---------------------------------
sf=$(mktemp); rm -f "$sf"
run "$sf"
n1=$(jq '.permissions.allow | length' "$sf")
run "$sf"
n2=$(jq '.permissions.allow | length' "$sf")
assert_eq "$n2" "$n1" "re-running does not duplicate rules"
rm -f "$sf"

# --- preserves existing unrelated keys and prior allow/deny entries ------
sf=$(mktemp)
cat >"$sf" <<'JSON'
{ "model": "opus", "permissions": { "allow": ["Bash(npm run *)"], "deny": ["Bash(rm:*)"] } }
JSON
run "$sf"
assert_eq "$(jq -r '.model' "$sf")" "opus" "unrelated top-level key preserved"
assert_success "pre-existing allow entry preserved" \
  bash -c "jq -e '.permissions.allow | index(\"Bash(npm run *)\")' '$sf'"
assert_success "deny list preserved" \
  bash -c "jq -e '.permissions.deny | index(\"Bash(rm:*)\")' '$sf'"
assert_success "new rule added alongside existing" \
  bash -c "jq -e '.permissions.allow | index(\"Bash(gh:*)\")' '$sf'"
rm -f "$sf"

# --- a path with JSON metacharacters cannot inject a standalone rule -----
# Substitution is done inside jq (--arg), so a crafted path stays escaped
# data within one rule rather than breaking out to add an array element.
sf=$(mktemp); rm -f "$sf"
REPO_ROOT='/x/**)","Bash(evil-injected:*)","Edit(/x' SKILL_DIR="/tmp/fake-skill" SETTINGS_FILE="$sf" \
  "$SYNC" >/dev/null 2>&1
injected=$(jq -r '.permissions.allow[]' "$sf" | grep -c '^Bash(evil-injected:\*)$')
assert_eq "$injected" "0" "crafted path does not inject a standalone allow rule"
rm -f "$sf"

echo "sync-permissions.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
