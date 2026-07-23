#!/usr/bin/env bash
# Tests for preflight-implement.sh, run against fake-gh (see run-tests.sh for
# harness setup).
#
# Also runnable standalone. When not invoked via run-tests.sh, FAKE_GH_STATE_DIR
# won't already be set and the real `gh` would still be on PATH — so set up our
# own fake-gh fixture and PATH override here, the same way run-tests.sh does,
# to guarantee this never talks to the real `gh` CLI or a real repo.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

if [[ -z "${FAKE_GH_STATE_DIR:-}" ]]; then
  export FAKE_GH_STATE_DIR
  FAKE_GH_STATE_DIR=$(mktemp -d)
  FAKE_BIN_DIR=$(mktemp -d)
  ln -s "$TEST_DIR/fake-gh" "$FAKE_BIN_DIR/gh"
  trap 'rm -rf "$FAKE_GH_STATE_DIR" "$FAKE_BIN_DIR"' EXIT
  export PATH="$FAKE_BIN_DIR:$PATH"
fi

PREFLIGHT="$SCRIPTS_DIR/preflight-implement.sh"

echo "preflight-implement.sh"

# (a) gate:plan-approved label present -> approved, exits 0.
gh issue edit 201 --add-label "gate:plan-approved" >/dev/null
assert_success "exits 0 when gate:plan-approved label is present" "$PREFLIGHT" 201

# (b) no gate label, but a comment whose body starts with "## Implementation Plan" -> approved, exits 0.
gh issue comment 202 --body "## Implementation Plan

Some approved plan text." >/dev/null
assert_success "exits 0 when an Implementation Plan comment is present" "$PREFLIGHT" 202

# (c) neither label nor plan comment -> fails closed, exits non-zero.
assert_failure "exits non-zero when neither label nor plan comment is present" "$PREFLIGHT" 203

# (d) not a GitHub-backed repo -> cannot verify, fails open, exits 0.
FAKE_GH_NO_REPO=1 assert_success "fails open when repo has no GitHub remote" "$PREFLIGHT" 204

# (e) no arguments -> usage error, exits non-zero. Doesn't touch fake-gh state.
assert_failure "exits non-zero with no arguments" "$PREFLIGHT"

# (f) too many arguments -> usage error, exits non-zero. Doesn't touch fake-gh state.
assert_failure "exits non-zero with two arguments" "$PREFLIGHT" 205 206

# (g) both the gate:plan-approved label AND an Implementation Plan comment
# present -> still approved, exits 0 (either-signal logic must not regress
# when both signals are set).
gh issue edit 207 --add-label "gate:plan-approved" >/dev/null
gh issue comment 207 --body "## Implementation Plan

Some approved plan text." >/dev/null
assert_success "exits 0 when both label and plan comment are present" "$PREFLIGHT" 207

# (h) a comment present, but its body does not start with "## Implementation
# Plan" (e.g. a Phase 1 clarification summary), and no gate label -> must
# not be mistaken for approval; fails closed, exits non-zero.
gh issue comment 208 --body "## Clarification Summary

Some clarification text, not a plan." >/dev/null
assert_failure "exits non-zero when comment present is not an Implementation Plan" "$PREFLIGHT" 208

# (i) gh/jq unavailable -> cannot verify, fails open, exits 0. Build a PATH
# with only bash on it (this branch needs nothing else) so this doesn't
# depend on where gh/jq happen to live on the host machine, mirroring
# test_gate.sh's "gh fails open when unavailable" case. Cleaned up
# immediately (rather than via a second EXIT trap) so it doesn't clobber the
# standalone-mode cleanup trap set up above.
EMPTY_PATH_DIR=$(mktemp -d)
ln -s "$(command -v bash)" "$EMPTY_PATH_DIR/bash"
assert_success "fails open when gh/jq are unavailable" env -i PATH="$EMPTY_PATH_DIR" "$PREFLIGHT" 209
rm -rf "$EMPTY_PATH_DIR"

echo "preflight-implement.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
