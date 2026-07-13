#!/usr/bin/env bash
# Reconstructs outcome-ledger records (see record-outcome.sh) for issues that
# were already implemented before the ledger existed, so a future
# change-sizing step has a reference class to draw on from day one.
#
# Usage:
#   backfill-outcomes.sh extract <issue-json-file> <pr-json-file>
#     Pure, offline, no network: reads a `gh issue view --json ...` blob and a
#     `gh pr view --json ...` blob from disk, prints ONE ledger JSON record
#     to stdout. This is the unit-tested path.
#
#   backfill-outcomes.sh closes-issue <issue-number>
#     Pure, offline: reads a PR body on stdin, exits 0 if it contains a
#     standard GitHub closing keyword (close/closes/closed, fix/fixes/fixed,
#     resolve/resolves/resolved; case-insensitive) immediately referencing
#     `#<issue-number>` (e.g. "Closes #42", "fixes: #42"), exits 1 otherwise.
#     A bare "#42" mention that isn't a closing reference does not match.
#     Used by `run` to filter search-API candidates down to the PR that
#     actually closes the issue.
#
#   backfill-outcomes.sh run [--dry-run]
#     Requires gh. Finds issues carrying a stage:* label, locates each one's
#     merged/closed PR, fetches the JSON `extract` needs, and either prints
#     the record (--dry-run) or upserts it into the ledger via
#     record-outcome.sh. Best-effort: warns and continues on a per-issue
#     failure rather than aborting the whole backfill.
#
# `extract` expects:
#   issue json: gh issue view <n> --json number,title,createdAt,labels
#   pr json:    gh pr view <n> --json number,mergedAt,additions,deletions,files,commits,state
#
# Fields left null (not reconstructable from git/PR history): plan_file_count,
# clarify_rounds, plan_revisions, review_loops.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

require_cmd jq "brew install jq"

skill_sha_default() {
  local sha
  sha=$(git -C "$DIR/.." rev-parse --short HEAD 2>/dev/null)
  [[ -n "$sha" ]] && echo "$sha" || echo "unknown"
}

