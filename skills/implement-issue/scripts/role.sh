#!/usr/bin/env bash
# Advisory role check: is the person driving this phase the one your team
# assigned to it? Reads ROLES.yml from the TARGET PROJECT's repo root (next
# to CLAUDE.md/AGENTS.md) — NOT from this skill's own directory, since roles
# are per-project, not per-skill. See ROLES.example.yml for the format.
#
# Fails OPEN (exit 0, with a warning) whenever it cannot actually verify
# anything: no ROLES.yml in the project, the current gh user isn't listed in
# it, or gh/jq aren't available. It never blocks solo use or a project that
# hasn't set up roles. This is advisory only, same spirit as gate.sh — real
# enforcement is a future, server-side step; see the skill's roadmap.
#
# Stage -> required role mapping (fixed; matches the analyst / architect /
# developer / QA split described in the skill's roadmap):
#   clarify -> analyst      plan    -> architect
#   implement -> developer  test    -> qa
#   review  -> developer    ci      -> developer
#   done    -> (none)
#
# Usage:
#   role.sh whoami            print the current gh user's assigned role, or
#                              "unassigned" / "no-roles-file"
#   role.sh required <stage>  print the role a stage is owned by (empty for
#                              stages with no assigned owner)
#   role.sh check <stage>     exit 0 if the current user's role matches (or
#                              nothing can be verified); exit 1 on a real
#                              mismatch

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

required_role_for_stage() {
  case "$1" in
    clarify)   echo analyst ;;
    plan)      echo architect ;;
    implement) echo developer ;;
    test)      echo qa ;;
    review)    echo developer ;;
    ci)        echo developer ;;
    done)      echo "" ;;
    *) die "unknown stage '$1' (valid: ${STAGES[*]})" ;;
  esac
}

find_roles_file() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [[ -f "$root/ROLES.yml" ]] || return 1
  echo "$root/ROLES.yml"
}

# Looks up "username: role" in the constrained flat-mapping subset of YAML
# documented in ROLES.example.yml — deliberately not a general YAML parser.
lookup_role() {
  local roles_file=$1 user=$2
  grep -E "^${user}:" "$roles_file" 2>/dev/null \
    | head -n1 \
    | sed -E 's/^[^:]+:[[:space:]]*//' \
    | sed -E 's/[[:space:]]*#.*$//' \
    | tr -d '[:space:]'
}

whoami_cmd() {
  local user roles_file role
  if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "no-roles-file"
    return
  fi
  user=$(gh api user -q .login 2>/dev/null) || { echo "unassigned"; return; }
  roles_file=$(find_roles_file) || { echo "no-roles-file"; return; }
  role=$(lookup_role "$roles_file" "$user")
  echo "${role:-unassigned}"
}

cmd=${1:-}
[[ -n "$cmd" ]] || die "usage: role.sh <whoami|required|check> [stage]"
shift

case "$cmd" in
  whoami)
    whoami_cmd
    ;;

  required)
    stage=${1:?stage required}
    required_role_for_stage "$stage"
    ;;

  check)
    stage=${1:?stage required}
    required=$(required_role_for_stage "$stage")
    if [[ -z "$required" ]]; then
      exit 0
    fi
    current=$(whoami_cmd)
    case "$current" in
      no-roles-file)
        warn "no ROLES.yml found in this project -- role-scoping not enforced"
        exit 0 ;;
      unassigned)
        warn "current gh user has no role assigned in ROLES.yml -- nothing enforced"
        exit 0 ;;
    esac
    if [[ "$current" == "$required" ]]; then
      ok "role '$current' matches required role '$required' for stage '$stage'"
      exit 0
    else
      warn "stage '$stage' is owned by role '$required'; current user is mapped to '$current'"
      exit 1
    fi
    ;;

  *)
    die "unknown subcommand '$cmd' (valid: whoami, required, check)"
    ;;
esac
