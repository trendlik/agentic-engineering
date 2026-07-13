# implement-issue — Detailed Workflow

## Phase 0: Resume Check

Runs automatically at the start of every invocation, before Phase 1 — determines whether this issue is fresh or a previous session (possibly a different person, machine, or LLM adapter) already made progress, and jumps to the right place instead of restarting.

1. Query the recorded stage:

```bash
STAGE=$("$SKILL_DIR/scripts/state.sh" get <number>)
```

2. Branch on `$STAGE`:

- **`none`** — fresh issue. Proceed to Phase 1 as written below.

- **`clarify`** — Phase 1 already completed in a previous session (the clarification comment exists on the issue; `gate:analysis-approved` is set) but Phase 2 never started. Load it instead of re-clarifying:

  ```bash
  CLARIFICATION_SUMMARY=$("$SKILL_DIR/scripts/find-artifact.sh" <number> "Clarification Summary")
  ```

  Tell the user clarification is already done, show them the summary, and skip straight to "Between Phase 1 and Phase 2" → Phase 2.

- **`plan`** — Phase 2 was started but never approved. There's nothing durable to recover here — the plan comment is only posted on approval (see Phase 2) — so load the clarification summary as above, skip Phase 1, and re-enter Phase 2 fresh. Tell the user a previous plan draft (if any) wasn't recoverable and needs redrafting.

- **`implement`, `test`, `review`, `ci`** — Phase 2 was approved in a previous session. Load both persisted artifacts:

  ```bash
  CLARIFICATION_SUMMARY=$("$SKILL_DIR/scripts/find-artifact.sh" <number> "Clarification Summary")
  APPROVED_PLAN=$("$SKILL_DIR/scripts/find-artifact.sh" <number> "Implementation Plan")
  # At stage `review`/`ci` a Review Findings comment may also exist (Phase 5 posts it).
  # Empty = review hasn't run yet on this issue → run it fresh. Present = reload it
  # instead of re-reviewing blind, and (if minor issues) show it to the user per Phase 6.
  REVIEW_FINDINGS=$("$SKILL_DIR/scripts/find-artifact.sh" <number> "Review Findings")
  ```

  Re-derive `$BASE_BRANCH` and `$FEATURE_BRANCH` as usual (Between Phase 1 and Phase 2, Steps 1 and 3) — these are deterministic, not stored, so there's nothing to load for them. Then check whether the branch already has commits:

  ```bash
  git ls-remote --heads origin "$FEATURE_BRANCH"
  ```

  - Branch exists: tell the user implementation may already be underway; ask whether to continue from it (fetch into a fresh worktree, resume at `$STAGE`) or discard it and restart Phase 3.

    If continuing: unlike the clarification and plan, the Phase 3/4 sub-agents' own "what I implemented" / "what I tested" prose reports are never persisted anywhere — do not assume they're recoverable from a prior session. Derive that context directly from the branch instead, which is more reliable anyway:

    ```bash
    git -C <worktree_path> log --oneline "origin/$BASE_BRANCH..HEAD"
    git -C <worktree_path> diff "origin/$BASE_BRANCH...HEAD" --stat
    ```

    Read the commit messages and changed-files list (and the actual diff for anything non-obvious) to reconstruct "what was implemented" / "what was tested" before feeding it into whichever phase's sub-agent prompt comes next.
  - Branch doesn't exist: nothing was actually implemented despite the stage label (the previous session likely ended right after Phase 2 approval) — proceed to Phase 3 as normal.

- **`done`** — already finished. Tell the user and ask whether they want to re-open work on it anyway (stale label, or genuinely new follow-up work) before doing anything.

Always announce which branch was taken (e.g. "Resuming issue #<n> at stage: implement" or "Starting fresh — no prior progress recorded") before proceeding — the user should never be surprised that phases were silently skipped.

---

## Phase 1: Clarify

1. Capture the current branch so it can be restored when the skill exits:

```bash
ORIGINAL_BRANCH=$(git branch --show-current)
```

**Save `$ORIGINAL_BRANCH`** — restore it on every exit path (success or stop-and-report).

Best effort, non-blocking: `"$SKILL_DIR/scripts/state.sh" init <number>` — sets `stage:clarify` if the issue has no stage label yet (idempotent; does nothing if Phase 0 already found an existing stage).

