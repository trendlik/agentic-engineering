#!/usr/bin/env bash
# Shared helpers for implement-issue scripts. Sourced, not executed directly.
#
# Defines the stage/gate label taxonomy used across state.sh and gate.sh:
#   stage:<name>          — the phase currently in flight for an issue
#                            (clarify, plan, implement, test, review, ci, done)
#   gate:<name>-approved  — a recorded approval that unblocks the next phase
#                            (analysis, plan)

set -uo pipefail

STAGES=(clarify plan implement test review ci done)
GATES=(analysis plan)

_color() { local code=$1; shift; printf '\033[%sm%s\033[0m\n' "$code" "$*"; }
info()  { _color '0;36' "$*" >&2; }
ok()    { _color '0;32' "$*" >&2; }
warn()  { _color '0;33' "$*" >&2; }
err()   { _color '0;31' "$*" >&2; }

die() { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1 (install: $2)"
}

is_valid_stage() {
  local s=$1 x
  for x in "${STAGES[@]}"; do [[ "$x" == "$s" ]] && return 0; done
  return 1
}

is_valid_gate() {
  local g=$1 x
  for x in "${GATES[@]}"; do [[ "$x" == "$g" ]] && return 0; done
  return 1
}

# Prints all label names on an issue, one per line.
issue_labels() {
  local number=$1
  gh issue view "$number" --json labels -q '.labels[].name' 2>/dev/null
}

# Idempotently ensures a label exists in the repo (creates it, or updates
# color/description if it already exists).
ensure_label() {
  local name=$1 color=$2 desc=$3
  gh label create "$name" --color "$color" --description "$desc" --force >/dev/null 2>&1
}

# CSV membership test for ROLES.yml values, which may list more than one
# role for a single person (e.g. "analyst,architect" for someone covering
# multiple hats — see ROLES.example.yml). Empty $1 never matches anything.
has_role() {
  local roles_csv=$1 target=$2
  [[ -n "$roles_csv" && ",${roles_csv}," == *",${target},"* ]]
}
