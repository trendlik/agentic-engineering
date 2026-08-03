#!/usr/bin/env bash
# Tests for lib/resolve-skill-dir.sh — the canonical $SKILL_DIR resolution
# shared by sync-permissions.sh, and drift-guarded against the prose loops in
# skills/implement-issue/SKILL.md and skills/onboard-implement-issue/SKILL.md
# (those two must stay inline for bootstrap reasons — you cannot call
# $SKILL_DIR/scripts/... before $SKILL_DIR is resolved — but their candidate
# ORDER must never drift from the canonical lib).
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# Repo root located from this file's own position in the tree (works from a
# CI checkout too, not just this dev machine): tests/ -> scripts/ ->
# implement-issue/ -> skills/ -> repo root.
REPO_ROOT_REAL="$(cd "$TEST_DIR/../../../.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

LIB="$SCRIPTS_DIR/lib/resolve-skill-dir.sh"

echo "resolve-skill-dir.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A "real" skill dir is any directory with a scripts/ subdirectory.
mkfixture() { mkdir -p "$1/scripts"; }

resolve() { # resolve <repo_root> <home> -- prints resolved path (or nothing on failure)
  local repo_root=$1 home=$2
  ( REPO_ROOT="$repo_root" HOME="$home" bash -c "source '$LIB'; resolve_skill_dir implement-issue" )
}

candidates() { # candidates <repo_root> <home>
  local repo_root=$1 home=$2
  ( REPO_ROOT="$repo_root" HOME="$home" bash -c "source '$LIB'; skill_dir_candidates implement-issue" )
}

# --- case 1: project .claude present -> wins over everything -------------
repo1="$WORK/repo1"; home1="$WORK/home1"
mkfixture "$repo1/.claude/skills/implement-issue"
mkfixture "$repo1/.agents/skills/implement-issue"
mkfixture "$home1/.claude/skills/implement-issue"
mkfixture "$home1/.gemini/config/skills/implement-issue"
assert_eq "$(resolve "$repo1" "$home1")" "$repo1/.claude/skills/implement-issue" \
  "project .claude wins over project .agents and both globals"

# --- case 2: project .agents present, no project .claude -> wins over globals
repo2="$WORK/repo2"; home2="$WORK/home2"
mkfixture "$repo2/.agents/skills/implement-issue"
mkfixture "$home2/.claude/skills/implement-issue"
mkfixture "$home2/.gemini/config/skills/implement-issue"
assert_eq "$(resolve "$repo2" "$home2")" "$repo2/.agents/skills/implement-issue" \
  "project .agents wins over both globals when no project .claude exists"

# --- case 3: no project pins -> global .claude ----------------------------
repo3="$WORK/repo3"; home3="$WORK/home3"
mkdir -p "$repo3"
mkfixture "$home3/.claude/skills/implement-issue"
mkfixture "$home3/.gemini/config/skills/implement-issue"
assert_eq "$(resolve "$repo3" "$home3")" "$home3/.claude/skills/implement-issue" \
  "no project pins -> falls through to global .claude"

# --- case 4: only global .gemini -> resolves to it ------------------------
repo4="$WORK/repo4"; home4="$WORK/home4"
mkdir -p "$repo4"
mkfixture "$home4/.gemini/config/skills/implement-issue"
assert_eq "$(resolve "$repo4" "$home4")" "$home4/.gemini/config/skills/implement-issue" \
  "only global .gemini present -> resolves to it"

# --- case 5: REPO_ROOT="" + non-repo CWD -> global fallback, exit 0, no error output
nonrepo="$WORK/nonrepo"; home5="$WORK/home5"
mkdir -p "$nonrepo"
mkfixture "$home5/.claude/skills/implement-issue"
out5=$(cd "$nonrepo" && REPO_ROOT="" HOME="$home5" bash -c "source '$LIB'; resolve_skill_dir implement-issue" 2>"$WORK/stderr5")
rc5=$?
assert_eq "$out5" "$home5/.claude/skills/implement-issue" \
  "empty REPO_ROOT + non-repo CWD degrades cleanly to global fallback"
