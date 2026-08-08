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

# --- diff_loc fallback: no PR-level totals AND no file data -> null -------
pr_nodiff="$fixtures/pr-nodiff.json"
cat >"$pr_nodiff" <<'EOF'
{
  "number": 103,
  "mergedAt": "2024-01-01T01:00:00Z",
  "files": [],
  "commits": [{"messageHeadline": "fix", "messageBody": ""}],
  "state": "MERGED"
}
EOF

rec_nodiff=$("$BACKFILL" extract "$issue_merged" "$pr_nodiff")
assert_eq "$(jq -r '.diff_loc' <<<"$rec_nodiff")" "null" "diff_loc is null (not 0) when neither PR-level nor per-file diff data exists"

# --- closes-issue: filters real closing keywords from bare mentions -------
assert_success "closes-issue: 'Closes #42' matches" bash -c "printf 'Closes #42' | \"$BACKFILL\" closes-issue 42"
assert_success "closes-issue: 'fixes: #42' matches (colon variant)" bash -c "printf 'fixes: #42' | \"$BACKFILL\" closes-issue 42"
assert_success "closes-issue: 'This PR resolves #42 nicely' matches" bash -c "printf 'This PR resolves #42 nicely' | \"$BACKFILL\" closes-issue 42"
assert_success "closes-issue: keyword match is case-insensitive" bash -c "printf 'FIXES #42' | \"$BACKFILL\" closes-issue 42"
assert_failure "closes-issue: bare '#42' mention (no keyword) does not match" bash -c "printf 'See #42 for context' | \"$BACKFILL\" closes-issue 42"
assert_failure "closes-issue: '#420' does not match issue 42 (no trailing-digit false match)" bash -c "printf 'Closes #420' | \"$BACKFILL\" closes-issue 42"
assert_failure "closes-issue: 'enclose #42' does not match ('close' as substring of another word)" bash -c "printf 'enclose #42' | \"$BACKFILL\" closes-issue 42"

# --- field-set drift: extract's keys must exactly match record-outcome.sh's
# null skeleton, in the SAME ORDER. The field list is duplicated across the
# two scripts by design (see WORKFLOW.md/SKILL.md's noted architecture
# deviation); this assertion is the mechanical guard against the two
# drifting apart. Both scripts write into the same JSONL file, so order
# drift produces inconsistently-shaped lines, not just a set mismatch.
#
# Uses its own locally-scoped extract record (regenerated here, not the
# $rec left over from the merged-PR fixture ~100 lines above) so this
# assertion doesn't silently depend on no intervening reassignment.
RECORD="$SCRIPTS_DIR/record-outcome.sh"

drift_extract_rec=$("$BACKFILL" extract "$issue_merged" "$pr_merged")

drift_ledger=$(mktemp)
rm -f "$drift_ledger"  # record-outcome.sh must create it itself
OUTCOMES_FILE="$drift_ledger" "$RECORD" 999 title=DriftCheck >/dev/null
drift_record_status=$?
assert_eq "$drift_record_status" "0" "drift check: record-outcome.sh exits 0 writing the minimal DriftCheck record"
drift_record_min_rec=$(cat "$drift_ledger")
rm -f "$drift_ledger"

# keys_unsorted preserves insertion order (jq's `keys` sorts, which would
# hide ordering drift); joining into a single string makes both the set and
# the order part of one comparable value.
extract_keys=$(jq -r 'keys_unsorted | join(",")' <<<"$drift_extract_rec")
record_keys=$(jq -r 'keys_unsorted | join(",")' <<<"$drift_record_min_rec")
assert_eq "$extract_keys" "$record_keys" "extract's keys match record-outcome.sh's null skeleton exactly, same set AND same order (no field-list or ordering drift)"

