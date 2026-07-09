#!/usr/bin/env bash
# Detects the base branch, fetches, and rebases the current branch onto it.
# On conflict, leaves the rebase in progress and reports the conflicting
# files to stderr — resolving them is a judgement call for the human/agent,
# not this script.
#
# Usage: sync-base.sh
# On success, prints the base branch name (and only that) to stdout.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

require_cmd git "https://git-scm.com/downloads"

base=""

# Prefer the local symbolic-ref: no network call, works the same offline.
base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')

if [[ -z "$base" ]] && command -v gh >/dev/null 2>&1; then
  base=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null)
fi

if [[ -z "$base" ]]; then
  base=$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')
fi

[[ -n "$base" ]] || die "could not determine base branch (checked: origin/HEAD symref, gh repo view, git remote show origin)"

info "base branch: $base"
git fetch origin || die "git fetch origin failed"

if ! git rebase "origin/$base"; then
  err "rebase onto origin/$base failed — conflicting files:"
  git diff --name-only --diff-filter=U >&2
  die "resolve conflicts, then: git rebase --continue (or git rebase --abort)"
fi

echo "$base"
