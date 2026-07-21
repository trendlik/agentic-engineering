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

<!-- The skill already applies a baseline of architecture standards to every plan (module/layer
     boundaries, no near-duplicate abstractions, single source of truth for new state). Add only
     THIS repo's own edge cases, architectural rules, and config gotchas here — don't repeat the
     baseline. -->

## Build & test (Phase 4)

<!-- Commands, environment quirks, required version-control-ignored files, suite-specific advice -->

## Review checklist (Phase 5)

<!-- The reviewer already applies a baseline checklist to every diff: architecture standards,
     security, and test quality (see WORKFLOW.md Phase 5). Add only THIS repo's own review items
     on top — don't repeat the baseline. -->

## CI quirks (Phase 7)

<!-- Known flaky checks, their failure signatures, and proven fixes -->
