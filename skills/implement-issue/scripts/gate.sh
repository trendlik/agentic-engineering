#!/usr/bin/env bash
# Local mirror of the (future, server-side) gate check described in the
# skill's roadmap: blocks a phase transition unless the required approval is
# recorded. Fails OPEN (warns, exit 0) whenever it cannot actually verify
# anything — gh/jq missing, or the repo has no GitHub remote — so it never
# blocks solo or offline use of the skill; it only enforces gates it can
# genuinely check.
#
# Not currently wired into WORKFLOW.md's phase transitions (see roadmap) —
# available today for manual/CI use ahead of that wiring.
#
# Usage: gate.sh <issue> <gate>   e.g. gate.sh 42 plan

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

[[ $# -eq 2 ]] || die "usage: gate.sh <issue> <gate>"
number=$1
gate=$2

if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  warn "gh/jq not available -- skipping gate check for '$gate' (nothing enforced)"
  exit 0
fi

if ! gh repo view >/dev/null 2>&1; then
  warn "not a GitHub-backed repo -- skipping gate check for '$gate' (nothing enforced)"
  exit 0
fi

if "$DIR/state.sh" check "$number" "$gate"; then
  ok "gate '$gate' approved for issue #$number"
  exit 0
else
  err "gate '$gate' NOT approved for issue #$number -- run: state.sh approve $number $gate"
  exit 1
fi
