#!/usr/bin/env bash
# Finds the most recent issue comment that is a persisted workflow artifact —
# the Phase 1 clarification summary or the Phase 2 approved plan — so a
# resuming session (Phase 0) can load what a previous session already
# decided instead of re-deriving or re-asking for it.
#
# Usage: find-artifact.sh <issue-number> <heading>
#   e.g. find-artifact.sh 42 "Clarification Summary"
#        find-artifact.sh 42 "Implementation Plan"
#
# Prints the full body of the latest matching comment to stdout. Exits 1 with
# nothing printed if no comment starts with "## <heading>".

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

[[ $# -eq 2 ]] || die "usage: find-artifact.sh <issue-number> <heading>"
number=$1
heading=$2
require_cmd gh "https://cli.github.com"
require_cmd jq "brew install jq"

json=$(gh issue view "$number" --json comments) || die "could not fetch issue #$number"

body=$(jq -r --arg h "## $heading" '
  [.comments[]? | select(.body != null and (.body | startswith($h)))]
  | if length == 0 then "" else last.body end
' <<<"$json")

if [[ -z "$body" ]]; then
  err "no comment found on issue #$number starting with '## $heading'"
  exit 1
fi

printf '%s\n' "$body"