2. Run: `gh issue view <number> --json title,body,labels,comments`
3. Read the issue carefully. Identify anything ambiguous: unclear acceptance criteria, missing context, edge cases not addressed, scope questions. If `$LEARNINGS_FILE` exists, also run every item in its **Clarify checklist (Phase 1)** section against the issue.
4. Ask the user your questions in a single message (don't drip one at a time unless follow-ups are needed).
5. Iterate until you have clear answers.
6. When satisfied, post a structured clarification summary as a GitHub comment:

```bash
gh issue comment <number> --body "$(cat <<'EOF'
## Clarification Summary

**Requirements confirmed:**
- <bullet per confirmed requirement>

**Decisions made:**
- <bullet per decision from clarification>

**Out of scope:**
- <bullet per explicitly excluded item>

**Open questions resolved:**
- Q: <question> → A: <answer>
EOF
)"
```

7. Best effort, non-blocking — record progress for future resumability. If the call fails (labels disabled, no push access, offline), log a warning and continue; do not let it stop the phase:

```bash
"$SKILL_DIR/scripts/state.sh" approve <number> analysis
```

### Checkpoint: do not auto-continue into planning

Clarification and planning are not the same act, and not necessarily the same person — an analyst clarifying requirements does not imply they (or anyone present in this session) is the architect who should now draft the plan. Ask explicitly:

> "Clarification recorded. Should plan drafting start now in this session, or stop here for someone (possibly a different person, machine, or session) to pick it up later?"

- **Proceed now**: continue directly into "Between Phase 1 and Phase 2" → Phase 2 below, same session.
- **Stop here**: the state is already correctly recorded (`stage:clarify`, `gate:analysis-approved`) — that's exactly what Phase 0 reads on the next invocation to resume at Phase 2 with the clarification already loaded (see Phase 0's `clarify` branch). Restore `$ORIGINAL_BRANCH`, tell the user plan drafting is ready to start whenever (same command, this or a different session/person: `/implement-issue <number>`), and end here — this is a clean stop, not a failure to report.

---

## Between Phase 1 and Phase 2: Sync local branch and derive branch name

Before drafting the plan, detect the base branch, derive the feature branch name from the project's branching strategy, and ensure the local branch is up to date so the plan reflects the current codebase.

Do not begin drafting the plan until this section's sync/derive steps have actually been run this session — jumping straight from Phase 1 into plan-drafting is a real failure mode, not just a hypothetical one.

### Step 1 — Detect base branch

```bash
BASE_BRANCH=$("$SKILL_DIR/scripts/sync-base.sh")
```

This detects the base branch, fetches, and rebases the current branch onto it in one deterministic step (same logic on every machine, tested in isolation — see `scripts/tests/test_sync_base.sh`).

**Save `$BASE_BRANCH`** — you will need it in Phases 6 and 7.

If the script exits non-zero, it has already printed the conflicting files to stderr and left the rebase in progress — stop and report them to the user; do not proceed until the base branch is clean.

### Step 2 — Read CLAUDE.md / AGENTS.md and detect branching strategy

Read `CLAUDE.md` or `AGENTS.md` now to understand project conventions (test commands, framework, paths, TypeScript rules, etc.) — you will pass this context to sub-agents.

While reading CLAUDE.md / AGENTS.md, look for an explicit branch naming pattern. Common forms:
- `feat/<number>-<slug>`, `fix/<number>-<slug>`, `chore/<number>-<slug>`
- `feature/<slug>`, `bugfix/<slug>`
- `<type>/<number>`, `issue-<number>`

If CLAUDE.md or AGENTS.md documents a pattern, follow it exactly.

### Step 3 — Derive the feature branch name

If CLAUDE.md or AGENTS.md defines a naming convention, apply it exactly — that's a judgement call only the agent can make (reading and matching arbitrary project prose). Otherwise use the deterministic default:

```bash
FEATURE_BRANCH=$("$SKILL_DIR/scripts/derive-branch.sh" <number>)
```

The script composes `<type>/<number>-<slug>` from the issue's labels and title (type prefix priority: `bug`/`fix`/`defect` → `fix`, `feature`/`enhancement`/`feat` → `feat`, `chore`/`maintenance`/`refactor` → `chore`, `docs` → `docs`, else → `feat`; title is lowercased, slugified, and trimmed to 40 chars; falls back to `issue-<number>` if the slug is empty). Same output on every machine — see `scripts/tests/test_derive_branch.sh`.

**Save `$FEATURE_BRANCH`** — every sub-agent prompt and git command must use this value, not a hardcoded `issue-<number>`.

---

## Phase 2: Plan

Best effort, non-blocking: `"$SKILL_DIR/scripts/state.sh" set <number> plan`

Draft the implementation plan in the conversation. Include:
- Which files will change and why
- The approach for each change (data model, UI, logic)
- Edge cases and how they'll be handled
- Any risks or tradeoffs
- For removal/deletion changes: explicitly list any tests (unit or E2E) that cover the removed feature and confirm they will be deleted as part of the plan
- If `$LEARNINGS_FILE` exists, honor every entry in its **Planning constraints (Phase 2)** section — address each relevant one explicitly in the plan

Show to user. Wait for explicit approval ("looks good", "approved", "go ahead"). If they request changes, revise and re-present. Do not proceed until approved.

> **CI-config caveat:** Phase 4 verifies the build/tests locally but never executes the CI workflow itself, so errors in CI/deploy config files surface only in Phase 7. When the plan edits CI or deploy configuration, treat it as code: give it a focused sanity pass, and ensure any version/toolchain is pinned in exactly one place (a manifest field *or* an action input, never both). Record project-specific config gotchas in the repo's `.implement-issue/LEARNINGS.md` under **Planning constraints (Phase 2)** (via the Phase 8 retrospective) or in CLAUDE.md / AGENTS.md — not here.
>
> **Dockerfile caveat:** A local `tsc`/bundler build does NOT exercise a container, so packaging and runtime errors (missing runtime deps, wrong workdir, bad CMD path) are invisible until something actually runs the image. Treat any Dockerfile in the plan as code that must be run, not inspected. In particular, for a monorepo using pnpm/yarn-PnP/npm-workspaces, the runner stage cannot just `COPY` the root `node_modules` — those package managers use isolated/symlinked layouts whose runtime deps live elsewhere (pnpm surfaces them via `packages/<pkg>/node_modules` symlinks into `.pnpm/`). The runner needs a self-contained `node_modules` (e.g. `pnpm deploy --prod`, hoisted node-linker, or equivalent). Do not trust a Dockerfile supplied verbatim in the issue.

