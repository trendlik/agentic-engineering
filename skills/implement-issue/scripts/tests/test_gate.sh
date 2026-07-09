#!/usr/bin/env bash
# Tests for gate.sh, run against fake-gh (see run-tests.sh for harness setup).
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

GATE="$SCRIPTS_DIR/gate.sh"
STATE="$SCRIPTS_DIR/state.sh"

echo "gate.sh"

# Blocks when the gate hasn't been approved.
assert_failure "gate blocks an unapproved plan gate" "$GATE" 3 plan

# Unblocks once state.sh records the approval.
"$STATE" approve 3 plan >/dev/null 2>&1
assert_success "gate passes once approved" "$GATE" 3 plan

# Fails OPEN when the repo isn't GitHub-backed — must never block offline/non-GitHub use.
FAKE_GH_NO_REPO=1 assert_success "gate fails open when repo has no GitHub remote" "$GATE" 3 plan

# Fails OPEN when gh isn't on PATH at all. Build a PATH with only bash on it
# (gate.sh's fail-open branch needs nothing else) so this doesn't depend on
# where gh/jq happen to live on the host machine.
EMPTY_PATH_DIR=$(mktemp -d)
trap 'rm -rf "$EMPTY_PATH_DIR"' EXIT
ln -s "$(command -v bash)" "$EMPTY_PATH_DIR/bash"
assert_success "gate fails open when gh is unavailable" env -i PATH="$EMPTY_PATH_DIR" "$GATE" 3 plan

echo "gate.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
