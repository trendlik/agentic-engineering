#!/usr/bin/env bash
# Tests for verify-gates.sh — the fail-CLOSED CI counterpart to gate.sh.
# Presence-only check: does gate:<name>-approved exist on the issue. Run
# against fake-gh for labels.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

VERIFY="$SCRIPTS_DIR/verify-gates.sh"
STATE="$SCRIPTS_DIR/state.sh"

echo "verify-gates.sh"

assert_failure "fails when no gates are approved" "$VERIFY" 60

"$STATE" approve 60 analysis >/dev/null 2>&1
assert_failure "fails when only one of two required gates is approved" "$VERIFY" 60

"$STATE" approve 60 plan >/dev/null 2>&1
assert_success "passes once both required gates are approved" "$VERIFY" 60

# Presence-only: it doesn't matter who applied the label, or how many times.
"$STATE" approve 60 analysis >/dev/null 2>&1
assert_success "re-approving an already-approved gate is harmless" "$VERIFY" 60

assert_failure "a fresh issue with no gates at all still fails" "$VERIFY" 61

echo "verify-gates.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