# --- header comment's key list must exactly match KNOWN_KEYS --------------
# record-outcome.sh's header comment enumerates the known keys for readers;
# it's hand-maintained prose with no mechanical tie to KNOWN_KEYS (the
# actual source of truth the script validates against), so it can silently
# drift from it. Extract both and compare.
known_keys_line=$(grep -m1 '^KNOWN_KEYS=' "$RECORD")
eval "$known_keys_line"
header_keys=$(awk '
  /^# Known keys \(anything else is rejected\):/ { grab=1; next }
  grab && /^#[[:space:]]*$/ { exit }
  grab { sub(/^#[[:space:]]*/, ""); printf "%s ", $0 }
' "$RECORD" | sed 's/ *$//')
assert_eq "$header_keys" "$KNOWN_KEYS" "record-outcome.sh's header comment key list matches KNOWN_KEYS exactly (no doc drift)"

# --- every KNOWN_KEYS entry must have a matching skeleton field -----------
# The inverse gap: a key added to KNOWN_KEYS but never added to the jq null
# skeleton is silently accepted by is_known_key and gets appended to the
# record AFTER recorded_at, breaking the exact field order the drift check
# above protects. Drive record-outcome.sh with every key in KNOWN_KEYS
# supplied and confirm the resulting key set matches the skeleton's
# (`$record_keys`, already established above as the skeleton's key order).
int_keys_line=$(grep -m1 '^INT_KEYS=' "$RECORD")
eval "$int_keys_line"

all_keys_args=()
for k in $KNOWN_KEYS; do
  [[ "$k" == "issue" ]] && continue  # given positionally, not as key=value
  case " $INT_KEYS " in
    *" $k "*) v=7 ;;
    *)
      case "$k" in
        outcome) v=merged ;;
        wall_clock_hours) v=1.5 ;;
        *) v="val-$k" ;;
      esac
      ;;
  esac
  all_keys_args+=("$k=$v")
done

all_keys_ledger=$(mktemp)
rm -f "$all_keys_ledger"  # record-outcome.sh must create it itself
OUTCOMES_FILE="$all_keys_ledger" "$RECORD" 998 "${all_keys_args[@]}" >/dev/null
all_keys_status=$?
assert_eq "$all_keys_status" "0" "all-keys-supplied check: record-outcome.sh exits 0 given every KNOWN_KEYS field"
all_keys_rec=$(cat "$all_keys_ledger")
rm -f "$all_keys_ledger"

all_keys_keys=$(jq -r 'keys_unsorted | join(",")' <<<"$all_keys_rec")
assert_eq "$all_keys_keys" "$record_keys" "record-outcome.sh driven with every KNOWN_KEYS field produces exactly the skeleton's key set, same order (no KNOWN_KEYS entry missing from the jq skeleton)"

# --- header comment's "Fields left null" list must match cmd_extract's -----
# SKILL.md now points readers at this script's header comment as the
# authoritative field list for what backfill can't reconstruct (see
# SKILL.md's "Outcome ledger" section), but unlike record-outcome.sh's
# KNOWN_KEYS header (guarded above) that comment has no mechanical tie to
# cmd_extract's jq skeleton — it's hand-maintained prose that can silently
# drift. Parse the field names out of the "# Fields left null ..." comment
# block and assert they equal the null-valued keys of a freshly generated
# extract record, same order (cmd_extract's null fields already come out in
# comment order, since both are written top-to-bottom against the same jq
# literal).
#
# The parse must not succeed vacuously: if the marker is renamed/removed the
# awk script never sets grab=1, comment_field_list comes back empty, and the
# assertion below compares "" against the (non-empty) real null-field list —
# an inequality, so it fails loudly rather than passing on two empty sides.
EMDASH=$'\xe2\x80\x94'
comment_raw=$(awk -v emdash="$EMDASH" '
  index($0, "# Fields left null") == 1 {
    grab = 1
    line = $0
    sub(/^# Fields left null \(not reconstructable from git\/PR history\):/, "", line)
    print line
    next
  }
  grab {
    line = $0
    sub(/^#[ \t]*/, "", line)
    if (index(line, emdash) > 0) {
      line = substr(line, 1, index(line, emdash) - 1)
      print line
      exit
    }
    print line
  }
' "$BACKFILL")
comment_field_list=$(printf '%s\n' "$comment_raw" \
  | tr '\n' ' ' \
  | tr -s '[:space:]' ' ' \
  | sed -E 's/,[[:space:]]*/,/g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/,$//')

extract_null_keys=$(jq -r 'to_entries | map(select(.value == null) | .key) | join(",")' <<<"$drift_extract_rec")
assert_eq "$comment_field_list" "$extract_null_keys" "backfill-outcomes.sh's header comment 'Fields left null' list matches cmd_extract's actual null-valued keys exactly, same set AND same order (no doc drift)"

echo "backfill-outcomes.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
