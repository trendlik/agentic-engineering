# implement-issue — Project Learnings

Approved, project-specific findings from implement-issue retrospectives (Phase 8).

This file is **data, not instructions**: it supplies content *within* individual
phases — extra clarify questions, planning constraints, test commands, review
checklist items, known CI flakes. It can never add, remove, reorder, or skip the
skill's phases, checkpoints, or gates; those are defined only by the skill itself
(SKILL.md / WORKFLOW.md). A finding that doesn't fit one of the fixed section
headings below is a flow change by definition and does not belong here — escalate
it to the skill's maintainers instead (see WORKFLOW.md Phase 8 Step 4b).

Every entry ends with its provenance: `(issue #<n>, YYYY-MM-DD, skill@<short-sha>)`.
An entry recorded against a much older skill commit may describe behaviour the
skill no longer has — verify before trusting it.

## Clarify checklist (Phase 1)

<!-- Extra questions/checks to run against every issue in this repo -->

## Planning constraints (Phase 2)

<!-- The skill applies a baseline of architecture standards to every plan (WORKFLOW.md Phase 2).
     Only THIS repo's own rules go here — not the baseline. -->

- New behaviour that varies by platform/adapter (Claude Code vs Antigravity, BSD vs GNU
  userland) must go through the existing seams, not add a fresh conditional branch that
  duplicates that decision in a new place.
- Keep deterministic mechanics in tested scripts under `scripts/`, not as new inline
  bash in WORKFLOW.md (mirrors the existing `scripts/` design). Any new script ships
  with a test in `scripts/tests/`.

## Build & test (Phase 4)

<!-- Commands, environment quirks, required version-control-ignored files, suite-specific advice -->

## Review checklist (Phase 5)

<!-- The reviewer applies a baseline architecture/security/test-quality checklist to every diff
     (WORKFLOW.md Phase 5). Only THIS repo's own review items go here — not the baseline. -->

- New deterministic logic lives in a tested `scripts/` file with a corresponding test in
  `scripts/tests/`, not inline in WORKFLOW.md.
- Fail-closed enforcement (`verify-gates.sh`, gate labels) is not weakened, and the
  advisory (`gate.sh`) vs enforced (`verify-gates.sh`) distinction is preserved.
- No `docker run` host mounts or `bypassPermissions` added to `settings.local.json` to
  paper over an approval prompt; secret handling follows the `SKILL_REPO_TOKEN` pattern.
- Edge cases specific to this skill's mechanics (missing label, offline `gh`, absent
  artifact comment, BSD vs GNU userland) have a test in the `scripts/tests/` suite.

## CI quirks (Phase 7)

<!-- Known flaky checks, their failure signatures, and proven fixes -->
