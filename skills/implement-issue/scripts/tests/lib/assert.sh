#!/usr/bin/env bash
# Tiny assertion helpers for the implement-issue script tests. Sourced by
# each test_*.sh file. Tracks pass/fail counts in globals the runner reads.

set -uo pipefail

ASSERT_PASS=0
ASSERT_FAIL=0

_report() {
  local ok=$1 desc=$2
  if [[ "$ok" == "0" ]]; then
    printf '  \033[0;32mok\033[0m   %s\n' "$desc"
    ASSERT_PASS=$((ASSERT_PASS + 1))
  else
    printf '  \033[0;31mFAIL\033[0m %s\n' "$desc"
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
  fi
}

assert_eq() {
  local actual=$1 expected=$2 desc=$3
  if [[ "$actual" == "$expected" ]]; then
    _report 0 "$desc"
  else
    _report 1 "$desc (expected '$expected', got '$actual')"
  fi
}

assert_success() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then
    _report 0 "$desc"
  else
    _report 1 "$desc (expected exit 0, got $?)"
  fi
}

assert_failure() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then
    _report 1 "$desc (expected non-zero exit, got 0)"
  else
    _report 0 "$desc"
  fi
}
