#!/usr/bin/env bash
# Tests for release.sh, run against throwaway temp git repos (see run-tests.sh
# for harness setup; this file is also runnable standalone). Never touches
# the real repo, the real ~/.agents/releases store, or real GitHub.
#
# Each test "family" is a temp bare repo (standing in for GitHub/origin) plus
# a clone of it (standing in for the checkout release.sh is run from), so the
# fetch + push path is exercised end-to-end without any network access.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

RELEASE="$ROOT_DIR/release.sh"

WORK_DIR=$(mktemp -d)
cleanup() {
  # chmod -R a-w snapshots would otherwise make rm -rf fail partway through.
  chmod -R u+w "$WORK_DIR" 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Sets up a fresh "$1/bare" (bare repo, stands in for origin) and "$1/clone"
# (a clone of it, stands in for the checkout release.sh runs from), with a
# single committed-and-pushed skills/implement-issue/SKILL.md whose version
# frontmatter is "$2" (verbatim, so callers can also pass a missing/malformed
# value -- an empty string omits the version: line entirely).
setup_family() {
  local family=$1 version_line=$2 extra_body=${3:-} skill_name=${4:-implement-issue} clone
  clone="$family/clone"
  mkdir -p "$family"
  git init -q --bare "$family/bare"
  git clone -q "$family/bare" "$clone" 2>/dev/null
  git -C "$clone" config user.email test@example.com
  git -C "$clone" config user.name "Test"
  mkdir -p "$clone/skills/$skill_name"
  write_skill_md "$clone" "$version_line" "$extra_body" "$skill_name"
  git -C "$clone" add -A
  git -C "$clone" commit -q -m "init"
  git -C "$clone" push -q origin HEAD
}

# extra_body (optional) is appended as an extra line after the fixture's
# heading -- used to plant a decoy "version:"-looking line in the PROSE BODY,
# outside the frontmatter block, to prove release.sh never picks it up.
write_skill_md() {
  local clone=$1 version_line=$2 extra_body=${3:-} skill_name=${4:-implement-issue}
  {
    echo "---"
    echo "name: $skill_name"
    echo "description: test fixture"
    [[ -n "$version_line" ]] && echo "$version_line"
    echo "---"
    echo "# $skill_name (test fixture)"
    [[ -n "$extra_body" ]] && echo "$extra_body"
  } > "$clone/skills/$skill_name/SKILL.md"
}

# Commits the clone's current skills/implement-issue/SKILL.md and pushes it
# to origin -- i.e. this is what "the canonical version" moving forward looks
# like, as opposed to just editing the working tree.
commit_and_push() {
  local clone=$1 msg=$2
  git -C "$clone" commit -aqm "$msg"
  git -C "$clone" push -q origin HEAD
}

run_release() {
  local clone=$1 store=$2; shift 2
  env SKILL_NAME=implement-issue REPO_ROOT="$clone" RELEASE_STORE="$store" "$RELEASE" "$@"
}

run_release_skill() {
  local skill=$1 clone=$2 store=$3; shift 3
  env SKILL_NAME="$skill" REPO_ROOT="$clone" RELEASE_STORE="$store" "$RELEASE" "$@"
}

echo "release.sh"

# --- (a) happy path: first release of a version succeeds, is pushed to
#         origin, and is complete ---
FAM_A="$WORK_DIR/fam-a"
BARE_A="$FAM_A/bare"
CLONE_A="$FAM_A/clone"
STORE_A="$WORK_DIR/store-a"
setup_family "$FAM_A" "version: 1.0.0"
assert_success "first release of a version exits 0" run_release "$CLONE_A" "$STORE_A"
assert_success "archived SKILL.md exists in the release dir" \
  bash -c "[[ -f '$STORE_A/implement-issue/1.0.0/SKILL.md' ]]"
assert_success "archived SKILL.md carries the released version" \
  bash -c "grep -q '^version: 1.0.0\$' '$STORE_A/implement-issue/1.0.0/SKILL.md'"
assert_success "scoped git tag was created locally" \
  git -C "$CLONE_A" rev-parse -q --verify refs/tags/implement-issue/v1.0.0
assert_success "scoped git tag was pushed to origin (the bare repo)" \
  bash -c "git -C '$BARE_A' tag | grep -qx 'implement-issue/v1.0.0'"

# --- (b) the released snapshot is read-only ---
assert_failure "cannot create a new file inside a released snapshot" \
  bash -c "echo x > '$STORE_A/implement-issue/1.0.0/newfile'"
assert_failure "cannot modify a file inside a released snapshot" \
  bash -c "echo x >> '$STORE_A/implement-issue/1.0.0/SKILL.md'"

# --- (c) second run for the same version refuses (immutability) ---
assert_failure "refuses to overwrite an already-released version" run_release "$CLONE_A" "$STORE_A"

# --- (d) KEY REGRESSION TEST: the version released is the one committed and
#         pushed to origin, NOT whatever is dirty in the local working tree.
#         Bump to 2.0.0 for real (commit + push), then dirty the working tree
#         to a third, never-committed version (9.9.9) and release again --
#         the release must be 2.0.0, and 9.9.9 must never appear anywhere. ---
write_skill_md "$CLONE_A" "version: 2.0.0"
commit_and_push "$CLONE_A" "bump to 2.0.0"
write_skill_md "$CLONE_A" "version: 9.9.9"  # uncommitted -- never pushed
assert_success "release succeeds while the working tree is dirty" run_release "$CLONE_A" "$STORE_A"
assert_success "the PUSHED version (2.0.0) was released" \
  bash -c "[[ -f '$STORE_A/implement-issue/2.0.0/SKILL.md' ]]"
assert_failure "the DIRTY working-tree version (9.9.9) was NOT released" \
  bash -c "[[ -e '$STORE_A/implement-issue/9.9.9' ]]"
assert_failure "no tag was created for the dirty, uncommitted version" \
  git -C "$CLONE_A" rev-parse -q --verify refs/tags/implement-issue/v9.9.9
git -C "$CLONE_A" checkout -q -- skills/implement-issue/SKILL.md  # clean up the dirty state

# --- (e) --dry-run is a no-op: no tag, no push, no release dir ---
FAM_E="$WORK_DIR/fam-e"
BARE_E="$FAM_E/bare"
CLONE_E="$FAM_E/clone"
STORE_E="$WORK_DIR/store-e"
setup_family "$FAM_E" "version: 3.0.0"
assert_success "--dry-run exits 0" run_release "$CLONE_E" "$STORE_E" --dry-run
assert_failure "--dry-run does not create the release directory" \
  bash -c "[[ -e '$STORE_E/implement-issue/3.0.0' ]]"
assert_failure "--dry-run does not create the git tag locally" \
  git -C "$CLONE_E" rev-parse -q --verify refs/tags/implement-issue/v3.0.0
assert_failure "--dry-run does not push anything to origin" \
  bash -c "[[ -n \$(git -C '$BARE_E' tag) ]]"

# --- (f) missing version field errors before any mutation ---
FAM_F="$WORK_DIR/fam-f"
CLONE_F="$FAM_F/clone"
STORE_F="$WORK_DIR/store-f"
setup_family "$FAM_F" ""
assert_failure "errors when SKILL.md has no version field" run_release "$CLONE_F" "$STORE_F"
assert_failure "no release store created on missing-version error" \
  bash -c "[[ -e '$STORE_F' ]]"

# --- (g) malformed version errors before any mutation ---
FAM_G="$WORK_DIR/fam-g"
CLONE_G="$FAM_G/clone"
STORE_G="$WORK_DIR/store-g"
setup_family "$FAM_G" "version: 1.0"
assert_failure "errors when version is not full semver (X.Y.Z)" run_release "$CLONE_G" "$STORE_G"
assert_failure "no release store created on malformed-version error" \
  bash -c "[[ -e '$STORE_G' ]]"

FAM_G2="$WORK_DIR/fam-g2"
CLONE_G2="$FAM_G2/clone"
STORE_G2="$WORK_DIR/store-g2"
setup_family "$FAM_G2" "version: not-a-version"
assert_failure "errors when version is non-numeric garbage" run_release "$CLONE_G2" "$STORE_G2"

# --- (h) a pre-existing tag that already points at the released commit is
#         reused, not re-created or errored on ---
FAM_H="$WORK_DIR/fam-h"
BARE_H="$FAM_H/bare"
CLONE_H="$FAM_H/clone"
STORE_H="$WORK_DIR/store-h"
setup_family "$FAM_H" "version: 5.0.0"
git -C "$CLONE_H" tag -a implement-issue/v5.0.0 -m "pre-existing, correct tag" HEAD >/dev/null
git -C "$CLONE_H" push -q origin implement-issue/v5.0.0
assert_success "release succeeds when a matching tag already exists" run_release "$CLONE_H" "$STORE_H"
assert_success "release directory was populated from the reused tag" \
  bash -c "[[ -f '$STORE_H/implement-issue/5.0.0/SKILL.md' ]]"

# --- (i) a pre-existing tag that points at a DIFFERENT commit than the
#         version being released is an error -- never move an existing tag ---
FAM_I="$WORK_DIR/fam-i"
CLONE_I="$FAM_I/clone"
STORE_I="$WORK_DIR/store-i"
setup_family "$FAM_I" "version: 0.0.1"
decoy_sha=$(git -C "$CLONE_I" rev-parse HEAD)
write_skill_md "$CLONE_I" "version: 6.0.0"
commit_and_push "$CLONE_I" "bump to 6.0.0"
git -C "$CLONE_I" tag -a implement-issue/v6.0.0 -m "wrong commit" "$decoy_sha" >/dev/null
assert_failure "errors when the tag exists but points at a different commit" \
  run_release "$CLONE_I" "$STORE_I"
assert_failure "no release directory created on tag-conflict error" \
  bash -c "[[ -e '$STORE_I/implement-issue/6.0.0' ]]"

# --- (j) missing parent directories under RELEASE_STORE are created ---
FAM_J="$WORK_DIR/fam-j"
CLONE_J="$FAM_J/clone"
STORE_J="$WORK_DIR/store-j/does/not/exist/yet"
setup_family "$FAM_J" "version: 7.0.0"
assert_success "creates missing RELEASE_STORE parent directories" run_release "$CLONE_J" "$STORE_J"
assert_success "release directory exists under the newly-created parents" \
  bash -c "[[ -f '$STORE_J/implement-issue/7.0.0/SKILL.md' ]]"

# --- (k) basic usage error ---
FAM_K="$WORK_DIR/fam-k"
CLONE_K="$FAM_K/clone"
STORE_K="$WORK_DIR/store-k"
setup_family "$FAM_K" "version: 1.0.0"
assert_failure "errors on an unrecognized flag" run_release "$CLONE_K" "$STORE_K" --bogus-flag

# --- (l) a stray "version:"-looking line in the skill's PROSE BODY (after the
#         frontmatter's closing "---") must never be picked up -- only the
#         version field inside the FIRST frontmatter block counts. This
#         guards the awk two-delimiter extraction described in release.sh's
#         own comments. ---
FAM_L="$WORK_DIR/fam-l"
CLONE_L="$FAM_L/clone"
STORE_L="$WORK_DIR/store-l"
setup_family "$FAM_L" "version: 1.2.3" "Mentions a decoy in prose: version: 9.9.9"
assert_success "release succeeds with a decoy 'version:' mention in the body" \
  run_release "$CLONE_L" "$STORE_L"
assert_success "the FRONTMATTER version (1.2.3) was released" \
  bash -c "[[ -f '$STORE_L/implement-issue/1.2.3/SKILL.md' ]]"
assert_failure "the body decoy version (9.9.9) was NOT released" \
  bash -c "[[ -e '$STORE_L/implement-issue/9.9.9' ]]"

# --- (m) a quoted version value (YAML-style "1.2.3" or '1.2.3') has its
#         quotes stripped by release.sh, per its own quote-stripping sed step ---
FAM_M="$WORK_DIR/fam-m"
CLONE_M="$FAM_M/clone"
STORE_M="$WORK_DIR/store-m"
setup_family "$FAM_M" 'version: "4.5.6"'
assert_success "release succeeds with a double-quoted version value" \
  run_release "$CLONE_M" "$STORE_M"
assert_success "quotes are stripped from the released version directory name" \
  bash -c "[[ -f '$STORE_M/implement-issue/4.5.6/SKILL.md' ]]"

# --- (n) SKILL.md entirely absent at REF -- distinct from case (f), where
#         SKILL.md exists but has no version: field. Here the
#         `git show REF:skills/<skill>/SKILL.md` itself fails because no
#         SKILL.md was ever committed. ---
FAM_N="$WORK_DIR/fam-n"
BARE_N="$FAM_N/bare"
CLONE_N="$FAM_N/clone"
STORE_N="$WORK_DIR/store-n"
mkdir -p "$FAM_N"
git init -q --bare "$BARE_N"
git clone -q "$BARE_N" "$CLONE_N" 2>/dev/null
git -C "$CLONE_N" config user.email test@example.com
git -C "$CLONE_N" config user.name "Test"
mkdir -p "$CLONE_N/skills/implement-issue"
echo "no SKILL.md here" > "$CLONE_N/skills/implement-issue/.gitkeep"
git -C "$CLONE_N" add -A
git -C "$CLONE_N" commit -q -m "init (no SKILL.md committed)"
git -C "$CLONE_N" push -q origin HEAD
assert_failure "errors when SKILL.md is entirely absent at REF" run_release "$CLONE_N" "$STORE_N"
assert_failure "no release store created when SKILL.md is absent" \
  bash -c "[[ -e '$STORE_N' ]]"

# --- (o) --dry-run still performs validation, not just a happy-path preview:
#         it must die when DEST already exists (the immutability guard runs
#         before the dry-run early-exit). ---
FAM_O="$WORK_DIR/fam-o"
CLONE_O="$FAM_O/clone"
STORE_O="$WORK_DIR/store-o"
setup_family "$FAM_O" "version: 8.0.0"
assert_success "real release (setup for dry-run-vs-existing-DEST case)" run_release "$CLONE_O" "$STORE_O"
assert_failure "--dry-run dies when DEST already exists" run_release "$CLONE_O" "$STORE_O" --dry-run

# --- (p) --dry-run still performs validation: it must die when the tag
#         already exists pointing at a different commit than the version
#         being released (never silently preview past a tag conflict). ---
FAM_P="$WORK_DIR/fam-p"
CLONE_P="$FAM_P/clone"
STORE_P="$WORK_DIR/store-p"
setup_family "$FAM_P" "version: 0.0.2"
decoy_sha_p=$(git -C "$CLONE_P" rev-parse HEAD)
write_skill_md "$CLONE_P" "version: 9.0.0"
commit_and_push "$CLONE_P" "bump to 9.0.0"
git -C "$CLONE_P" tag -a implement-issue/v9.0.0 -m "wrong commit" "$decoy_sha_p" >/dev/null
assert_failure "--dry-run dies when tag exists but points at a different commit" \
  run_release "$CLONE_P" "$STORE_P" --dry-run
assert_failure "--dry-run (tag conflict) creates no release directory" \
  bash -c "[[ -e '$STORE_P/implement-issue/9.0.0' ]]"

# --- (q) releases onboard-implement-issue when SKILL_NAME=onboard-implement-issue ---
FAM_Q="$WORK_DIR/fam-q"
BARE_Q="$FAM_Q/bare"
CLONE_Q="$FAM_Q/clone"
STORE_Q="$WORK_DIR/store-q"
setup_family "$FAM_Q" "version: 1.0.0" "" "onboard-implement-issue"
assert_success "release onboard-implement-issue exits 0" \
  run_release_skill "onboard-implement-issue" "$CLONE_Q" "$STORE_Q"
assert_success "archived SKILL.md exists in the release dir for onboard-implement-issue" \
  bash -c "[[ -f '$STORE_Q/onboard-implement-issue/1.0.0/SKILL.md' ]]"
assert_success "archived SKILL.md carries the released version for onboard-implement-issue" \
  bash -c "grep -q '^version: 1.0.0\$' '$STORE_Q/onboard-implement-issue/1.0.0/SKILL.md'"
assert_success "scoped git tag was created locally for onboard-implement-issue" \
  git -C "$CLONE_Q" rev-parse -q --verify refs/tags/onboard-implement-issue/v1.0.0
assert_success "scoped git tag was pushed to origin for onboard-implement-issue" \
  bash -c "git -C '$BARE_Q' tag | grep -qx 'onboard-implement-issue/v1.0.0'"
assert_failure "refuses to overwrite an already-released version of onboard-implement-issue" \
  run_release_skill "onboard-implement-issue" "$CLONE_Q" "$STORE_Q"

# --- (r) --dry-run for onboard-implement-issue ---
FAM_R="$WORK_DIR/fam-r"
CLONE_R="$FAM_R/clone"
STORE_R="$WORK_DIR/store-r"
setup_family "$FAM_R" "version: 1.0.0" "" "onboard-implement-issue"
assert_success "--dry-run for onboard-implement-issue exits 0" \
  run_release_skill "onboard-implement-issue" "$CLONE_R" "$STORE_R" --dry-run
assert_failure "--dry-run for onboard-implement-issue does not create release directory" \
  bash -c "[[ -e '$STORE_R/onboard-implement-issue/1.0.0' ]]"
assert_failure "--dry-run for onboard-implement-issue does not create git tag" \
  git -C "$CLONE_R" rev-parse -q --verify refs/tags/onboard-implement-issue/v1.0.0

# --- (s) dirty working tree release for onboard-implement-issue releases pushed version ---
write_skill_md "$CLONE_Q" "version: 2.0.0" "" "onboard-implement-issue"
commit_and_push "$CLONE_Q" "bump onboard-implement-issue to 2.0.0"
write_skill_md "$CLONE_Q" "version: 9.9.9" "" "onboard-implement-issue"
assert_success "release onboard-implement-issue succeeds while working tree is dirty" \
  run_release_skill "onboard-implement-issue" "$CLONE_Q" "$STORE_Q"
assert_success "the PUSHED version of onboard-implement-issue (2.0.0) was released" \
  bash -c "[[ -f '$STORE_Q/onboard-implement-issue/2.0.0/SKILL.md' ]]"
assert_failure "the DIRTY version of onboard-implement-issue (9.9.9) was NOT released" \
  bash -c "[[ -e '$STORE_Q/onboard-implement-issue/9.9.9' ]]"
git -C "$CLONE_Q" checkout -q -- skills/onboard-implement-issue/SKILL.md

# --- (t) invalid SKILL_NAME rejected ---
FAM_T="$WORK_DIR/fam-t"
CLONE_T="$FAM_T/clone"
STORE_T="$WORK_DIR/store-t"
setup_family "$FAM_T" "version: 1.0.0"
assert_failure "rejects SKILL_NAME containing path traversal ('..')" \
  run_release_skill "../invalid" "$CLONE_T" "$STORE_T"
assert_failure "rejects non-existent SKILL_NAME" \
  run_release_skill "nonexistent-skill" "$CLONE_T" "$STORE_T"

# --- (u) verify actual repository skill files have valid version frontmatter ---
assert_success "skills/onboard-implement-issue/SKILL.md in repo has valid semver version" \
  bash -c "grep -q '^version: [0-9]\+\.[0-9]\+\.[0-9]\+\$' '$ROOT_DIR/skills/onboard-implement-issue/SKILL.md'"
assert_success "skills/implement-issue/SKILL.md in repo has valid semver version" \
  bash -c "grep -q '^version: [0-9]\+\.[0-9]\+\.[0-9]\+\$' '$ROOT_DIR/skills/implement-issue/SKILL.md'"

# NOTE: a test asserting "a failed archive leaves no DEST behind" (the new
# staging+mv behavior from the release.sh fix) was deliberately NOT added
# here. Forcing `git archive | tar` itself to fail requires either corrupting
# git objects mid-test or relying on filesystem permission checks (e.g.
# chmod a-w a parent dir) that silently no-op when tests run as root (common
# in CI/containers) -- both brittle. The mktemp-based staging directory is
# exercised on every successful run above (cases a, d, h, j, l, m, o, p), so
# the plumbing is covered; only the failure-path cleanup itself is untested.

echo "release.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]

