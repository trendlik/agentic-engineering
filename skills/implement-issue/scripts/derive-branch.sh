#!/usr/bin/env bash
# Computes the DEFAULT feature branch name for an issue from its labels and
# title: <type>/<number>-<slug>. This is the deterministic fallback the skill
# uses whenever CLAUDE.md/AGENTS.md does not document an explicit branch
# naming convention — that override still requires reading prose and applying
# it, which stays a judgement call for the agent. This script only owns the
# mechanical default so it's testable and identical across machines.
#
# Usage: derive-branch.sh <issue-number>
# Prints the branch name (and only the branch name) to stdout.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

[[ $# -eq 1 ]] || die "usage: derive-branch.sh <issue-number>"
number=$1
require_cmd gh "https://cli.github.com"
require_cmd jq "brew install jq"

json=$(gh issue view "$number" --json title,labels) || die "could not fetch issue #$number"

title=$(jq -r '.title' <<<"$json")
labels=$(jq -r '.labels[].name' <<<"$json" | tr '[:upper:]' '[:lower:]')

# Priority order matches the documented heuristic: fix > feat > chore > docs > else.
if grep -qE '^(bug|fix|defect)$' <<<"$labels"; then
  prefix="fix"
elif grep -qE '^(feature|enhancement|feat)$' <<<"$labels"; then
  prefix="feat"
elif grep -qE '^(chore|maintenance|refactor)$' <<<"$labels"; then
  prefix="chore"
elif grep -qE '^(docs)$' <<<"$labels"; then
  prefix="docs"
else
  prefix="feat"
fi

slug=$(printf '%s' "$title" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g' \
  | sed -E 's/^-+//; s/-+$//' \
  | cut -c1-40 \
  | sed -E 's/-+$//')

if [[ -z "$slug" ]]; then
  echo "issue-$number"
else
  echo "$prefix/$number-$slug"
fi
