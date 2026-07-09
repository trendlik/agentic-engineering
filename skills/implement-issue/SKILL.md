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
| 0 | Resume Check | Main agent (automatic — no user interaction unless resuming) |
| 1 | Clarify | Main agent (interactive) |
| 2 | Plan | Main agent (user approval required) |
| 3 | Implement | Sub-agent in isolated worktree |
| 4 | Test | Sub-agent in same worktree |
| 5 | Review | Sub-agent (read-only) |
| 6 | Decision | Main agent → loop or PR |
| 7 | CI Watch & Fix | Main agent + fix sub-agents, loops until green |
| 8 | Retrospective | Main agent → diagnose bottlenecks → propose skill edits |

See [WORKFLOW.md](WORKFLOW.md) for full per-phase instructions.

## Setup: resolve `$SKILL_DIR`

Before Phase 1, resolve the skill's own directory once — every script call in WORKFLOW.md uses `$SKILL_DIR`:

```bash
for candidate in ~/.claude/skills/implement-issue ~/.gemini/config/skills/implement-issue; do
  [[ -d "$candidate/scripts" ]] && SKILL_DIR="$candidate" && break
done
```

This resolves correctly whether the skill is reached via the Claude Code or Antigravity symlink — bash follows a symlinked directory transparently, so no `readlink`/`realpath` gymnastics are needed (those differ between BSD and GNU userlands anyway).

New machine? Run `$SKILL_DIR/scripts/doctor.sh` first — it verifies git/gh/jq are installed and authenticated and reports exactly what's missing.

## Scripts

`scripts/` holds the deterministic mechanics that used to live as inline bash in WORKFLOW.md — same behavior, now tested (`scripts/tests/run-tests.sh`, no dependencies beyond bash/git/jq) and identical across machines and both platform adapters:

| Script | Replaces | Used in |
|---|---|---|
| `doctor.sh` | — (new) | new-machine setup |
| `sync-base.sh` | manual `git remote show origin` / fetch / rebase | Between Phase 1 and 2 |
| `derive-branch.sh <issue>` | inline label→prefix + slugify heuristic | Between Phase 1 and 2 |
| `state.sh` | — (new) | stage/gate bookkeeping at every phase transition; read by Phase 0 to dispatch |
| `find-artifact.sh <issue> <heading>` | — (new) | Phase 0 — loads a previously-posted clarification/plan comment on resume |
| `role.sh` | — (new) | Phase 0 — advisory check of who usually owns a stage |
| `gate.sh <issue> <gate>` | — (new) | manual/local advisory gate check (fails open) |
| `verify-gates.sh <issue>` | — (new) | **CI only** — the fail-closed enforcement check; see below |

`state.sh` persists the issue's workflow stage and approval gates as GitHub labels (`stage:*`, `gate:*-approved`) — see the header comment in `scripts/state.sh` for the full command reference. Writing this state (at every phase transition) is **best-effort bookkeeping**: if a call fails (labels disabled, no push access, offline), log a warning and continue — the existing conversational approval in Phase 1/2 remains the actual gate. **Reading** it, however, is load-bearing: Phase 0 uses `state.sh get` to decide whether to resume mid-workflow, which is what makes a different session — or a different person, or a different LLM adapter — able to pick up where a previous one left off. See WORKFLOW.md's Phase 0 for the full dispatch logic.

`role.sh` reads `ROLES.yml` from the **target project's** repo root (not this skill's directory — copy `ROLES.example.yml` there and fill in real usernames) to check whether the current GitHub user matches the role a stage is usually owned by (analyst/architect/developer/qa). It fails open whenever nothing can be verified — no `ROLES.yml`, unlisted user, no `gh`/`jq` — so a project that hasn't set up roles is unaffected. This is advisory only today (Phase 0 warns on a mismatch but never blocks) — real enforcement is `verify-gates.sh`, below.

## CI enforcement

`gate.sh`/`role.sh` are advisory: they run locally and fail open, so they can warn but never stop a determined (or careless) person from self-approving their own gate. `verify-gates.sh` closes that gap — it checks the GitHub issue's label *timeline*, not just current label state, to find who actually applied each `gate:*-approved` label, and fails the check if that person's `ROLES.yml` role doesn't match what the gate requires (`gate:analysis-approved` → `analyst`, `gate:plan-approved` → `architect`). It's meant to run as a **required PR status check**, not locally.

To turn this on for a project:

