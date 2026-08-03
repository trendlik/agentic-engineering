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
- Release/publish/deploy tooling must source the artifact from the canonical remote's
  committed state (fetch, then archive a tag or remote-tracking ref) — never the local
  working tree or local HEAD, which can carry uncommitted or unpushed state. State the
  authoritative source explicitly in the plan, and decide tag/push side effects (does the
  tool push the tag, or only build the snapshot?) up front rather than during
  implementation. (issue #31, 2026-08-02, skill@a9492e4)
- When a change alters how the tooling resolves its own location (symlink layout, candidate
  order, release-store pins), the plan must sequence the out-of-repo re-point **before**
  merge, not as a post-merge follow-up — otherwise the first run after merge resolves into
  the mutable SOURCE it is editing. State it as a pre-merge checklist item in the PR body.
  (issue #37, 2026-08-03, skill@v1.0.0)

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
- When a change adds or edits checkpoint / user-reply handling, verify the new wording
  is consistent with ALL existing reply branches — especially local mode's "request
  changes" gate action — so a new reply taxonomy doesn't reclassify or contradict an
  existing first-class directive. (issue #27, 2026-07-26, skill@ca06aaf)
- Scripts that build filesystem paths from env vars/config/frontmatter and then mutate
  them (`chmod -R`, `rm -rf`, archive-extract, `mv`) must: (a) validate each path
  component against traversal (reject `.`/`..`/leading-dot/`..`-containing values), not
  just a character-class regex; and (b) populate a destination atomically — stage into a
  temp dir and `mv` into place on success, with trap/cleanup on failure — so a
  mid-operation failure never leaves a partial artifact (especially one that a later
  immutability/exists guard would then refuse to overwrite). (issue #31, 2026-08-02, skill@a9492e4)
- `.claude/settings.json` is **committed** in this repo, and Claude Code writes approved
  Bash/Read rules into it — so absolute machine-specific paths (`/Users/<name>/…`) and
  version-pinned release-store paths accrete there silently, including from permission
  prompts nobody edited by hand. Any diff touching it must use `~`-relative forms and carry
  no pin version; per-machine rules belong in the gitignored `.claude/settings.local.json`.
  Check with `git grep -n '/Users/'`. (issue #37, 2026-08-03, skill@v1.0.0)
- A drift/consistency test that compares prose to code must assert the block's **semantics**
  (loop termination, guards, predicates), not just the ordering of extracted values, and each
  assertion must be mutation-tested on a **copy**: delete the construct and confirm that
  assertion — and only it — fails. (issue #37, 2026-08-03, skill@v1.0.0)
- Any doc claim about what `release.sh` does or requires must be verified against `release.sh`
  itself. Two facts that are easy to get wrong: the tag push is **unconditional** (so every
  path needs push access, even tag reuse), and the release store is **per-machine**
  (`$HOME/.agents/releases`), so another person's release never appears in your `$HOME`.
  (issue #37, 2026-08-03, skill@v1.0.0)

## CI quirks (Phase 7)

<!-- Known flaky checks, their failure signatures, and proven fixes -->
