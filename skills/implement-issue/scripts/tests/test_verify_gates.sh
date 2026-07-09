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

# --- one person holding multiple comma-separated roles can satisfy both
# gates alone (e.g. solo testing under a single account) ---
cat >> "$REPO/ROLES.yml" <<'EOF'
erin: analyst,architect,developer,qa
EOF
FAKE_GH_USER=erin "$STATE" approve 42 analysis >/dev/null 2>&1
FAKE_GH_USER=erin "$STATE" approve 42 plan >/dev/null 2>&1
assert_success "passes when a single multi-role approver covers both gates" \
  bash -c "cd '$REPO' && '$VERIFY' 42"

echo "verify-gates.sh (base-ref mode: a PR can't grant itself a role by editing ROLES.yml)"

ORIGIN=$(mktemp -d)
WORK=$(mktemp -d)
trap 'rm -rf "$REPO" "$ORIGIN" "$WORK"' EXIT

git init --quiet --bare "$ORIGIN"
git clone --quiet "$ORIGIN" "$WORK"
git -C "$WORK" config user.email test@test
git -C "$WORK" config user.name test

# The legitimate ROLES.yml, committed on the base branch (origin/main).
(
  cd "$WORK"
  git checkout --quiet -b main
  cat > ROLES.yml <<'EOF'
alice: analyst
bob: architect
EOF
  git add ROLES.yml
  git commit --quiet -m "legit roles"
  git push --quiet origin main
)
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

# A "PR branch" that locally (never pushed to origin/main) edits ROLES.yml to
# grant mallory the architect role — simulating a malicious PR.
(
  cd "$WORK"
  git checkout --quiet -b pr-branch
  cat > ROLES.yml <<'EOF'
alice: analyst
bob: architect
mallory: architect
EOF
  git add ROLES.yml
  git commit --quiet -m "malicious: self-elevate mallory to architect"
)

# analysis gate approved legitimately by alice (valid in both versions of
# ROLES.yml, so it isn't what this test is discriminating on).
FAKE_GH_USER=alice "$STATE" approve 50 analysis >/dev/null 2>&1
# plan gate "approved" by mallory, who only holds architect in the PR
# branch's own (malicious) working-tree copy of ROLES.yml.
FAKE_GH_USER=mallory "$STATE" approve 50 plan >/dev/null 2>&1

assert_failure "base-ref mode ignores the PR branch's edited ROLES.yml and still denies mallory" \
  bash -c "cd '$WORK' && '$VERIFY' 50 main"

# Documents the vulnerability the base-ref argument closes: without it, the
# same working tree reads its own (malicious) ROLES.yml and wrongly passes.
assert_success "no base-ref (legacy/local mode) is NOT safe for this PR scenario -- it trusts the working tree" \
  bash -c "cd '$WORK' && '$VERIFY' 50"

echo "verify-gates.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
