---
name: implement-issue
description: Implements a GitHub issue end-to-end through a structured clarify → plan → implement → test → review → PR → CI-watch → retrospective loop, with separate sub-agents for implementation, testing, review, and CI fixes. Use when user says "implement issue #N", "/implement-issue N", or wants to work a GitHub issue through to a pull request.
---

# implement-issue

## Quick start

```
/implement-issue 42
/implement-issue 42 --skip-e2e
```

Fetches issue #42, clarifies requirements with the user, drafts and gets approval on an implementation plan, then runs sequential sub-agents (implement → test → review) in an isolated git worktree. Loops on review findings until clean, opens a PR, then watches CI and spawns fix agents until all checks pass. Ends with a retrospective that diagnoses bottlenecks and proposes targeted edits to the skill's own documentation.

Pass `--skip-e2e` to skip the E2E test suite in Phase 4 (build + type-check only). If the flag is omitted, the user is asked after plan approval.

## Phase overview

Announce each phase as you enter it: **"--- Phase N: Name ---"**

| # | Phase | Who |
|---|-------|-----|
| 1 | Clarify | Main agent (interactive) |
| 2 | Plan | Main agent (user approval required) |
| 3 | Implement | Sub-agent in isolated worktree |
| 4 | Test | Sub-agent in same worktree |
| 5 | Review | Sub-agent (read-only) |
| 6 | Decision | Main agent → loop or PR |
| 7 | CI Watch & Fix | Main agent + fix sub-agents, loops until green |
| 8 | Retrospective | Main agent → diagnose bottlenecks → propose skill edits |

See [WORKFLOW.md](WORKFLOW.md) for full per-phase instructions.

## Key rules

- Parse `<number>` from the invocation args (e.g. `/implement-issue 42` → number is `42`)
- Parse optional `--skip-e2e` flag; if present, save `$RUN_E2E=false` immediately and skip asking the user
- Never proceed past Phase 2 without explicit user plan approval
- Derive `$FEATURE_BRANCH` from the project's branching strategy (CLAUDE.md → issue labels → title slug → fallback `issue-<number>`); use it everywhere — never hardcode `issue-<number>`
- Pass full context to every sub-agent: issue number, title, body, clarification summary (including any explicitly REJECTED alternatives, not just the chosen decisions), approved plan, and the derived `$FEATURE_BRANCH`
- The worktree path returned by the Phase 3 agent is reused in Phases 4, 5, and 7
- Review agent must see ALL accumulated changes, including from prior loop iterations
- On a clean review: open PR with `gh pr create --head $FEATURE_BRANCH` linking `Closes #<number>`, then enter Phase 7
- On review issues: show findings, ask user whether to re-clarify (back to Phase 1) or re-implement (back to Phase 3), then loop
- Phase 7: wait for CI, spawn fix agents on failure, loop — cap at 5 fix iterations
- Phase 8: always runs after Phase 7 (pass or stop-and-report); tally loop counts, diagnose root causes, propose concrete edits to SKILL.md/WORKFLOW.md, apply with user approval

## Model assignments

The coordinator (Phases 1, 2, 6 decision, 7 watch, 8) runs on the session model — set it with `/model` (Opus recommended). Sub-agents pin their own model via the `model:` field in each `Agent({...})` block:

| Phase | Sub-agent | Model |
|-------|-----------|-------|
| 3 | Implement | `sonnet` |
| 4 | Test | `sonnet` |
| 5 | Review | `opus` |
| 6 | Fix blocking issues | `sonnet` |
| 7 | CI fix | `sonnet` |

If a sub-agent block has no `model:` field, it inherits the coordinator's model.