1. Copy `ROLES.example.yml` to the target project's repo root as `ROLES.yml`, filling in real GitHub usernames.
2. Copy `templates/implement-issue-gate.yml` to the target project's `.github/workflows/implement-issue-gate.yml`. It checks out this skill's repo fresh on every run (no need to vendor scripts into the target project) and resolves the linked issue from the PR body's `Closes #<n>`.
   - `trendlik-org/agentic-engineering` is **private**, so this checkout needs an explicit token — `GITHUB_TOKEN` can never read a different repo, even in the same org (a hard GitHub limitation, not a missing setting). Create a fine-grained PAT scoped to read-only Contents+Metadata on `trendlik-org/agentic-engineering`, then store it as an **org** secret (shared across every target repo in `trendlik-org`, not re-created per repo): `gh secret set SKILL_REPO_TOKEN --org trendlik-org --repos "<target-repo-name>"`.
3. In the target repo's branch protection settings, add `implement-issue-gate` as a required status check.

Steps 1–2 just make the check *run* (informational, visible on the PR, not blocking). Step 3 is what makes it actually enforce — and it's a repo-admin action with real consequences for collaborators, so treat it deliberately: confirm with whoever owns the target repo's branch protection before adding it, and consider running it informationally for a while first to catch false positives (e.g. a valid approver who isn't in `ROLES.yml` yet).

## Key rules

- Resolve `$SKILL_DIR` first (see Setup above) — every script invocation below depends on it
- Parse `<number>` from the invocation args (e.g. `/implement-issue 42` → number is `42`)
- Always run Phase 0 before Phase 1 — never assume an issue is fresh; let `state.sh get` decide whether to resume mid-workflow
- Phase 0's role check is advisory only — warn on a mismatch, never block on it
- Parse optional `--skip-e2e` flag; if present, save `$RUN_E2E=false` immediately and skip asking the user
- Never proceed past Phase 2 without explicit user plan approval
- Derive `$FEATURE_BRANCH` from the project's branching strategy (CLAUDE.md / AGENTS.md → issue labels → title slug → fallback `issue-<number>`); use it everywhere — never hardcode `issue-<number>`
- Pass full context to every sub-agent: issue number, title, body, clarification summary (including any explicitly REJECTED alternatives, not just the chosen decisions), approved plan, and the derived `$FEATURE_BRANCH`
- The worktree path returned by the Phase 3 agent is reused in Phases 4, 5, and 7
- Review agent must see ALL accumulated changes, including from prior loop iterations
- On a clean review: open PR with `gh pr create --head $FEATURE_BRANCH` linking `Closes #<number>`, then enter Phase 7
- On review issues: show findings, ask user whether to re-clarify (back to Phase 1) or re-implement (back to Phase 3), then loop
- Phase 7: wait for CI, spawn fix agents on failure, loop — cap at 5 fix iterations; before announcing success, re-query the PR state (`gh pr view <n> --json state,mergedBy`) and word the summary to match — the user may have merged or closed it mid-run, so never assume it is still open
- Phase 8: always runs after Phase 7 (pass or stop-and-report); tally loop counts, diagnose root causes, propose concrete edits to SKILL.md/WORKFLOW.md, apply with user approval, and commit to the appropriate skill directory (e.g. `~/.claude/skills/implement-issue` or `~/.gemini/config/skills/implement-issue`).

## Model assignments & Capability Tiers

The coordinator (Phases 1, 2, 6 decision, 7 watch, 8) runs on the session model — set it with `/model` (e.g. Opus or Gemini 3.5 Pro recommended).

For sub-agents, we define two capability tiers:
- **Coding Tier** (fast, highly accurate coding & tool usage): Map to `sonnet` (Claude Code) or `gemini-3.5-flash` (Antigravity).
- **Review Tier** (strong reasoning, comprehensive analysis): Map to `opus` (Claude Code) or `gemini-3.5-pro` (Antigravity).

| Phase | Sub-agent | Tier | Claude Code Model | Antigravity Model |
|-------|-----------|------|-------------------|-------------------|
| 3 | Implement | Coding | `sonnet` | `gemini-3.5-flash` |
| 4 | Test | Coding | `sonnet` | `gemini-3.5-flash` |
| 5 | Review | Review | `opus` | `gemini-3.5-pro` |
| 6 | Fix blocking issues | Coding | `sonnet` | `gemini-3.5-flash` |
| 7 | CI fix | Coding | `sonnet` | `gemini-3.5-flash` |

When spawning sub-agents, use the appropriate model/tier configuration based on the platform you are running on. If a sub-agent execution has no explicit model/tier pinned, it inherits the coordinator's model.
