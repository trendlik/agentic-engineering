#!/usr/bin/env bash
# Tests for state.sh, run against fake-gh (see run-tests.sh for harness setup).
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

STATE="$SCRIPTS_DIR/state.sh"

echo "state.sh"

# init sets the initial stage
"$STATE" init 1 >/dev/null 2>&1
assert_eq "$("$STATE" get 1)" "clarify" "init sets stage:clarify on a fresh issue"

# init is idempotent — does not clobber an existing stage
"$STATE" set 1 plan >/dev/null 2>&1
"$STATE" init 1 >/dev/null 2>&1
assert_eq "$("$STATE" get 1)" "plan" "init leaves an already-staged issue alone"

# set moves the stage and removes the previous stage label
"$STATE" set 1 implement >/dev/null 2>&1
assert_eq "$("$STATE" get 1)" "implement" "set moves to the new stage"
labels=$("$STATE" labels 1)
assert_failure "set removes the previous stage label" bash -c "echo '$labels' | grep -qx 'stage:plan'"

# unknown stage is rejected
assert_failure "set rejects an unknown stage" "$STATE" set 1 bogus

# get on a fresh issue with no labels reports "none"
assert_eq "$("$STATE" get 99)" "none" "get reports 'none' for an unlabeled issue"

# approve/check round-trip
assert_failure "check fails before approval" "$STATE" check 2 analysis
"$STATE" approve 2 analysis >/dev/null 2>&1
assert_success "check succeeds after approval" "$STATE" check 2 analysis

# unknown gate is rejected
assert_failure "approve rejects an unknown gate" "$STATE" approve 2 bogus
assert_failure "check rejects an unknown gate" "$STATE" check 2 bogus

echo "state.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
