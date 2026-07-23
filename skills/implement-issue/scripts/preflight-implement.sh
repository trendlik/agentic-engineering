#!/usr/bin/env bash
# Local, pre-action hard gate run at the very top of WORKFLOW.md's Phase 3 —
# it blocks the coordinator from spawning the implementation sub-agent unless
# the plan was actually approved. This is what catches a coordinator that
# skipped straight from an issue to implementation without ever running
# Phase 2's approval checkpoint.
#
# Fails OPEN (warn, exit 0) whenever it cannot determine approval state at
# all — gh/jq missing, no GitHub remote, or the issue fetch itself fails —
# so a network blip or offline/non-GitHub use never blocks a legitimate run.
# It fails CLOSED (err, exit 1) only when it can positively confirm the plan
# was NOT approved: the issue fetch succeeded and shows neither the
# gate:plan-approved label nor an "## Implementation Plan" comment.
#
# Complementary to verify-gates.sh, which is the fail-closed CI/merge-time
# check run as a required PR status check — this script is its local,
# pre-implementation counterpart, run by the coordinator itself.
#
# Usage: preflight-implement.sh <issue>

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

[[ $# -eq 1 ]] || die "usage: preflight-implement.sh <issue>"
number=$1

if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  warn "gh/jq not available -- cannot verify plan approval for issue #$number; proceeding (fail-open)"
  exit 0
fi

if ! gh repo view >/dev/null 2>&1; then
  warn "not a GitHub-backed repo -- cannot verify plan approval; proceeding (fail-open)"
  exit 0
fi

# Single explicit fetch so a fetch failure (network blip, no access) is
# distinguishable from genuine absence of the label/comment below. Deliberately
# NOT using find-artifact.sh or `state.sh check` here — both swallow fetch
# errors into "absent", which would wrongly fail-closed on a transient error
# instead of failing open.
json=$(gh issue view "$number" --json labels,comments 2>/dev/null)
if [[ $? -ne 0 ]]; then
  warn "could not fetch issue #$number -- cannot verify plan approval; proceeding (fail-open)"
  exit 0
fi

has_gate=$(jq -r '[.labels[]? | select(.name == "gate:plan-approved")] | length > 0' <<<"$json")
has_plan=$(jq -r '[.comments[]? | select(.body != null and (.body | startswith("## Implementation Plan")))] | length > 0' <<<"$json")

if [[ "$has_gate" == "true" || "$has_plan" == "true" ]]; then
  if [[ "$has_gate" == "true" ]]; then
    ok "plan approved for issue #$number (label) -- proceeding"
  else
    ok "plan approved for issue #$number (artifact) -- proceeding"
  fi
  exit 0
else
  err "plan NOT approved for issue #$number: no gate:plan-approved label and no '## Implementation Plan' comment. Complete Phase 2 (plan approval) before implementing."
  exit 1
fi
