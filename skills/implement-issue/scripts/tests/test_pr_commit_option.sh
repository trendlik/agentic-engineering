#!/usr/bin/env bash
# Tests for Phase 8 feature PR commit option for LEARNINGS.md and outcomes.jsonl in WORKFLOW.md and SKILL.md.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$TEST_DIR/../.." && pwd)"

# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

echo "test_pr_commit_option.sh"

WORKFLOW_FILE="$SKILL_DIR/WORKFLOW.md"
SKILL_FILE="$SKILL_DIR/SKILL.md"
ONBOARDING_FILE="$SKILL_DIR/ONBOARDING.md"

# 1. Check WORKFLOW.md contains retrospective commit step prompt asking whether to commit directly to feature branch
assert_success "WORKFLOW.md documents asking user whether to commit retrospective changes directly to feature branch" \
  grep -Fq 'Commit retrospective changes (.implement-issue/outcomes.jsonl and approved LEARNINGS.md entries) directly to feature branch' "$WORKFLOW_FILE"

# 2. Check WORKFLOW.md documents git push origin HEAD:<feature_branch> for feature PR branch commit
assert_success "WORKFLOW.md documents pushing retrospective changes to feature branch" \
  grep -Fq 'git push origin HEAD:<feature_branch>' "$WORKFLOW_FILE"

# 3. Check WORKFLOW.md documents staging both LEARNINGS.md and outcomes.jsonl
assert_success "WORKFLOW.md documents staging LEARNINGS.md and outcomes.jsonl" \
  grep -Fq 'git add .implement-issue/LEARNINGS.md .implement-issue/outcomes.jsonl' "$WORKFLOW_FILE"

# 4. Check WORKFLOW.md Step 1b documents deferring outcomes.jsonl commit to retrospective commit step
assert_success "WORKFLOW.md Step 1b documents deferring outcomes.jsonl commit to retrospective commit step" \
  grep -Fq '`record-outcome.sh` writes the entry to `.implement-issue/outcomes.jsonl` in the working tree without running `git commit`.' "$WORKFLOW_FILE"

# 5. Check SKILL.md mentions option to commit outcomes and learnings to feature PR branch
assert_success "SKILL.md documents option to commit to feature PR branch in Quick start summary" \
  grep -Fq 'option to commit them directly to the feature PR branch as part of the feature PR after CI passes' "$SKILL_FILE"

# 6. Check SKILL.md Key Rules bullet for Phase 8 mentions feature PR commit option
assert_success "SKILL.md Key Rules bullet documents committing outcomes and learnings to feature PR branch" \
  grep -Fq 'Retrospective changes (`outcomes.jsonl` and approved `LEARNINGS.md` entries) can be committed directly to the feature PR branch' "$SKILL_FILE"

# 7. Check ONBOARDING.md documents feature PR commit option for learnings and outcomes
assert_success "ONBOARDING.md documents feature PR commit option for learnings and outcomes" \
  grep -Fq 'The retrospective offers to commit `outcomes.jsonl` (and any approved `LEARNINGS.md` entries) directly to the feature PR branch' "$ONBOARDING_FILE"

# 8. Check explicit approval mandate before LEARNINGS.md modifications is preserved
assert_success "WORKFLOW.md preserves explicit user approval requirement before LEARNINGS.md edits" \
  grep -Fq 'Project-scoped proposals targeting `.implement-issue/LEARNINGS.md` MUST be presented to the user for approval FIRST before any changes to `.implement-issue/LEARNINGS.md` or git commits are performed.' "$WORKFLOW_FILE"

echo "test_pr_commit_option.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
