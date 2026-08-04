#!/usr/bin/env bash
# Tests for record-outcome.sh (pure/offline: no gh, no network). Each test
# uses its own temp ledger via $OUTCOMES_FILE so tests don't interfere.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"
# shellcheck source=../lib/common.sh
source "$SCRIPTS_DIR/lib/common.sh"

RECORD="$SCRIPTS_DIR/record-outcome.sh"

echo "record-outcome.sh"

# --- append + second issue appends a second line ------------------------
ledger=$(mktemp)
rm -f "$ledger"  # record-outcome.sh must create it itself
OUTCOMES_FILE="$ledger" "$RECORD" 1 title=First outcome=merged >/dev/null 2>&1
assert_success "ledger file created after first record" bash -c "[[ -f '$ledger' ]]"
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "1" "first record is the only line"

OUTCOMES_FILE="$ledger" "$RECORD" 2 title=Second outcome=closed >/dev/null 2>&1
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "2" "second (different) issue appends a second line"
rm -f "$ledger"

# --- upsert: same issue replaces its line in place -----------------------
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 5 title=Original outcome=merged pr=10 >/dev/null 2>&1
OUTCOMES_FILE="$ledger" "$RECORD" 6 title=Other outcome=merged pr=11 >/dev/null 2>&1
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "2" "two distinct issues -> two lines before upsert"

OUTCOMES_FILE="$ledger" "$RECORD" 5 title=Updated outcome=closed pr=99 >/dev/null 2>&1
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "2" "re-recording issue 5 does not add a line (upsert, not append)"

line5=$(grep '"issue":5' "$ledger")
assert_eq "$(jq -r '.title' <<<"$line5")" "Updated" "upserted record reflects new title"
assert_eq "$(jq -r '.outcome' <<<"$line5")" "closed" "upserted record reflects new outcome"
assert_eq "$(jq -r '.pr' <<<"$line5")" "99" "upserted record reflects new pr"
rm -f "$ledger"

# --- unsupplied known fields serialize as JSON null ----------------------
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 7 title=Bare >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -r '.clarify_rounds' <<<"$rec")" "null" "unsupplied clarify_rounds is JSON null"
assert_eq "$(jq -r '.plan_revisions' <<<"$rec")" "null" "unsupplied plan_revisions is JSON null"
assert_eq "$(jq -r '.review_loops' <<<"$rec")" "null" "unsupplied review_loops is JSON null"
assert_eq "$(jq -r '.outcome' <<<"$rec")" "null" "unsupplied outcome is JSON null"
assert_eq "$(jq -r '.labels' <<<"$rec")" "null" "unsupplied labels is JSON null"
rm -f "$ledger"

# --- numeric fields are JSON numbers, not strings; labels is an array ----
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 8 diff_loc=123 files_changed=4 commits=2 labels=a,b,c >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -r '.diff_loc | type' <<<"$rec")" "number" "diff_loc is a JSON number"
assert_eq "$(jq -r '.files_changed | type' <<<"$rec")" "number" "files_changed is a JSON number"
assert_eq "$(jq -r '.commits | type' <<<"$rec")" "number" "commits is a JSON number"
assert_eq "$(jq -r '.labels | type' <<<"$rec")" "array" "labels is a JSON array"
rm -f "$ledger"

# --- labels=a,b,c -> 3-element array; empty labels -> empty array --------
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 9 labels=a,b,c >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -c '.labels' <<<"$rec")" '["a","b","c"]' "labels=a,b,c becomes a 3-element JSON array"

OUTCOMES_FILE="$ledger" "$RECORD" 10 labels= >/dev/null 2>&1
rec10=$(grep '"issue":10' "$ledger")
assert_eq "$(jq -c '.labels' <<<"$rec10")" '[]' "empty labels string becomes an empty JSON array"
rm -f "$ledger"

