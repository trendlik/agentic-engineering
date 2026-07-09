#!/usr/bin/env bash
# Single source of truth for an issue's workflow stage and approval gates,
# persisted as GitHub labels so any machine, any person, and any LLM adapter
# reads the same state. See ../WORKFLOW.md for what each stage/gate means.
#
# Labels used (see lib/common.sh for the canonical list):
#   stage:<name>          e.g. stage:plan
#   gate:<name>-approved  e.g. gate:plan-approved
#
# Usage:
#   state.sh init <issue>              create the label set in this repo if
#                                       missing; set stage:clarify if the
#                                       issue has no stage:* label yet
#   state.sh get <issue>                print current stage, or "none"
#   state.sh set <issue> <stage>        move the issue to <stage>
#   state.sh approve <issue> <gate>     record a gate approval (analysis|plan)
#   state.sh check <issue> <gate>       exit 0 if <gate> is approved, else 1
#   state.sh labels <issue>             debug: list all labels on the issue

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

require_cmd gh "https://cli.github.com"
require_cmd jq "brew install jq"

STAGE_COLOR="0366d6"
GATE_COLOR="2ea44f"

current_stage() {
  local number=$1
  issue_labels "$number" | grep -E '^stage:' | sed 's/^stage://' | head -n1
}

cmd=${1:-}
[[ -n "$cmd" ]] || die "usage: state.sh <init|get|set|approve|check|labels> <issue> [value]"
shift

case "$cmd" in
  init)
    number=${1:?issue number required}
    for s in "${STAGES[@]}"; do ensure_label "stage:$s" "$STAGE_COLOR" "implement-issue stage: $s"; done
    for g in "${GATES[@]}"; do ensure_label "gate:${g}-approved" "$GATE_COLOR" "implement-issue gate: $g approved"; done
    existing=$(current_stage "$number")
    if [[ -z "$existing" ]]; then
      gh issue edit "$number" --add-label "stage:clarify" >/dev/null || die "failed to set initial stage"
      ok "issue #$number initialized at stage:clarify"
    else
      info "issue #$number already at stage:$existing"
    fi
    ;;

  get)
    number=${1:?issue number required}
    s=$(current_stage "$number")
    echo "${s:-none}"
    ;;

  set)
    number=${1:?issue number required}
    stage=${2:?stage required}
    is_valid_stage "$stage" || die "unknown stage '$stage' (valid: ${STAGES[*]})"
    ensure_label "stage:$stage" "$STAGE_COLOR" "implement-issue stage: $stage"
    existing=$(current_stage "$number")
    if [[ -n "$existing" && "$existing" != "$stage" ]]; then
      gh issue edit "$number" --remove-label "stage:$existing" >/dev/null 2>&1 \
        || warn "could not remove stale label stage:$existing (continuing)"
    fi
    gh issue edit "$number" --add-label "stage:$stage" >/dev/null || die "failed to set stage:$stage"
    ok "issue #$number -> stage:$stage"
    ;;

  approve)
    number=${1:?issue number required}
    gate=${2:?gate required}
    is_valid_gate "$gate" || die "unknown gate '$gate' (valid: ${GATES[*]})"
    ensure_label "gate:${gate}-approved" "$GATE_COLOR" "implement-issue gate: $gate approved"
    gh issue edit "$number" --add-label "gate:${gate}-approved" >/dev/null || die "failed to record approval"
    ok "issue #$number: gate:${gate}-approved recorded"
    ;;

  check)
    number=${1:?issue number required}
    gate=${2:?gate required}
    is_valid_gate "$gate" || die "unknown gate '$gate' (valid: ${GATES[*]})"
    if issue_labels "$number" | grep -qx "gate:${gate}-approved"; then
      exit 0
    else
      exit 1
    fi
    ;;

  labels)
    number=${1:?issue number required}
    issue_labels "$number"
    ;;

  *)
    die "unknown subcommand '$cmd' (valid: init, get, set, approve, check, labels)"
    ;;
esac