After plan approval, if `--skip-e2e` was **not** passed, ask the user:

> "Should Phase 4 run the full E2E test suite, or build + type-check only? (Choose build-only for CSS, config, or copy-only changes where E2E adds no signal.)"

Save the answer as `$RUN_E2E` (`true` = full E2E, `false` = build + type-check only). If `--skip-e2e` was passed, `$RUN_E2E=false` and skip this question.

Once both the plan and `$RUN_E2E` are settled, persist the approved plan as a GitHub comment — this is the artifact a *different* person or session reads back on resume (mirrors the Phase 1 clarification comment; see Phase 0). Use a quoted heredoc (`'EOF'`) and substitute the literal plan text and E2E decision in place of the placeholders — do not let shell expansion touch the plan body:

```bash
gh issue comment <number> --body "$(cat <<'EOF'
## Implementation Plan

<the approved plan, verbatim>

**Run E2E tests:** <true|false>
EOF
)"
```

Then, best effort, non-blocking (see Setup in SKILL.md):

```bash
"$SKILL_DIR/scripts/state.sh" approve <number> plan
"$SKILL_DIR/scripts/state.sh" set <number> implement
```

### Checkpoint: do not auto-continue into implementation

Plan approval and implementation are not the same act, and not necessarily the same person — an architect approving the plan does not imply they (or anyone present in this session) is the one who should now write the code. Ask explicitly:

> "Plan approved and recorded. Should implementation start now in this session, or stop here for someone (possibly a different person, machine, or session) to pick it up later?"

- **Proceed now**: continue directly into Phase 3 below, same session.
- **Stop here**: the state is already correctly recorded (`stage:implement`, `gate:plan-approved`) — that's exactly what Phase 0 reads on the next invocation to resume at Phase 3 with the clarification and plan already loaded (see Phase 0's `implement`/`test`/`review`/`ci` branch). Restore `$ORIGINAL_BRANCH`, tell the user implementation is ready to start whenever (same command, this or a different session/person: `/implement-issue <number>`), and end here — this is a clean stop, not a failure to report.

---

## Phase 3: Implement

Spawn an implementation sub-agent using your platform's sub-agent tool (Coding Tier):
- **Claude Code**: Call `Agent({ description: "Implement issue #<number>", isolation: "worktree", model: "sonnet", prompt: <prompt> })`
- **Google Antigravity**: Call `invoke_subagent` with `TypeName: "self"`, `Role: "Implementer"`, `Workspace: "branch"` (or `"share"`), and the `Prompt` below.

**Prompt / Configuration:**
```
You are implementing GitHub issue #<number> on branch `<feature_branch>` (derived from the project's branching strategy — use this exact name for commits and any git operations).

Start by reading CLAUDE.md / AGENTS.md at the worktree root — it contains project conventions
(code style, TypeScript rules, framework versions, etc.) you must follow.

ISSUE TITLE: <title>
ISSUE BODY:
<body>

CLARIFICATION SUMMARY:
<summary posted in Phase 1>

APPROVED IMPLEMENTATION PLAN:
<plan from Phase 2>

YOUR TASK:
- Implement the functionality described above
- Honor every constraint and edge case named in the plan above as a hard requirement — re-read the plan's risks/edge-cases and treat each as something your code must explicitly handle (e.g. guards against conflicting browser/OS behavior), not as optional prose
- Where the clarification chose one option over a named alternative, implement ONLY the chosen option and do NOT add the rejected alternative as a fallback or convenience — re-adding it ("belt and suspenders") is a defect, not a courtesy
- Do NOT write tests — a separate agent will handle that
- Before committing, run the project's type-check / compile step and fix any
  errors it reports — do not defer type or compile errors to the test phase
- If a pre-commit reviewer you spawned has not reported back within ~3 minutes,
  proceed without it — the coordinator will run its own pre-commit review before
  opening the PR. Do not wait indefinitely. Set a mental 3-minute timer when you
  spawn it; if no result by then, commit and report "pre-commit reviewer timed out".
- Follow existing code patterns and style
- Commit your changes with a descriptive message referencing the issue: "<type>: <description> (#<number>)" where `<type>` matches the branch prefix (feat, fix, chore, docs, etc.)
- Do not open a PR

When done, report: what files you changed and a brief summary of what you implemented.
```

The agent result will include the worktree path and branch name. **Save these** — you need them for Phases 4 and 5.

Push the branch so it's visible to anyone resuming, regardless of whether you continue in this session or not — commits sitting only in a local worktree aren't recoverable by Phase 0's resume logic, which checks the remote:

