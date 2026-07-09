#!/usr/bin/env bash
# Tests for find-artifact.sh, run against fake-gh (see run-tests.sh for harness setup).
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

FIND="$SCRIPTS_DIR/find-artifact.sh"

echo "find-artifact.sh"

# No comments at all -> nothing to find.
assert_failure "exits non-zero when the issue has no comments" "$FIND" 30 "Clarification Summary"

# Post a matching artifact comment.
gh issue comment 30 --body "## Clarification Summary

Requirements confirmed:
- thing one" >/dev/null

assert_eq "$("$FIND" 30 "Clarification Summary" | head -1)" "## Clarification Summary" \
  "returns the comment whose body starts with the requested heading"

# A comment under a different heading shouldn't match.
assert_failure "does not match a differently-headed comment" "$FIND" 30 "Implementation Plan"

# Post a second Clarification Summary (re-clarification) -> the latest wins.
gh issue comment 30 --body "## Clarification Summary

Requirements confirmed:
- thing two (revised)" >/dev/null

out=$("$FIND" 30 "Clarification Summary")
# Piped via stdin (not string-interpolated into a nested shell command) — see
# the same fix in test_sync_base.sh for why.
assert_success "returns the most recent matching comment, not the first" grep -q "thing two" <<< "$out"

echo "find-artifact.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