cmd_extract() {
  local issue_file=${1:?usage: backfill-outcomes.sh extract <issue-json-file> <pr-json-file>}
  local pr_file=${2:?usage: backfill-outcomes.sh extract <issue-json-file> <pr-json-file>}
  [[ -f "$issue_file" ]] || die "issue json file not found: $issue_file"
  [[ -f "$pr_file" ]] || die "PR json file not found: $pr_file"

  jq -nc \
    --slurpfile issue_arr "$issue_file" \
    --slurpfile pr_arr "$pr_file" \
    --arg skill_sha "$(skill_sha_default)" \
    --arg recorded_at "$(date +%F)" \
    '
    ($issue_arr[0]) as $issue |
    ($pr_arr[0]) as $pr |
    (($issue.labels // [])) as $ilabels |
    (($pr.commits // [])) as $commits |
    (($pr.files // [])) as $files |
    (
      if ($pr.additions != null and $pr.deletions != null) then
        ($pr.additions + $pr.deletions)
      elif ($files | length) > 0 then
        ($files | map((.additions // 0) + (.deletions // 0)) | add)
      else
        null
      end
    ) as $diff_loc |
    (
      if (($pr.mergedAt // null) != null) then
        (((($pr.mergedAt | fromdateiso8601) - ($issue.createdAt | fromdateiso8601)) / 3600 * 10 | round) / 10)
      else
        null
      end
    ) as $wall_clock_hours |
    (
      [ $commits[]
        | select( (((.messageHeadline // "") + " " + (.messageBody // "")) | ascii_downcase)
                  | contains("address ci failures") )
      ] | length
    ) as $ci_fixes |
    {
      issue: $issue.number,
      title: $issue.title,
      pr: $pr.number,
      labels: ($ilabels | map(.name) | map(select((startswith("stage:") or startswith("gate:")) | not))),
      outcome: (if (($pr.mergedAt // null) != null) then "merged" else "closed" end),
      plan_file_count: null,
      files_changed: ($files | length),
      diff_loc: $diff_loc,
      commits: ($commits | length),
      clarify_rounds: null,
      plan_revisions: null,
      review_loops: null,
      ci_fixes: $ci_fixes,
      wall_clock_hours: $wall_clock_hours,
      skill_sha: $skill_sha,
      recorded_at: $recorded_at
    }
    ' || die "failed to extract record from $issue_file / $pr_file"
}

# Standard GitHub closing keywords (case-insensitive), grouped by tense.
CLOSING_KEYWORDS="close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved"

cmd_closes_issue() {
  local n=${1:?usage: backfill-outcomes.sh closes-issue <issue-number> (PR body on stdin)}
  [[ "$n" =~ ^[0-9]+$ ]] || die "issue number must be a non-negative integer, got: '$n'"
  local body
  body=$(cat)
  # Match a closing keyword not itself preceded by a letter (so "enclose" or
  # "prefix" don't count as "close"/"fix"), followed by an optional colon and
  # whitespace, then "#<n>" not followed by another digit (so "#42" doesn't
  # match inside "#420"). jq's test() (Oniguruma) supports the lookahead and
  # case-insensitive flag this needs; kept here instead of bash's [[ =~ ]] so
  # the same regex engine is used offline (tests) and against real PR bodies.
  local matched
  matched=$(jq -n --arg body "$body" --arg re "(^|[^A-Za-z])(${CLOSING_KEYWORDS})(:)?\\s+#${n}(?!\\d)" \
    '$body | test($re; "i")') || die "closes-issue: regex match failed"
  [[ "$matched" == "true" ]]
}

cmd_run() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" ]] && dry_run=1

  require_cmd gh "https://cli.github.com"

  local all_issues numbers n
  all_issues=$(gh issue list --state all --limit 1000 --json number,labels,title) || die "gh issue list failed"
  numbers=$(jq -r '.[] | select((.labels // []) | map(.name) | any(startswith("stage:"))) | .number' <<<"$all_issues")

  if [[ -z "$numbers" ]]; then
    info "no issues with a stage:* label found"
    return 0
  fi

  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    info "issue #$n: looking for its merged/closed PR"

    # Cast a wide net with the search API (any PR mentioning "#$n"), then
    # filter to the ones that actually close the issue via a standard GitHub
    # closing keyword (see cmd_closes_issue) — a bare "#$n" mention elsewhere
    # in the body must not count.
    local candidates pr_number=""
    candidates=$(gh pr list --state all --search "#$n in:body" --json number,body 2>/dev/null) || candidates="[]"
    local entry cand_body
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      cand_body=$(jq -r '.body // ""' <<<"$entry")
      if printf '%s' "$cand_body" | cmd_closes_issue "$n"; then
        pr_number=$(jq -r '.number' <<<"$entry")
        break
      fi
    done < <(jq -c '.[]' <<<"$candidates" 2>/dev/null)
    if [[ -z "$pr_number" || "$pr_number" == "null" ]]; then
      warn "issue #$n: no matching PR found, skipping"
      continue
    fi

    local issue_json_file pr_json_file
    issue_json_file=$(mktemp)
    pr_json_file=$(mktemp)

    if ! gh issue view "$n" --json number,title,createdAt,labels >"$issue_json_file" 2>/dev/null; then
      warn "issue #$n: could not fetch issue json, skipping"
      rm -f "$issue_json_file" "$pr_json_file"
      continue
    fi
    if ! gh pr view "$pr_number" --json number,mergedAt,additions,deletions,files,commits,state >"$pr_json_file" 2>/dev/null; then
      warn "issue #$n: could not fetch PR #$pr_number json, skipping"
      rm -f "$issue_json_file" "$pr_json_file"
      continue
    fi

    local pr_state
    pr_state=$(jq -r '.state' "$pr_json_file")
    if [[ "$pr_state" != "MERGED" && "$pr_state" != "CLOSED" ]]; then
      warn "issue #$n: PR #$pr_number is not merged/closed (state=$pr_state), skipping"
      rm -f "$issue_json_file" "$pr_json_file"
      continue
    fi

    local record
    record=$(cmd_extract "$issue_json_file" "$pr_json_file")
    local extract_status=$?
    rm -f "$issue_json_file" "$pr_json_file"
    if [[ $extract_status -ne 0 || -z "$record" ]]; then
      warn "issue #$n: extract failed, skipping"
      continue
    fi

    if [[ $dry_run -eq 1 ]]; then
      echo "$record"
      continue
    fi

    # Convert the record into key=value args for record-outcome.sh, letting
    # it re-derive recorded_at/skill_sha fresh at write time (issue and the
    # two auto-filled fields are excluded here). Labels are joined on "," for
    # record-outcome.sh's labels= convention; per its header comment, a label
    # name containing a comma is not representable this way and will split.
    local args=()
    while IFS= read -r -d '' kv; do
      args+=("$kv")
    done < <(jq -j '
      to_entries
      | map(select(.key != "issue" and .key != "recorded_at" and .key != "skill_sha" and .value != null))
      | map(
          if .key == "labels" then
            "labels=" + ((.value // []) | join(","))
          else
            .key + "=" + (.value | tostring)
          end
        )
      | map(. + "\u0000")
      | add // ""
    ' <<<"$record")

    if ! "$DIR/record-outcome.sh" "$n" "${args[@]}" >/dev/null; then
      warn "issue #$n: record-outcome.sh failed, skipping"
      continue
    fi
    ok "issue #$n: outcome recorded (PR #$pr_number)"
  done <<<"$numbers"
}

cmd=${1:-}
[[ -n "$cmd" ]] || die "usage: backfill-outcomes.sh <extract|closes-issue|run> ..."
shift

case "$cmd" in
  extract) cmd_extract "$@" ;;
  closes-issue) cmd_closes_issue "$@" ;;
  run) cmd_run "$@" ;;
  *) die "unknown subcommand '$cmd' (valid: extract, closes-issue, run)" ;;
esac