```bash
git -C <worktree_path> push -u origin HEAD:<feature_branch>
```

Best effort, non-blocking: `"$SKILL_DIR/scripts/state.sh" set <number> test`

### Checkpoint: do not auto-continue into testing

Implementation and testing are not the same act, and not necessarily the same person — a developer implementing the feature does not imply they (or anyone present in this session) is the QA person who should now test it. Ask explicitly:

> "Implementation done, committed, and pushed. Should testing start now in this session, or stop here for someone (possibly a different person, machine, or session) to pick it up later?"

- **Proceed now**: continue directly into Phase 4 below, same session — you already have the worktree path and `$FEATURE_BRANCH`.
- **Stop here**: the state is already correctly recorded (`stage:test`). Restore `$ORIGINAL_BRANCH` on the main checkout — the worktree itself stays on the feature branch, which is fine; a resuming session fetches its own fresh worktree per Phase 0. Tell the user testing is ready to start whenever, and end here.

---

## Phase 4: Test

### Worktree prerequisites (run once before any build/test)

An isolated worktree starts without installed dependencies and without any
files the project ignores from version control (env/secrets/local config). Before
building or testing:
- Install the project's dependencies inside the worktree.
- Copy any version-control-ignored files the build or tests rely on from the
  main checkout into the same relative path in the worktree.
If a test fails because of missing configuration or credentials rather than a
real assertion, suspect a missing ignored file before treating it as a genuine
failure.

If `$LEARNINGS_FILE` exists, follow its **Build & test (Phase 4)** section
(commands, environment quirks, required ignored files) and append that section
verbatim to the test sub-agent prompt below.

### If the change adds or edits a Dockerfile

Before the build/test branches below, if `git diff` includes a `Dockerfile` and `docker` is available locally, run a container smoke test — `tsc`/bundler builds never exercise the image:

```bash
docker build -f <path/to/Dockerfile> -t issue-<number>-smoke <build-context>
docker run --rm -d -p <port>:<port> -e NODE_ENV=production issue-<number>-smoke
# hit the documented liveness/health endpoint, assert the expected status, then stop the container
```

If the image fails to build or the endpoint doesn't respond, treat it as a blocking issue and loop back to Phase 3 — do not defer container errors to the review agent. If `docker` is unavailable locally, note that in the test report so the reviewer knows the container path is unverified.

### If `$RUN_E2E=false` (skip the end-to-end suite)

`$RUN_E2E=false` skips only the end-to-end test suite — it does NOT mean "write
no tests." For any logic or behaviour change, still spawn the test sub-agent to
add unit tests using the project's unit-test runner, then run the build and
type-check. Skip the test sub-agent entirely only for genuinely non-logic
changes (styling, configuration, copy). Run the build and type-check directly:

```bash
npm --prefix <worktree_path> run build
npx --prefix <worktree_path> tsc --noEmit
```

Report the result. If either command fails, treat it as a blocking issue and loop back to Phase 3.

### If `$RUN_E2E=true` (full test suite)

Spawn a test sub-agent (Coding Tier) in the same worktree:
- **Claude Code**: Call `Agent({ description: "Write tests for issue #<number>", model: "sonnet", prompt: <prompt> })`
- **Google Antigravity**: Call `invoke_subagent` with `TypeName: "self"`, `Role: "Tester"`, `Workspace: "inherit"`, and the `Prompt` below.

**Prompt / Configuration:**
```
You are writing tests for changes made on branch `<feature_branch>`.

The implementation is in the git worktree at: <worktree_path>

Start by reading CLAUDE.md / AGENTS.md at <worktree_path> — it specifies the test
framework(s), test commands, and file conventions for this project. Follow those
conventions exactly. If neither is present, discover conventions by looking
at existing test files in the worktree.

ISSUE TITLE: <title>
ISSUE BODY:
<body>

CLARIFICATION SUMMARY:
<summary>

IMPLEMENTATION PLAN:
<plan>

WHAT WAS IMPLEMENTED:
<summary returned by Phase 3 agent>

YOUR TASK:
- Read the changed files in <worktree_path> to understand what was implemented
- Write tests that cover the changed/new behaviour
- Use absolute paths when reading/writing files — all work must be done inside <worktree_path>
- Run your new spec first to iterate quickly, THEN run the FULL suite (no filter,
  e.g. `npm run test:e2e`) at least once before reporting success. Specs that
  drive timing-sensitive UI (controlled inputs, focus/setTimeout, drag) often
  pass in isolation but fail under parallel load. For such specs also stress them
  with the runner's repeat flag (e.g. `--repeat-each=10`). Only report "passing"
  if the FULL suite is green — never conclude from a filtered run alone.
- After the full suite passes, also run the project's build/compile step (check
  CLAUDE.md for the command — it is the same command CI runs). Test runners
  execute code at runtime and can succeed even when the compiler rejects the
  test file; only the build pipeline catches compile-time errors in test files.
- Do NOT commit machine-specific or environment workarounds. In particular, never
  change `playwright.config.ts` (baseURL/dev-server port) to dodge a local port
  collision — that config must match CI. If the configured port is occupied
  locally, free it or run the dev server yourself on the expected port; leave the
  committed config untouched.
- Before committing, run `git diff --stat` and confirm only intended files (your
  new/changed test specs) are staged — revert any stray config changes.
- Commit your tests: "test: add coverage for <description> (#<number>)"

When done, report: what test files you created/modified and what behaviour they cover.
```

