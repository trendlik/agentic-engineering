#!/usr/bin/env bash
# Runs all implement-issue script tests. No dependencies beyond bash, git,
# and jq (already required by the scripts themselves) — deliberately no
# bats/etc., so this runs unmodified on a fresh machine.
#
# Usage: run-tests.sh

set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export FAKE_GH_STATE_DIR
FAKE_GH_STATE_DIR=$(mktemp -d)

FAKE_BIN_DIR=$(mktemp -d)
ln -s "$TEST_DIR/fake-gh" "$FAKE_BIN_DIR/gh"

trap 'rm -rf "$FAKE_GH_STATE_DIR" "$FAKE_BIN_DIR"' EXIT

# Prepend the fake `gh` (exposed under its real name via the symlink above)
# so every test_*.sh, and the scripts it drives, talks to the fixture
# instead of the network or a real repo.
export PATH="$FAKE_BIN_DIR:$PATH"

total_pass=0
total_fail=0
suite_failures=()

for test_file in "$TEST_DIR"/test_*.sh; do
  [[ -e "$test_file" ]] || continue
  name=$(basename "$test_file")
  echo "=== $name ==="
  if bash "$test_file"; then
    :
  else
    suite_failures+=("$name")
  fi
  echo
done

echo "---"
if [[ ${#suite_failures[@]} -eq 0 ]]; then
  printf '\033[0;32mAll test suites passed.\033[0m\n'
  exit 0
else
  printf '\033[0;31m%d suite(s) had failures: %s\033[0m\n' "${#suite_failures[@]}" "${suite_failures[*]}"
  exit 1
fi
