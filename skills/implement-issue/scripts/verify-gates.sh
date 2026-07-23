#!/usr/bin/env bash
# CI-enforced gate presence check — the server-side counterpart to gate.sh.
# gate.sh fails OPEN by design, since it runs locally/ad hoc and must never
# block solo use. This script is the opposite on purpose: it's meant to run
# as a REQUIRED status check on a PR in GitHub Actions, and it fails CLOSED.
#
# It checks only that each required gate label (gate:analysis-approved,
# gate:plan-approved) is present on the linked issue — a presence check, not
# an identity check. An earlier version cross-referenced who applied each
# label against a ROLES.yml role mapping; that was dropped — it was
# trivially neutered by one person legitimately holding multiple roles, and
# GitHub's own issue timeline already shows who applied any label in plain
# UI without needing this script's help. If you want to know who approved a
# gate, look at the issue.
#
# Missing gates are a FAILURE here. If a repo doesn't want this enforced,
# the fix is to not add this script's workflow as a required check — not to
# rely on this script being lenient. See templates/implement-issue-gate.yml
# for the workflow that calls this.
#
# Usage: verify-gates.sh <issue-number>
# Requires a `gh`-authenticated token with repo read access (the default
# GITHUB_TOKEN in Actions has this for same-repo issues).

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

[[ $# -eq 1 ]] || die "usage: verify-gates.sh <issue-number>"
number=$1
require_cmd gh "https://cli.github.com"
require_cmd jq "brew install jq"

# If the issue is already marked as stage:done, the gates are implicitly approved
if issue_labels "$number" | grep -qx "stage:done"; then
  ok "OK    issue #$number is already stage:done — gates implicitly approved"
  exit 0
fi

fail=0
for gate in "${GATES[@]}"; do
  if issue_labels "$number" | grep -qx "gate:${gate}-approved"; then
    ok "OK    gate:${gate}-approved is set on issue #$number"
  else
    err "FAIL  gate:${gate}-approved is not set on issue #$number"
    fail=1
  fi
done

exit $fail