assert_eq "$rc5" "0" "degraded resolution still exits 0"
assert_eq "$(cat "$WORK/stderr5")" "" "no error output on the not-a-repo path"
cand5=$(cd "$nonrepo" && REPO_ROOT="" HOME="$home5" bash -c "source '$LIB'; skill_dir_candidates implement-issue")
assert_eq "$(printf '%s\n' "$cand5" | wc -l | tr -d ' ')" "2" \
  "not-a-repo candidate list contains only the two global candidates"

# --- case 6: a candidate dir exists but has no scripts/ subdir -> skipped -
repo6="$WORK/repo6"; home6="$WORK/home6"
mkdir -p "$repo6/.claude/skills/implement-issue"   # exists, but no scripts/ inside
mkfixture "$home6/.claude/skills/implement-issue"
assert_eq "$(resolve "$repo6" "$home6")" "$home6/.claude/skills/implement-issue" \
  "a candidate directory without a scripts/ subdir is skipped, not selected"

# --- drift guard: canonical lib vs. both prose loops ----------------------
# Extracts the resolution block from each source, then normalizes it to an
# ordered token sequence of the four known candidate shapes so reformatting
# (whitespace, array-vs-list form, ~ vs $HOME) is tolerated and only
# reordering or removal fails the comparison.

extract_block_skillmd() { # extract_block_skillmd <file> -- the inline candidate loop
  awk '/^_repo_root=/{flag=1} flag{print} /^done$/{if(flag) exit}' "$1"
}

extract_block_lib() { # extract_block_lib <file> -- the skill_dir_candidates() body
  awk '/^skill_dir_candidates\(\)/{flag=1} flag{print} flag && /^}/{exit}' "$1"
}

normalize_block() { # normalize_block <<< block-text -- ordered token sequence on stdout
  grep -oE '(\$\{?_?repo_root\}?|\$\{?REPO_ROOT\}?|~|\$HOME)[^ "'"'"'()]*\.(claude|agents|gemini/config)/skills/[^ "'"'"')]*' \
    | while IFS= read -r tok; do
        case "$tok" in
          *repo_root*.claude/skills/*|*REPO_ROOT*.claude/skills/*) echo "project-claude" ;;
          *repo_root*.agents/skills/*|*REPO_ROOT*.agents/skills/*) echo "project-agents" ;;
          "~"*.claude/skills/*|*HOME*.claude/skills/*) echo "global-claude" ;;
          "~"*.gemini/config/skills/*|*HOME*.gemini/config/skills/*) echo "global-gemini" ;;
          *) echo "UNKNOWN:$tok" ;;
        esac
      done
}

seq_lib=$(extract_block_lib "$SCRIPTS_DIR/lib/resolve-skill-dir.sh" | normalize_block)
seq_main=$(extract_block_skillmd "$REPO_ROOT_REAL/skills/implement-issue/SKILL.md" | normalize_block)
seq_onboard=$(extract_block_skillmd "$REPO_ROOT_REAL/skills/onboard-implement-issue/SKILL.md" | normalize_block)

expected_seq=$'project-claude\nproject-agents\nglobal-claude\nglobal-gemini'

assert_eq "$seq_lib" "$expected_seq" \
  "lib/resolve-skill-dir.sh candidate order is project-claude, project-agents, global-claude, global-gemini"
assert_eq "$seq_main" "$expected_seq" \
  "implement-issue/SKILL.md prose loop order matches the canonical lib"
assert_eq "$seq_onboard" "$expected_seq" \
  "onboard-implement-issue/SKILL.md prose loop order matches the canonical lib"
assert_eq "$seq_main" "$seq_lib" \
  "implement-issue/SKILL.md prose loop has not drifted from the canonical lib"
assert_eq "$seq_onboard" "$seq_lib" \
  "onboard-implement-issue/SKILL.md prose loop has not drifted from the canonical lib"

echo "resolve-skill-dir.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
