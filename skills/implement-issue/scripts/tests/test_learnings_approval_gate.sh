#!/usr/bin/env bash
# Tests for Phase 8 Step 4a LEARNINGS.md explicit user approval requirement in WORKFLOW.md and SKILL.md.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$TEST_DIR/../.." && pwd)"

# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

echo "test_learnings_approval_gate.sh"

WORKFLOW_FILE="$SKILL_DIR/WORKFLOW.md"
SKILL_FILE="$SKILL_DIR/SKILL.md"

# 1. Check WORKFLOW.md contains explicit approval mandate before file writes/commits
assert_success "WORKFLOW.md mandates user approval FIRST before LEARNINGS.md edits or git commit" \
  grep -Fq 'Project-scoped proposals targeting `.implement-issue/LEARNINGS.md` MUST be presented to the user for approval FIRST before any changes to `.implement-issue/LEARNINGS.md` or git commits are performed.' "$WORKFLOW_FILE"

# 2. Check WORKFLOW.md contains STOP and wait instruction
assert_success "WORKFLOW.md instructs agent to STOP and wait for explicit user response" \
  grep -Fq '**STOP and wait for explicit user response** before modifying `.implement-issue/LEARNINGS.md` or running `git commit`.' "$WORKFLOW_FILE"

# 3. Check WORKFLOW.md contains skip/decline rule blocking writes and commits
assert_success "WORKFLOW.md specifies skip/decline prevents LEARNINGS.md edits and git commit" \
  grep -Fq 'Skip / decline ("skip")**: do NOT modify `.implement-issue/LEARNINGS.md` and do NOT execute `git commit`.' "$WORKFLOW_FILE"

# 4. Check SKILL.md requires user approval prior to file writes or commits
assert_success "SKILL.md requires user approval prior to file writes or commits in learnings summary" \
  grep -Fq "only after explicit user approval prior to any file writes or commits" "$SKILL_FILE"

# 5. Check SKILL.md mentions stopping to wait for user response in Phase 8 summary
assert_success "SKILL.md mandates stopping to wait for user response in Phase 8 summary" \
  grep -Fq "requires prior explicit user approval before any file writes or commits occur — stopping to wait for user response" "$SKILL_FILE"

echo "test_learnings_approval_gate.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