Push the branch (idempotent — safe even if nothing new was committed this phase, e.g. the `$RUN_E2E=false` build-only path):

```bash
git -C <worktree_path> push origin HEAD:<feature_branch>
```

Best effort, non-blocking: `"$SKILL_DIR/scripts/state.sh" set <number> review`

### Checkpoint: do not auto-continue into review

Testing and review are not the same act, and not necessarily the same person — a QA person confirming tests pass does not imply they (or anyone present in this session) is the developer who should now review the code. Ask explicitly:

> "Testing done, committed, and pushed. Should review start now in this session, or stop here for someone (possibly a different person, machine, or session) to pick it up later?"

- **Proceed now**: continue directly into Phase 5 below, same session.
- **Stop here**: the state is already correctly recorded (`stage:review`). Restore `$ORIGINAL_BRANCH` on the main checkout. Tell the user review is ready to start whenever, and end here.

---

## Phase 5: Review

Spawn a review sub-agent (Review Tier):
- **Claude Code**: Call `Agent({ description: "Review implementation of issue #<number>", model: "opus", prompt: <prompt> })`
- **Google Antigravity**: Call `invoke_subagent` with `TypeName: "self"`, `Role: "Reviewer"`, `Workspace: "inherit"`, and the `Prompt` below.

If `$LEARNINGS_FILE` exists, append its **Review checklist (Phase 5)** section to the prompt below as additional repo-specific review items.

**Prompt / Configuration:**
```
You are reviewing the implementation of GitHub issue #<number>.

The changes are on branch `<feature_branch>` in the worktree at: <worktree_path>

Start by reading CLAUDE.md / AGENTS.md at <worktree_path> for project conventions.

ISSUE TITLE: <title>
ISSUE BODY:
<body>

CLARIFICATION SUMMARY:
<summary>

IMPLEMENTATION PLAN:
<plan>

YOUR TASK:
- Run: git -C <worktree_path> diff <base_branch>...HEAD to see all changes
- Review implementation correctness, edge cases, code quality, and alignment with the plan
- Review tests: do they cover the changed behaviour adequately?
- Check for security issues, regressions, or missing error handling

Return one of:
A) "LGTM" with a brief summary of what was reviewed
B) A numbered list of issues, each with: severity (blocking/minor), file:line, description, and suggested fix

Be strict — minor issues are worth flagging even if not blocking.
```

### Persist the review outcome (before acting on it)

The reviewer's result comes back only in *your* (the coordinator's) context. Unlike the implementation and tests, it is not committed to the branch — so no resuming session can reconstruct it from `git`, and it has no durable home unless you give it one. Persist it now, before Phase 6, as a GitHub **issue** comment (the PR does not exist yet), mirroring the clarification and plan artifacts so it is both user-visible and reloadable on resume:

```bash
gh issue comment <number> --body "$(cat <<'EOF'
## Review Findings

<verbatim reviewer output: either "LGTM — <summary>" or the numbered list of issues,
each with severity (blocking/minor), file:line, description, and suggested fix>
EOF
)"
```

This is the artifact Phase 0 reloads when resuming at stage `review`/`ci`, and the exact text Phase 6 must show the user. Do not paraphrase it away or leave it only in conversation context.

---

## Phase 6: Decision

### If review returns blocking issues:

Fix them automatically — do not ask the user. Spawn a fix sub-agent (Coding Tier) in the same worktree:
- **Claude Code**: Call `Agent({ description: "Fix blocking review issues for issue #<number>", model: "sonnet", prompt: <prompt> })`
- **Google Antigravity**: Call `invoke_subagent` with `TypeName: "self"`, `Role: "Fixer"`, `Workspace: "inherit"`, and the `Prompt` below.

**Prompt / Configuration:**
```
You are fixing blocking issues found during code review of GitHub issue #<number>.

The changes are on branch `<feature_branch>` in the worktree at: <worktree_path>

Start by reading CLAUDE.md / AGENTS.md at <worktree_path> for project conventions.

ISSUE TITLE: <title>
APPROVED IMPLEMENTATION PLAN:
<plan>

BLOCKING ISSUES TO FIX:
<numbered list of blocking issues from the review agent, each with file:line, description, and suggested fix>

YOUR TASK:
- Fix every blocking issue listed above
- Do not change behaviour beyond what is needed to resolve the listed issues
- Follow existing code patterns and style
- Commit your fixes: "fix: address blocking review issues (#<number>)"

When done, report: which issues you fixed and what you changed.
```

After the fix agent completes, loop back to **Phase 5** to re-review. If the re-review returns only minor issues or LGTM, proceed accordingly below.

If the review still returns blocking issues after 3 fix iterations, restore the original branch and stop:

```bash
git checkout $ORIGINAL_BRANCH
```

Report the situation to the user — it likely needs manual investigation.

### If review returns only minor issues:

