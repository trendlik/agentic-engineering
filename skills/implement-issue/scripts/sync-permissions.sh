#!/usr/bin/env bash
# Installs implement-issue's recommended permission allowlist into a repo's
# .claude/settings.local.json so a run (coordinator AND its sub-agents) stops
# blocking on approval prompts. Idempotent: re-running only appends rules not
# already present and never touches other settings keys.
#
# Why settings.local.json (not settings.json): the rules resolve to absolute,
# machine-specific paths — this skill's own scripts, and this repo's worktree
# tree — so they must not be committed. settings.local.json is git-ignored by
# Claude Code convention, which is the correct home for per-machine config.
#
# What it does NOT add: project-specific commands, which vary per repo and are
# unknowable here — add them yourself (or capture them via the Phase 8
# retrospective into .implement-issue/LEARNINGS.md). That covers build/test
# (e.g. "Bash(npm run *)", "Bash(pytest:*)", "Bash(go test:*)") and, only for
# repos with a Dockerfile, the Phase 4 container smoke test
# ("Bash(docker build:*)", "Bash(docker run:*)"). docker run can mount the host
# filesystem, so it is deliberately not granted to every repo by default.
#
# Caveat: whether Claude Code matches an absolute-path Bash rule
# (Bash(/abs/path/state.sh:*)) depends on its version — verify with
# `/permissions` after syncing. If those don't match, the run still works;
# it just prompts on the coordinator's own script calls.
#
# Usage: sync-permissions.sh [--dry-run]
#
# Env overrides (used by tests):
#   REPO_ROOT      target repo root (default: git rev-parse --show-toplevel)
#   SKILL_DIR      skill dir for script-path rules (default: this script's ../)
#   SETTINGS_FILE  target file (default: $REPO_ROOT/.claude/settings.local.json)
#   TEMPLATE       allowlist template (default: ../templates/settings.allow.json)

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

require_cmd jq "brew install jq"

dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

: "${REPO_ROOT:=$(git rev-parse --show-toplevel 2>/dev/null)}"
[[ -n "$REPO_ROOT" ]] || die "not inside a git repo (and REPO_ROOT not set)"

# Resolve SKILL_DIR to the SAME path the coordinator uses at runtime, so the
# script-path allow rules actually match. SKILL.md resolves it via the symlink
# candidates (e.g. ~/.claude/skills/implement-issue), and bash keeps that
# symlink path verbatim in the command string it runs — so a rule must use the
# symlink path, not the physical checkout $DIR/.. resolves to. Mirror that
# candidate loop here; fall back to this script's own dir only if none match.
if [[ -z "${SKILL_DIR:-}" ]]; then
  for candidate in ~/.claude/skills/implement-issue ~/.gemini/config/skills/implement-issue; do
    [[ -d "$candidate/scripts" ]] && SKILL_DIR="$candidate" && break
  done
  : "${SKILL_DIR:=$(cd "$DIR/.." && pwd)}"
fi
: "${SETTINGS_FILE:=$REPO_ROOT/.claude/settings.local.json}"
: "${TEMPLATE:=$DIR/../templates/settings.allow.json}"
[[ -f "$TEMPLATE" ]] || die "template not found: $TEMPLATE"
jq -e . >/dev/null 2>&1 <"$TEMPLATE" || die "template is not valid JSON: $TEMPLATE"

# Load existing target (or an empty object if it doesn't exist yet).
if [[ -f "$SETTINGS_FILE" ]]; then
  current=$(cat "$SETTINGS_FILE")
  jq -e . >/dev/null 2>&1 <<<"$current" || die "$SETTINGS_FILE is not valid JSON"
else
  current='{}'
fi

# Substitute the placeholders INSIDE jq — paths are passed as --arg, so jq
# treats them as opaque string data and escapes them on output. A path
# containing quotes/brackets therefore stays a literal substring of one rule
# and can never break out to inject an extra allow entry (which text-level
# sed substitution into JSON would allow). Then append only rules not already
# present, leaving existing order and other keys (deny/ask/model/…) untouched.
merged=$(jq \
  --arg skill "$SKILL_DIR" \
  --arg repo "$REPO_ROOT" \
  --slurpfile tmpl "$TEMPLATE" \
  '
  ($tmpl[0].permissions.allow
     | map(gsub("__SKILL_DIR__"; $skill) | gsub("__REPO_ROOT__"; $repo))) as $add
  | .permissions = (.permissions // {})
  | .permissions.allow = (
      (.permissions.allow // []) as $cur
      | $cur + [ $add[] | select( . as $x | ($cur | index($x)) | not ) ]
    )
  ' <<<"$current") || die "failed to build merged settings"

before=$(jq '(.permissions.allow // []) | length' <<<"$current")
after=$(jq '.permissions.allow | length' <<<"$merged")
added=$(( after - before ))

if [[ $dry_run -eq 1 ]]; then
  info "[dry-run] would write $SETTINGS_FILE ($added new rule(s))"
  jq '.permissions.allow' <<<"$merged"
  exit 0
fi

mkdir -p "$(dirname "$SETTINGS_FILE")" || die "could not create $(dirname "$SETTINGS_FILE")"
tmp=$(mktemp) || die "could not create temp file"
jq . <<<"$merged" >"$tmp" || die "failed to write merged settings"
mv "$tmp" "$SETTINGS_FILE" || die "could not write $SETTINGS_FILE"
ok "allowlist synced to $SETTINGS_FILE ($added new rule(s))"
