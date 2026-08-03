#!/usr/bin/env bash
# Canonical $SKILL_DIR resolution for implement-issue. Sourced, not executed.
#
# A project can pin a specific released version of this skill by placing a
# symlink at its own .claude/skills/<skill> (Claude Code) or
# .agents/skills/<skill> (Antigravity) pointing into the release store.
# Workspace-scoped discovery outranks global discovery on both adapters, so
# resolution must probe the project paths before the global ones — a pinned
# project's scripts must come from the SAME symlink its prose was resolved
# against, not whatever the global symlink happens to point at.
#
# Candidate order (first match wins):
#   1. <repo-root>/.claude/skills/<skill>   (Claude Code, per-project pin)
#   2. <repo-root>/.agents/skills/<skill>   (Antigravity, per-project pin)
#   3. ~/.claude/skills/<skill>             (Claude Code, global default)
#   4. ~/.gemini/config/skills/<skill>      (Antigravity, global default)
#
# Outside a git repo (no repo root resolvable), the project candidates are
# skipped entirely and resolution degrades cleanly to the global fallback.
#
# Constraint: paths are built from $HOME/$REPO_ROOT and returned VERBATIM —
# no readlink/realpath. Bash follows a symlinked directory transparently, and
# a resolved allowlist rule must match the symlink path a script was actually
# invoked through, not the physical directory it points at.
#
# Seams (testability): REPO_ROOT and HOME are the only inputs beyond the
# filesystem, both env vars — a test injects them directly, no mocking or
# git stubbing needed. Neither function mutates anything; resolve_skill_dir
# only stats directories.

set -uo pipefail

# Prints the ordered candidate paths for <skill>, one per line.
skill_dir_candidates() {
  local skill=${1:-implement-issue} repo_root
  repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  local candidates=()
  [[ -n "$repo_root" ]] && candidates+=(
    "$repo_root/.claude/skills/$skill"
    "$repo_root/.agents/skills/$skill"
  )
  candidates+=(
    "$HOME/.claude/skills/$skill"
    "$HOME/.gemini/config/skills/$skill"
  )
  printf '%s\n' "${candidates[@]}"
}

# Prints the first candidate that has a scripts/ subdirectory; returns 1 if
# none of the candidates qualify.
resolve_skill_dir() {
  local skill=${1:-implement-issue} candidate
  while IFS= read -r candidate; do
    if [[ -d "$candidate/scripts" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(skill_dir_candidates "$skill")
  return 1
}