Reproduce the numbered minor findings **in full** — verbatim from the `## Review Findings` comment you just posted — inside the *same message* where you ask how to proceed. Do not put them in a separate note before the question: text emitted between or before tool calls may never be surfaced to the user, so the findings must live in the final user-facing message alongside the question, not upstream of it. The user has to be able to read every finding and the question in one place:

> Minor issues found:
>
> <the numbered list, verbatim>
>
> Should I fix these too, or proceed to the PR?

### If review returns LGTM:

0. Re-verify the issue is still actionable before doing any push (sub-agents can run for many minutes, during which another PR may close it):

```bash
gh issue view <number> --json state,stateReason
gh pr list --search "<number> in:title" --state merged --json number,title
```

If the issue is now CLOSED or a merged PR already addresses it, STOP: do not push or open a PR. Delete the local branch, remove the worktree, restore `$ORIGINAL_BRANCH`, and report the duplicate to the user.

1. Rebase the branch onto the latest base branch so the PR has no merge conflicts:

```bash
git -C <worktree_path> fetch origin
git -C <worktree_path> rebase origin/<base_branch>   # run as its own step — do NOT pipe to tail/head (it masks the exit code)
# Only if the rebase succeeded (no conflict markers, no rebase-in-progress) push:
git -C <worktree_path> push --force-with-lease origin HEAD:<feature_branch>
```
On conflict, resolve, `git rebase --continue`, then push — never chain the push after a piped rebase.

If the rebase produces conflicts you cannot auto-resolve, stop and report the specific conflicting files to the user before proceeding.

2. Create the PR from the worktree or main repo (branch already exists in git):

```bash
gh pr create \
  --title "<issue title>" \
  --head "<feature_branch>" \
  --body "$(cat <<'EOF'
## Summary

<2-3 bullet summary of what was implemented>

Closes #<number>

## Test plan

<bullet list of what the new tests cover>

🤖 Generated with AI Agentic Coding (via Claude Code / Google Antigravity)
EOF
)"
```

2. Post the PR URL in the conversation.
3. Proceed to **Phase 7**.

> **Note:** If the fix was committed directly to the base branch instead of via PR, the `Closes #<number>` keyword won't auto-trigger. Close the issue manually: `gh issue close <number> --repo <owner/repo> --comment "Fixed in <sha> — <one-line summary>."`

---

## Phase 7: CI Watch & Fix

Best effort, non-blocking: `"$SKILL_DIR/scripts/state.sh" set <number> ci`

After the PR is created, monitor GitHub CI and fix any failures. Loop until all checks pass (cap at 5 fix iterations to avoid infinite loops).

### Step 1 — Wait for CI to complete

Get the most recent run on the PR branch and wait for it to finish:

```bash
# Get the run ID for the PR
gh run list --branch <feature_branch> --limit 1 --json databaseId,status,conclusion

# Watch it (blocks until done)
gh run watch <run-id>

# Then get the final conclusion
gh run view <run-id> --json conclusion,status
```

### Step 2 — If all checks pass → done

```bash
gh pr checks <pr-number>
```

If all checks show `pass`, restore the original branch:

```bash
git checkout $ORIGINAL_BRANCH
```

Best effort, non-blocking: `"$SKILL_DIR/scripts/state.sh" set <number> done`

Then re-query the PR's actual state immediately before composing the success summary — sub-agents and CI watches can run for many minutes, during which the user may merge or close the PR themselves. Do NOT assume the PR is still open just because you opened it:

```bash
gh pr view <pr-number> --json state,mergedAt,mergedBy,url
```

Word the announcement to match the queried `state`:
- `MERGED` → "PR #<n> has been **merged** (by <mergedBy>): <url>" — do not say it is open or awaiting review.
- `CLOSED` (not merged) → "PR #<n> was **closed** without merging: <url>" — flag this, since the implementation did not ship.
- `OPEN` → "PR #<n> is open and all CI checks pass: <url>".

### Step 3 — If checks fail → spawn a CI fix agent

Get the full failure logs first:

```bash
gh run view <run-id> --log-failed
```

If `$LEARNINGS_FILE` exists, check its **CI quirks (Phase 7)** section for a known failure signature matching these logs — a documented flake with a proven fix beats rediscovering it — and append the section to the fix-agent prompt below.

Then spawn a fix sub-agent (Coding Tier) in the same worktree:
- **Claude Code**: Call `Agent({ description: "Fix CI failures for issue #<number>", model: "sonnet", prompt: <prompt> })`
- **Google Antigravity**: Call `invoke_subagent` with `TypeName: "self"`, `Role: "CI Fixer"`, `Workspace: "inherit"`, and the `Prompt` below.

