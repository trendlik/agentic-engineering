#!/usr/bin/env bash
# Tests for backfill-outcomes.sh's `extract` subcommand: pure/offline, reads
# hand-written gh-shaped JSON fixtures from disk and prints one ledger
# record. The `run` subcommand needs live gh and is out of scope here.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

BACKFILL="$SCRIPTS_DIR/backfill-outcomes.sh"

echo "backfill-outcomes.sh"

fixtures=$(mktemp -d)
cleanup() { rm -rf "$fixtures"; }
trap cleanup EXIT

# --- merged PR fixture -----------------------------------------------------
issue_merged="$fixtures/issue-merged.json"
pr_merged="$fixtures/pr-merged.json"

cat >"$issue_merged" <<'EOF'
{
  "number": 42,
  "title": "Add feature X",
  "createdAt": "2024-01-01T00:00:00Z",
  "labels": [
    {"name": "bug"},
    {"name": "stage:plan"},
    {"name": "gate:analysis-approved"}
  ]
}
EOF

cat >"$pr_merged" <<'EOF'
{
  "number": 100,
  "mergedAt": "2024-01-01T03:30:00Z",
  "additions": 50,
  "deletions": 20,
  "files": [
    {"path": "a.txt", "additions": 30, "deletions": 10},
    {"path": "b.txt", "additions": 20, "deletions": 10}
  ],
  "commits": [
    {"messageHeadline": "Implement feature", "messageBody": ""},
    {"messageHeadline": "Address CI failures", "messageBody": "fixed lint"},
    {"messageHeadline": "Final cleanup", "messageBody": ""}
  ],
  "state": "MERGED"
}
EOF

rec=$("$BACKFILL" extract "$issue_merged" "$pr_merged")
assert_success "extract on merged fixture exits 0" bash -c "true"
assert_eq "$(jq -r '.issue' <<<"$rec")" "42" "merged: issue number extracted"
assert_eq "$(jq -r '.title' <<<"$rec")" "Add feature X" "merged: title extracted"
assert_eq "$(jq -r '.pr' <<<"$rec")" "100" "merged: pr number extracted"
assert_eq "$(jq -r '.outcome' <<<"$rec")" "merged" "merged: outcome is 'merged'"
assert_eq "$(jq -r '.files_changed' <<<"$rec")" "2" "merged: files_changed counts files array"
assert_eq "$(jq -r '.diff_loc' <<<"$rec")" "70" "merged: diff_loc is PR-level additions+deletions"
assert_eq "$(jq -r '.wall_clock_hours' <<<"$rec")" "3.5" "merged: wall_clock_hours computed from createdAt/mergedAt"
assert_eq "$(jq -r '.wall_clock_hours | type' <<<"$rec")" "number" "merged: wall_clock_hours is a JSON number"
assert_eq "$(jq -c '.labels' <<<"$rec")" '["bug"]' "merged: labels drop stage:*/gate:* but keep semantic labels"

# ci_fixes counts commits whose message matches "address CI failures" (ci)
assert_eq "$(jq -r '.ci_fixes' <<<"$rec")" "1" "merged: ci_fixes counts only the matching commit"
assert_eq "$(jq -r '.commits' <<<"$rec")" "3" "merged: commits counts all commits"

# non-reconstructable fields are null
assert_eq "$(jq -r '.plan_file_count' <<<"$rec")" "null" "merged: plan_file_count is null (not reconstructable)"
assert_eq "$(jq -r '.clarify_rounds' <<<"$rec")" "null" "merged: clarify_rounds is null (not reconstructable)"
assert_eq "$(jq -r '.plan_revisions' <<<"$rec")" "null" "merged: plan_revisions is null (not reconstructable)"
assert_eq "$(jq -r '.review_loops' <<<"$rec")" "null" "merged: review_loops is null (not reconstructable)"

# --- unmerged/closed PR fixture --------------------------------------------
issue_closed="$fixtures/issue-closed.json"
pr_closed="$fixtures/pr-closed.json"

cat >"$issue_closed" <<'EOF'
{
  "number": 43,
  "title": "Abandoned idea",
  "createdAt": "2024-02-01T00:00:00Z",
  "labels": [{"name": "wontfix"}]
}
EOF

cat >"$pr_closed" <<'EOF'
{
  "number": 101,
  "additions": 5,
  "deletions": 3,
  "files": [{"path": "c.txt", "additions": 5, "deletions": 3}],
  "commits": [{"messageHeadline": "wip", "messageBody": ""}],
  "state": "CLOSED"
}
EOF

rec_closed=$("$BACKFILL" extract "$issue_closed" "$pr_closed")
assert_eq "$(jq -r '.outcome' <<<"$rec_closed")" "closed" "unmerged PR (no mergedAt): outcome is 'closed'"
assert_eq "$(jq -r '.wall_clock_hours' <<<"$rec_closed")" "null" "unmerged PR: wall_clock_hours is null"

# --- diff_loc fallback: no top-level additions/deletions, per-file only ---
pr_fallback="$fixtures/pr-fallback.json"
cat >"$pr_fallback" <<'EOF'
{
  "number": 102,
  "mergedAt": "2024-01-01T01:00:00Z",
  "files": [
    {"path": "a.txt", "additions": 12, "deletions": 4},
    {"path": "b.txt", "additions": 7, "deletions": 1}
  ],
  "commits": [{"messageHeadline": "fix", "messageBody": ""}],
  "state": "MERGED"
}
EOF

rec_fallback=$("$BACKFILL" extract "$issue_merged" "$pr_fallback")
assert_eq "$(jq -r '.diff_loc' <<<"$rec_fallback")" "24" "diff_loc falls back to summed per-file additions+deletions when PR-level totals are absent"

echo "backfill-outcomes.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