# --- validation / error paths --------------------------------------------
ledger=$(mktemp)
assert_failure "unknown key is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 bogus_field=1
assert_failure "invalid outcome value is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 outcome=merged_wrongly
assert_failure "non-integer issue is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" abc title=x
assert_failure "negative issue is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" -1 title=x
assert_failure "non-integer numeric field is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 diff_loc=1.5
assert_failure "negative count field (diff_loc) is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 diff_loc=-5
assert_failure "negative count field (files_changed) is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 files_changed=-1
assert_success "wall_clock_hours accepts a float" env OUTCOMES_FILE="$ledger" "$RECORD" 20 wall_clock_hours=1.5
rm -f "$ledger"

# --- auto-fill: recorded_at / skill_sha ----------------------------------
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 30 title=AutoFill >/dev/null 2>&1
rec=$(cat "$ledger")
recorded_at=$(jq -r '.recorded_at' <<<"$rec")
skill_sha=$(jq -r '.skill_sha' <<<"$rec")
assert_failure "recorded_at is auto-filled (non-null) when omitted" bash -c "[[ '$recorded_at' == 'null' || -z '$recorded_at' ]]"
assert_failure "skill_sha is auto-filled (non-null) when omitted" bash -c "[[ '$skill_sha' == 'null' || -z '$skill_sha' ]]"

OUTCOMES_FILE="$ledger" "$RECORD" 31 recorded_at=2020-01-01 skill_sha=deadbee >/dev/null 2>&1
rec31=$(grep '"issue":31' "$ledger")
assert_eq "$(jq -r '.recorded_at' <<<"$rec31")" "2020-01-01" "explicit recorded_at is honored"
assert_eq "$(jq -r '.skill_sha' <<<"$rec31")" "deadbee" "explicit skill_sha is honored"
rm -f "$ledger"

# --- skill_sha_default resolution order ----------------------------------
tmp_sha_work=$(mktemp -d)

# 1. git short sha available in git repo
git_repo="$tmp_sha_work/git_repo"
mkdir -p "$git_repo"
git -C "$git_repo" init >/dev/null 2>&1
git -C "$git_repo" config user.email "test@example.com"
git -C "$git_repo" config user.name "Test User"
touch "$git_repo/file.txt"
git -C "$git_repo" add file.txt
git -C "$git_repo" commit -m "initial commit" >/dev/null 2>&1
expected_git_sha=$(git -C "$git_repo" rev-parse --short HEAD)

assert_eq "$(skill_sha_default "$git_repo")" "$expected_git_sha" \
  "skill_sha_default returns git short SHA when git repo exists"

# 2. git sha fails / not a git repo, but SKILL.md with version: X.Y.Z exists -> returns vX.Y.Z
release_store="$tmp_sha_work/release_store"
mkdir -p "$release_store"
cat <<'EOF' > "$release_store/SKILL.md"
---
name: implement-issue
description: test skill
version: 1.0.0
---
EOF

assert_eq "$(skill_sha_default "$release_store")" "v1.0.0" \
  "skill_sha_default falls back to v<version> from SKILL.md when not a git repo"

cat <<'EOF' > "$release_store/SKILL.md"
---
name: test-quoted
version: "2.3.4-beta"
---
EOF

assert_eq "$(skill_sha_default "$release_store")" "v2.3.4-beta" \
  "skill_sha_default handles quoted version strings in SKILL.md"

# 3. both git sha and SKILL.md version fail / missing -> returns unknown
empty_store="$tmp_sha_work/empty_store"
mkdir -p "$empty_store"

assert_eq "$(skill_sha_default "$empty_store")" "unknown" \
  "skill_sha_default returns 'unknown' when not a git repo and SKILL.md missing"

cat <<'EOF' > "$empty_store/SKILL.md"
---
name: implement-issue
description: no version field
---
EOF

assert_eq "$(skill_sha_default "$empty_store")" "unknown" \
  "skill_sha_default returns 'unknown' when SKILL.md exists but has no version"

rm -rf "$tmp_sha_work"

echo "record-outcome.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