**Prompt / Configuration:**
```
You are fixing CI failures for a PR on branch `<feature_branch>`.

Worktree path: <worktree_path>

Start by reading CLAUDE.md / AGENTS.md at <worktree_path> — it specifies the test
framework, test commands, and file layout for this project. Use it to locate test
files and understand how tests are run.

CONTEXT — what was implemented:
<brief summary of the feature from Phase 3>

FAILED CI LOGS:
<paste the full output of `gh run view <run-id> --log-failed`>

YOUR TASK:
1. Sync the worktree with any commits pushed by previous fix iterations:
   ```bash
   git -C <worktree_path> fetch origin
   git -C <worktree_path> rebase origin/<feature_branch>
   ```
2. Read the failing log carefully — identify the exact file, line, and error for each failure
3. Read the failing test file(s) and the relevant source files in <worktree_path> to understand the current structure
4. Fix the root cause — prefer fixing tests only if the implementation is correct; fix the implementation if it is genuinely wrong
5. Use absolute paths — all work inside <worktree_path>
6. Commit the fix: "fix: address CI failures (#<number>)"
7. Push: git -C <worktree_path> push --force-with-lease origin HEAD:<feature_branch>

When done, report: which checks failed, what the root cause was, and what you changed.
```

### Step 4 — Wait for the new CI run and loop

After the fix agent pushes, a new CI run will trigger. Go back to Step 1 and repeat.

If CI still fails after 5 fix iterations, restore the original branch and stop:

```bash
git checkout $ORIGINAL_BRANCH
```

Report the situation to the user — it likely needs manual investigation.

---

## Phase 8: Retrospective

After CI passes (or after a stop-and-report exit), run a retrospective on this implementation session, propose targeted improvements, and route each one to its proper destination — the target project's learnings file or the skill repo's issue tracker. Users of this skill never edit the skill directly (see "Project learnings" in SKILL.md).

### Step 1 — Collect signals

Tally the following from this session:

| Signal | Count |
|--------|-------|
| Clarification rounds (back-and-forth before plan) | N |
| Plan revision cycles (user rejected/changed plan) | N |
| Review loop iterations (Phase 5 → 6 → 5) | N |
| CI fix iterations (Phase 7 loop) | N |
| Stop-and-report exits (rebase conflicts, review cap, CI cap) | N |

### Step 1b — Record the outcome ledger entry

Best effort, non-blocking (same posture as the `state.sh` calls elsewhere): persist this run's signals into `.implement-issue/outcomes.jsonl` in the target repo via `scripts/record-outcome.sh`. If the call fails (no write access, disk issue, offline), log a warning and continue — do not let it stop the retrospective. This step exists so a future change-sizing step has a reference class of actual past runs to draw on; it stores raw signals only, no size judgment.

**First, capture whether the ledger is being seeded from empty** — do this *before* the `record-outcome.sh` write below, because that write adds this run's entry and an "is the ledger empty?" check afterward would never observe an empty ledger:

```bash
# 0 when the ledger is absent or empty, else its current line count
LEDGER_LINES=$( [[ -s .implement-issue/outcomes.jsonl ]] && wc -l < .implement-issue/outcomes.jsonl | tr -d ' ' || echo 0 )
```

The record combines the Step 1 tallies above with the PR's diff stats:

```bash
# outcome: from the Phase 7 final `gh pr view --json state,mergedAt` result
#   MERGED -> merged, CLOSED (not merged) -> closed; on a stop-and-report
#   exit (rebase conflict, review cap, CI cap) use aborted instead
gh pr view <pr-number> --json state,mergedAt,additions,deletions,files,commits

# files_changed / diff_loc / commits: from the PR stats above, or equivalently
git -C <worktree_path> diff --stat <base_branch>...HEAD

# wall_clock_hours: issue createdAt -> PR mergedAt, in hours
gh issue view <number> --json createdAt

"$SKILL_DIR/scripts/record-outcome.sh" <number> \
  title="<issue title>" \
  pr=<pr-number> \
  labels="<issue's semantic labels, comma-separated — its stage:*/gate:* bookkeeping labels are not part of this>" \
  outcome=merged \
  plan_file_count=<count of files named in the approved Phase 2 plan> \
  files_changed=<from gh pr view --json files> \
  diff_loc=<additions + deletions from gh pr view> \
  commits=<from gh pr view --json commits> \
  clarify_rounds=<Step 1 tally> \
  plan_revisions=<Step 1 tally> \
  review_loops=<Step 1 tally> \
  ci_fixes=<Step 1 tally> \
  wall_clock_hours=<issue createdAt -> PR mergedAt, in hours>
```

**One-time backfill offer (best-effort, non-blocking — same posture as above).** If this run just seeded a previously-empty ledger (`LEDGER_LINES` was `0`) AND the repo has reconstructable history — at least one already-closed issue carrying a `stage:*` label — then the ledger is missing every issue implemented before it existed. Offer (never force) a one-time backfill so the reference class isn't permanently empty:

```bash
if [[ "$LEDGER_LINES" -eq 0 ]] && \
   [[ -n "$(gh issue list --state closed --json number,labels \
             --jq '.[] | select(.labels | map(.name) | any(startswith("stage:"))) | .number' 2>/dev/null)" ]]; then
  "$SKILL_DIR/scripts/backfill-outcomes.sh" run --dry-run   # preview what would be seeded
fi
```

Show the user the dry-run preview, explain the ledger was empty but backfillable from existing history, and ask whether to run `"$SKILL_DIR/scripts/backfill-outcomes.sh" run` (which upserts the reconstructed records). This is an offer, not an action — same best-effort posture as `record-outcome.sh` above; a `gh` failure must never stop the retrospective. If either condition is false (a fresh repo with no history, or a ledger that already has entries) or the user declines, skip silently — this must never nag on a normal run.

