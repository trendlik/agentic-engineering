#!/usr/bin/env bash
# Tests for sync-base.sh using real throwaway git repos (no gh needed — this
# script resolves the base branch via the local origin/HEAD symref first).
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

SYNC="$SCRIPTS_DIR/sync-base.sh"

echo "sync-base.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Repo-local identity (not a shell alias) — sync-base.sh runs git as its own
# process, so config must live in each repo's .git/config to be visible to it.
set_local_identity() {
  git -C "$1" config user.email "test@test"
  git -C "$1" config user.name "test"
}

# --- fixture: bare "origin" + a clone with a feature branch behind main ---
git init --quiet --bare "$SANDBOX/origin.git"

git clone --quiet "$SANDBOX/origin.git" "$SANDBOX/seed"
set_local_identity "$SANDBOX/seed"
(
  cd "$SANDBOX/seed"
  git checkout --quiet -b main
  echo "base" > file.txt
  git add file.txt
  git commit --quiet -m "initial"
  git push --quiet origin main
)
git -C "$SANDBOX/origin.git" symbolic-ref HEAD refs/heads/main

git clone --quiet "$SANDBOX/origin.git" "$SANDBOX/work"
set_local_identity "$SANDBOX/work"
(
  cd "$SANDBOX/work"
  git checkout --quiet -b feature
)

# Advance main on origin so the clone's feature branch is behind it.
(
  cd "$SANDBOX/seed"
  echo "new on main" >> file.txt
  git commit --quiet -am "advance main"
  git push --quiet origin main
)

# --- happy path: clean rebase ---
out=$(cd "$SANDBOX/work" && "$SYNC" 2>/dev/null)
assert_eq "$out" "main" "prints the detected base branch on success"

on_main_commit=$(cd "$SANDBOX/work" && git log --oneline | grep -c "advance main")
assert_eq "$on_main_commit" "1" "feature branch is rebased onto the latest main"

# --- already up to date: `git rebase` prints its own status text
# ("Current branch main is up to date.") to STDOUT in this case, which must
# not leak into the captured return value alongside the real branch name ---
out=$(cd "$SANDBOX/work" && "$SYNC" 2>/dev/null)
assert_eq "$out" "main" "output stays clean ('main' only) when already up to date, not polluted by git's own status text"

# --- conflict path: leaves the rebase in progress and reports the file ---
(
  cd "$SANDBOX/work"
  echo "conflicting local change" > file.txt
  git commit --quiet -am "conflicting change"
)
(
  cd "$SANDBOX/seed"
  echo "conflicting remote change" > file.txt
  git commit --quiet -am "advance main again"
  git push --quiet origin main
)

# Single invocation: capture both the exit code and stderr from the same run
# (a second invocation would hit "rebase already in progress" instead).
err_out=$(cd "$SANDBOX/work" && "$SYNC" 2>&1 1>/dev/null)
sync_exit=$?
assert_eq "$sync_exit" "1" "conflicting rebase exits non-zero"
# Piped via stdin, not string-interpolated into a nested shell command — git's
# own hint text contains literal double quotes that would otherwise break a
# naive "bash -c \"...$err_out...\"" construction.
assert_success "conflict output names the conflicting file" grep -q "file.txt" <<< "$err_out"
# The failed attempt above leaves a rebase in progress; clean it up.
(cd "$SANDBOX/work" && git rebase --abort >/dev/null 2>&1 || true)

echo "sync-base.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
