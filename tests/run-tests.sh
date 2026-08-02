#!/usr/bin/env bash
# Runs all repo-root script tests (currently just release.sh). No dependencies
# beyond bash and git — deliberately no bats/etc., mirrors
# skills/implement-issue/scripts/tests/run-tests.sh so this runs unmodified on
# a fresh machine.
#
# Usage: run-tests.sh

set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
