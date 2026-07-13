#!/usr/bin/env bash
# Appends or updates one record in the per-repo outcome ledger
# (.implement-issue/outcomes.jsonl in the target repo), the historical data
# a future change-sizing step will use for reference-class forecasting.
# See ../WORKFLOW.md Phase 8 for when this is called and ../SKILL.md's
# "Outcome ledger" section for the field list and rationale.
#
# Usage:
#   record-outcome.sh <issue> key=value [key=value ...]
#
# Known keys (anything else is rejected):
#   issue pr labels outcome plan_file_count files_changed diff_loc commits
#   clarify_rounds plan_revisions review_loops ci_fixes wall_clock_hours
#   skill_sha recorded_at
#
# - `issue` is also given positionally (first arg) and must be a
#   non-negative integer.
# - `labels` is a comma-separated string, stored as a JSON array (empty
#   string -> empty array).
# - `outcome` must be one of: merged, closed, aborted.
# - Any known key not supplied is written as JSON null.
# - `recorded_at` defaults to today (`date +%F`); `skill_sha` defaults to
#   this skill's short commit sha (or "unknown" if that can't be resolved).
# - UPSERT keyed on `issue`: replaces any existing line for the same issue
#   number in place, never appends a duplicate.
#
# Ledger path: $(git rev-parse --show-toplevel)/.implement-issue/outcomes.jsonl
# Override with $OUTCOMES_FILE (used by tests).

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

require_cmd jq "brew install jq"

INT_KEYS="issue pr plan_file_count files_changed diff_loc commits clarify_rounds plan_revisions review_loops ci_fixes"
KNOWN_KEYS="issue title pr labels outcome plan_file_count files_changed diff_loc commits clarify_rounds plan_revisions review_loops ci_fixes wall_clock_hours skill_sha recorded_at"

is_known_key() {
  local k=$1 x
  for x in $KNOWN_KEYS; do [[ "$x" == "$k" ]] && return 0; done
  return 1
}

is_int_key() {
  local k=$1 x
  for x in $INT_KEYS; do [[ "$x" == "$k" ]] && return 0; done
  return 1
}

is_integer() { [[ "$1" =~ ^-?[0-9]+$ ]]; }
is_number()  { [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; }

[[ $# -ge 1 ]] || die "usage: record-outcome.sh <issue> key=value [key=value ...]"
issue=$1
shift
is_integer "$issue" && [[ "$issue" -ge 0 ]] || die "issue must be a non-negative integer, got: '$issue'"

# Resolve ledger path.
if [[ -n "${OUTCOMES_FILE:-}" ]]; then
  ledger="$OUTCOMES_FILE"
else
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repo (and OUTCOMES_FILE not set)"
  ledger="$toplevel/.implement-issue/outcomes.jsonl"
fi
mkdir -p "$(dirname "$ledger")" || die "could not create ledger directory for $ledger"
touch "$ledger" || die "could not create ledger file $ledger"

# Parse key=value args.
labels_raw=""
labels_given=0
outcome_val=""
jq_args=(--argjson issue "$issue")
jq_set_fields="issue: \$issue"

for kv in "$@"; do
  [[ "$kv" == *=* ]] || die "malformed argument (expected key=value): '$kv'"
  key=${kv%%=*}
  val=${kv#*=}

  is_known_key "$key" || die "unknown field '$key' (known fields: $KNOWN_KEYS)"
  [[ "$key" == "issue" ]] && die "issue is given positionally, not as issue=... (got '$kv')"

  case "$key" in
    labels)
      labels_raw="$val"
      labels_given=1
      ;;
    outcome)
      case "$val" in
        merged|closed|aborted) ;;
        *) die "outcome must be one of merged|closed|aborted, got: '$val'" ;;
      esac
      outcome_val="$val"
      jq_args+=(--arg outcome "$val")
      jq_set_fields="$jq_set_fields, outcome: \$outcome"
      ;;
    wall_clock_hours)
      is_number "$val" || die "wall_clock_hours must be an integer or float, got: '$val'"
      jq_args+=(--argjson wall_clock_hours "$val")
      jq_set_fields="$jq_set_fields, wall_clock_hours: \$wall_clock_hours"
      ;;
    skill_sha|recorded_at)
      jq_args+=(--arg "$key" "$val")
      jq_set_fields="$jq_set_fields, $key: \$$key"
      ;;
    *)
      if is_int_key "$key"; then
        is_integer "$val" || die "$key must be an integer, got: '$val'"
        jq_args+=(--argjson "$key" "$val")
        jq_set_fields="$jq_set_fields, $key: \$$key"
      else
        jq_args+=(--arg "$key" "$val")
        jq_set_fields="$jq_set_fields, $key: \$$key"
      fi
      ;;
  esac
done

if [[ $labels_given -eq 1 ]]; then
  if [[ -z "$labels_raw" ]]; then
    labels_json="[]"
  else
    labels_json=$(printf '%s' "$labels_raw" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
  fi
  jq_args+=(--argjson labels "$labels_json")
  jq_set_fields="$jq_set_fields, labels: \$labels"
fi

# Auto-fill recorded_at and skill_sha unless explicitly passed.
if [[ "$jq_set_fields" != *'recorded_at:'* ]]; then
  recorded_at=$(date +%F)
  jq_args+=(--arg recorded_at "$recorded_at")
  jq_set_fields="$jq_set_fields, recorded_at: \$recorded_at"
fi
if [[ "$jq_set_fields" != *'skill_sha:'* ]]; then
  skill_sha=$(git -C "$DIR/.." rev-parse --short HEAD 2>/dev/null) || skill_sha="unknown"
  [[ -n "$skill_sha" ]] || skill_sha="unknown"
  jq_args+=(--arg skill_sha "$skill_sha")
  jq_set_fields="$jq_set_fields, skill_sha: \$skill_sha"
fi

# Build the full record: every known key present (explicit or null), then
# overlay the fields actually supplied via jq_set_fields. -c keeps it on one
# line, since the ledger format is one JSON object per line (JSONL) and the
# upsert logic below reads/matches line by line.
record=$(jq -nc "${jq_args[@]}" \
  '{
    issue: null, title: null, pr: null, labels: null, outcome: null,
    plan_file_count: null, files_changed: null, diff_loc: null, commits: null,
    clarify_rounds: null, plan_revisions: null, review_loops: null, ci_fixes: null,
    wall_clock_hours: null, skill_sha: null, recorded_at: null
  } * {'"$jq_set_fields"'}') || die "failed to build JSON record"

# UPSERT: replace any existing line for this issue, else append.
tmp=$(mktemp) || die "could not create temp file"
found=0
if [[ -s "$ledger" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line_issue=$(jq -r '.issue' <<<"$line" 2>/dev/null)
    if [[ "$line_issue" == "$issue" ]]; then
      printf '%s\n' "$record" >>"$tmp"
      found=1
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$ledger"
fi
if [[ $found -eq 0 ]]; then
  printf '%s\n' "$record" >>"$tmp"
fi
mv "$tmp" "$ledger" || die "could not write ledger $ledger"

echo "$record"
