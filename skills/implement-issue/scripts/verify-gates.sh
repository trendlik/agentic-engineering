#!/usr/bin/env bash
# CI-enforced gate check — the server-side counterpart to gate.sh/role.sh.
# Those two fail OPEN by design, because they run locally/ad hoc and must
# never block solo use. This script is the opposite on purpose: it's meant
# to run as a REQUIRED status check on a PR in GitHub Actions, and it fails
# CLOSED. It verifies not just that gate:*-approved labels exist on the
# linked issue, but that the specific person who applied each one holds the
# role ROLES.yml assigns to that gate — otherwise anyone with label-write
# access could self-approve their own gate.
#
# Missing ROLES.yml, an unresolvable approver, or a role mismatch are all
# FAILURES here. If a repo doesn't want this enforced, the fix is to not add
# this script's workflow as a required check — not to rely on this script
# being lenient. See templates/implement-issue-gate.yml for the workflow
# that calls this.
#
# Usage: verify-gates.sh <issue-number>
# Requires a `gh`-authenticated token with repo read access (the default
# GITHUB_TOKEN in Actions has this for same-repo issues) and ROLES.yml
# committed at the repo root (see ROLES.example.yml).

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

[[ $# -eq 1 ]] || die "usage: verify-gates.sh <issue-number>"
number=$1
require_cmd git "https://git-scm.com/downloads"
require_cmd gh "https://cli.github.com"
require_cmd jq "brew install jq"

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
roles_file="$root/ROLES.yml"
if [[ ! -f "$roles_file" ]]; then
  err "FAIL  ROLES.yml not found at repo root -- role enforcement cannot run (see ROLES.example.yml)"
  exit 1
fi

lookup_role() {
  local user=$1
  grep -E "^${user}:" "$roles_file" 2>/dev/null \
    | head -n1 \
    | sed -E 's/^[^:]+:[[:space:]]*//' \
    | sed -E 's/[[:space:]]*#.*$//' \
    | tr -d '[:space:]'
}

required_role_for_gate() {
  case "$1" in
    analysis) echo analyst ;;
    plan)     echo architect ;;
    *) die "unknown gate '$1' (valid: ${GATES[*]})" ;;
  esac
}

owner_repo=$(gh repo view --json nameWithOwner -q .nameWithOwner) || die "could not resolve repo"
timeline=$(gh api "repos/$owner_repo/issues/$number/timeline" --paginate) || die "could not fetch issue #$number timeline"

fail=0
for gate in "${GATES[@]}"; do
  required=$(required_role_for_gate "$gate")

  if ! issue_labels "$number" | grep -qx "gate:${gate}-approved"; then
    err "FAIL  gate:${gate}-approved is not set on issue #$number"
    fail=1
    continue
  fi

  actor=$(jq -r --arg label "gate:${gate}-approved" '
    [.[] | select(.event == "labeled" and .label.name == $label)] | last | .actor.login // empty
  ' <<<"$timeline")

  if [[ -z "$actor" ]]; then
    err "FAIL  could not determine who applied gate:${gate}-approved on issue #$number"
    fail=1
    continue
  fi

  role=$(lookup_role "$actor")
  if [[ -z "$role" ]]; then
    err "FAIL  '$actor' (applied gate:${gate}-approved) has no role in ROLES.yml"
    fail=1
  elif [[ "$role" != "$required" ]]; then
    err "FAIL  gate:${gate}-approved was applied by '$actor' (role: $role), but requires role: $required"
    fail=1
  else
    ok "OK    gate:${gate}-approved applied by '$actor' (role: $required), as required"
  fi
done

exit $fail
