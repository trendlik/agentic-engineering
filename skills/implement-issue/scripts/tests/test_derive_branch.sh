#!/usr/bin/env bash
# Tests for derive-branch.sh, run against fake-gh (see run-tests.sh for harness setup).
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

DERIVE="$SCRIPTS_DIR/derive-branch.sh"

echo "derive-branch.sh"

set_issue() {
  local number=$1 title=$2 label=$3
  echo "$title" > "$FAKE_GH_STATE_DIR/issue-$number.title"
  [[ -n "$label" ]] && echo "$label" > "$FAKE_GH_STATE_DIR/issue-$number.labels"
}

set_issue 10 "Fix login bug!!" "bug"
assert_eq "$("$DERIVE" 10)" "fix/10-fix-login-bug" "bug label -> fix/ prefix, punctuation stripped"

set_issue 11 "Add a really long title that will definitely need truncating to forty characters" "feature"
out=$("$DERIVE" 11)
assert_eq "${out%%-*}" "feat/11" "feature label -> feat/ prefix"
# "feat/11-" is 8 chars; the slug itself must be truncated to <= 40 chars.
assert_success "long title truncated to <= 48 total chars" bash -c "[[ ${#out} -le 48 ]]"

set_issue 12 "!!!" ""
assert_eq "$("$DERIVE" 12)" "issue-12" "empty slug after stripping symbols falls back to issue-<n>"

set_issue 13 "Refactor internals" "chore"
assert_eq "$("$DERIVE" 13)" "chore/13-refactor-internals" "chore label -> chore/ prefix"

set_issue 14 "Update docs" "docs"
assert_eq "$("$DERIVE" 14)" "docs/14-update-docs" "docs label -> docs/ prefix"

set_issue 15 "No labels here" ""
assert_eq "$("$DERIVE" 15)" "feat/15-no-labels-here" "no labels -> feat/ default"

echo "derive-branch.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
