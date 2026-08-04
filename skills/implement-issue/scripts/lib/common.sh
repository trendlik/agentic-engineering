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

# Returns true if dir is either a git repository top-level root or belongs
# to the skill repo (via remote URL check).
is_skill_repo() {
  local dir=$1
  local dir_abs toplevel remote_url
  dir_abs=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  if [[ "$dir_abs" == "$toplevel" ]]; then
    return 0
  fi
  remote_url=$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)
  if [[ "$remote_url" == *"agentic-engineering"* ]]; then
    return 0
  fi
  return 1
}

# Returns the skill's short git commit SHA if skill_dir is inside the skill repo or a git root,
# or "unknown" otherwise.
skill_sha_default() {
  local skill_dir="${1:-${DIR:-}/..}"
  if is_skill_repo "$skill_dir"; then
    local sha
    sha=$(git -C "$skill_dir" rev-parse --short HEAD 2>/dev/null || true)
    if [[ -n "$sha" ]]; then
      echo "$sha"
      return 0
    fi
  fi
  echo "unknown"
}

# Returns the skill's version from SKILL.md frontmatter (^version: ...),
# or "unknown" if missing or unparseable.
skill_version_default() {
  local skill_dir="${1:-${DIR:-}/..}"
  if [[ -f "$skill_dir/SKILL.md" ]]; then
    local ver
    ver=$(sed -n -E 's/^[[:space:]]*version:[[:space:]]*["'\'']?([^"'\''[:space:]]+)["'\'']?.*/\1/p' "$skill_dir/SKILL.md" | head -n 1)
    if [[ -n "$ver" ]]; then
      echo "$ver"
      return 0
    fi
  fi
  echo "unknown"
}

