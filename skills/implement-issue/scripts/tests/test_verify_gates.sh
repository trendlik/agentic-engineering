#!/usr/bin/env bash
# Tests for verify-gates.sh — the fail-CLOSED CI counterpart to gate.sh.
# Needs a real git repo (for ROLES.yml lookup at repo root) plus fake-gh for
# labels, timeline, and the resolved actor identity.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

VERIFY="$SCRIPTS_DIR/verify-gates.sh"
STATE="$SCRIPTS_DIR/state.sh"

echo "verify-gates.sh"

REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
git init --quiet "$REPO"

# --- no ROLES.yml at all -> fails closed regardless of anything else ---
assert_failure "fails when ROLES.yml is missing from the repo root" \
  bash -c "cd '$REPO' && '$VERIFY' 40"

cat > "$REPO/ROLES.yml" <<'EOF'
alice: analyst
bob: architect
carol: developer
EOF

# --- ROLES.yml present, but neither gate has been approved yet ---
assert_failure "fails when no gates are approved" bash -c "cd '$REPO' && '$VERIFY' 40"

# --- analysis gate approved by the right role (alice=analyst), plan gate missing ---
FAKE_GH_USER=alice "$STATE" approve 40 analysis >/dev/null 2>&1
assert_failure "fails when only one of two required gates is approved" \
  bash -c "cd '$REPO' && '$VERIFY' 40"

# --- plan gate approved by the WRONG role (carol=developer, not architect) ---
FAKE_GH_USER=carol "$STATE" approve 40 plan >/dev/null 2>&1
assert_failure "fails when a gate was approved by the wrong role" \
  bash -c "cd '$REPO' && '$VERIFY' 40"

# --- re-approve plan with the right role (bob=architect) ---
FAKE_GH_USER=bob "$STATE" approve 40 plan >/dev/null 2>&1
assert_success "passes when both gates are approved by the correct roles" \
  bash -c "cd '$REPO' && '$VERIFY' 40"

# --- gate approved by someone with no entry in ROLES.yml at all ---
FAKE_GH_USER=stranger "$STATE" approve 41 analysis >/dev/null 2>&1
FAKE_GH_USER=bob "$STATE" approve 41 plan >/dev/null 2>&1
assert_failure "fails when the approver isn't listed in ROLES.yml" \
  bash -c "cd '$REPO' && '$VERIFY' 41"

echo "verify-gates.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