On a stop-and-report exit (no PR merged), still write a record with `outcome=aborted` and whatever fields are actually known (e.g. `pr`, `diff_loc`, and `wall_clock_hours` may be unavailable if no PR was ever opened) — leave the rest null rather than guessing.

### Step 2 — Diagnose bottlenecks

For each signal with count ≥ 1, identify the root cause. Map each cause to one of these categories:

- **Clarify gap** — the issue lacked context that a better Phase 1 checklist would have surfaced
- **Plan gap** — an edge case or constraint was not in the plan and surfaced during review or CI
- **Agent context gap** — a sub-agent lacked information it needed (missing CLAUDE.md/AGENTS.md field, missing worktree path, etc.)
- **Skill rule gap** — the skill's key rules didn't cover a decision the agent had to make ad-hoc
- **Workflow step gap** — WORKFLOW.md was silent on how to handle a situation that came up

### Step 3 — Propose changes, classified by scope

For each diagnosed gap, draft a concrete, minimal change that would prevent the same friction next time, and classify its scope:

- **`project`** — tied to this repo's technology, conventions, or CI, and expressible as *content* under one of the fixed headings in `.implement-issue/LEARNINGS.md`: **Clarify checklist (Phase 1)**, **Planning constraints (Phase 2)**, **Build & test (Phase 4)**, **Review checklist (Phase 5)**, **CI quirks (Phase 7)**.
- **`skill`** — a gap in the skill's own phases, rules, or prompts that would recur in any project.

A finding that is project-specific but fits none of the LEARNINGS.md headings is trying to change the flow — never store it as a learning. Either reframe it as phase content under a heading, or (if the flow itself is genuinely wrong) classify it as `skill` so the maintainers decide.

Format each proposal as:

```
[PROPOSAL N]
Scope: project | skill
Target: <LEARNINGS.md section heading> | <SKILL.md/WORKFLOW.md + section heading or line reference>
Change: <add | edit | remove>
Reason: <one sentence — what friction this prevents>
Evidence: <which Step 1 signal fired (with count) and the Step 2 root-cause category>

--- before ---
<existing text, or "(nothing — new addition)">
--- after ---
<proposed text>
```

Only propose changes that are directly supported by what happened in this session. Do not invent hypothetical improvements.

### Step 4a — Project-scoped proposals → the target project's learnings file

Show the project-scoped proposals to the user in a single message. Ask:

> "Found N project-specific learning(s) from this session. Store all, store selectively, or skip?"

For each accepted proposal:

1. If `.implement-issue/LEARNINGS.md` doesn't exist at the project root, create it from `$SKILL_DIR/templates/LEARNINGS.md`.
2. Append the entry under its target section heading, ending with provenance: `(issue #<number>, <YYYY-MM-DD>, skill@$(git -C "$SKILL_DIR" rev-parse --short HEAD))`.
3. Commit in the project repo:

```bash
git add .implement-issue/LEARNINGS.md
git commit -m "docs: implement-issue learnings from issue #<number>"
```

If the commit fails (e.g. detached state, hooks), report what was written and where — the file content is the deliverable; the commit is best-effort.

### Step 4b — Skill-scoped proposals → issue on the skill repo

The default channel is an **issue, not a PR**: a single session is weak evidence for changing the skill, and the issue tracker is where recurrence across projects and users becomes visible. Maintainers promote a finding to an actual change once the pattern is strong enough.

For each skill-scoped proposal (after showing it to the user and getting their OK to file it):

1. Search for an existing report of the same finding:

```bash
gh issue list --repo trendlik/agentic-engineering --label retrospective --state open --search "<keywords from the proposal>"
```

2. If a matching issue exists, add the evidence as a comment (recurrence is the signal maintainers are waiting for). If not, create one:

```bash
gh issue create --repo trendlik/agentic-engineering --label retrospective \
  --title "retrospective: <one-line finding>" \
  --body "<evidence block below>"
```

(If the `retrospective` label doesn't exist or can't be applied, create the issue without it.) Evidence block format — same for new issues and recurrence comments:

```
## Retrospective evidence

**Project:** <owner/repo> · **Issue:** #<number> · **Date:** <YYYY-MM-DD> · **Skill commit:** <short-sha>
**Signal:** <which Step 1 signal fired, with count>
**Diagnosis:** <Step 2 root-cause category>

<the full [PROPOSAL] block from Step 3, verbatim — including the before/after diff>
```

3. If the user has no access to the skill repo (`gh issue create` fails with a permission error), print the evidence block and ask them to relay it to the skill's maintainers.

**Maintainer path (exception):** only when the user has push access to the skill repo — check with `gh repo view trendlik/agentic-engineering --json viewerPermission` (`WRITE` or `ADMIN`) — offer a choice: file the issue as above (default), or apply the edit directly to `$SKILL_DIR` and commit:

```bash
git -C "$SKILL_DIR" commit -am "docs: retrospective improvements from issue #<number>"
```

Never apply directly without both the access *and* the user explicitly choosing it; when in doubt, file the issue.
