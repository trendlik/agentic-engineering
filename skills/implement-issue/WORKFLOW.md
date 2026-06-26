# implement-issue — Detailed Workflow

## Phase 1: Clarify

1. Capture the current branch so it can be restored when the skill exits:

```bash
ORIGINAL_BRANCH=$(git branch --show-current)
```

**Save `$ORIGINAL_BRANCH`** — restore it on every exit path (success or stop-and-report).

2. Run: `gh issue view <number> --json title,body,labels,comments`
3. Read the issue carefully. Identify anything ambiguous: unclear acceptance criteria, missing context, edge cases not addressed, scope questions.
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

---

## Between Phase 1 and Phase 2: Sync local branch and derive branch name

Before drafting the plan, detect the base branch, derive the feature branch name from the project's branching strategy, and ensure the local branch is up to date so the plan reflects the current codebase.

### Step 1 — Detect base branch

```bash
BASE_BRANCH=$(git remote show origin | grep "HEAD branch" | awk '{print $NF}')
git fetch origin
git rebase origin/$BASE_BRANCH
```

**Save `$BASE_BRANCH`** — you will need it in Phases 6 and 7.

If the rebase fails, stop and report the conflicting files to the user — do not proceed until the base branch is clean.

### Step 2 — Read CLAUDE.md / AGENTS.md and detect branching strategy

Read `CLAUDE.md` or `AGENTS.md` now to understand project conventions (test commands, framework, paths, TypeScript rules, etc.) — you will pass this context to sub-agents.

While reading CLAUDE.md / AGENTS.md, look for an explicit branch naming pattern. Common forms:
- `feat/<number>-<slug>`, `fix/<number>-<slug>`, `chore/<number>-<slug>`
- `feature/<slug>`, `bugfix/<slug>`
- `<type>/<number>`, `issue-<number>`

If CLAUDE.md or AGENTS.md documents a pattern, follow it exactly.

### Step 3 — Derive the feature branch name

If CLAUDE.md or AGENTS.md defines a naming convention, apply it. Otherwise use this heuristic:

1. Determine the **type prefix** from the issue labels:
   - `bug` / `fix` / `defect` → `fix`
   - `feature` / `enhancement` / `feat` → `feat`
   - `chore` / `maintenance` / `refactor` → `chore`
   - `docs` → `docs`
   - anything else / no labels → `feat`

2. Slugify the issue title: lowercase, replace spaces and special chars with `-`, trim to 40 chars, strip leading/trailing `-`.

3. Compose: `<type>/<number>-<slug>` (e.g. `feat/42-add-user-avatar`)

4. Fall back to `issue-<number>` only if slugification produces an empty string.

**Save `$FEATURE_BRANCH`** — every sub-agent prompt and git command must use this value, not a hardcoded `issue-<number>`.

---

## Phase 2: Plan

Draft the implementation plan in the conversation. Include:
- Which files will change and why
- The approach for each change (data model, UI, logic)
- Edge cases and how they'll be handled
- Any risks or tradeoffs

Show to user. Wait for explicit approval ("looks good", "approved", "go ahead"). If they request changes, revise and re-present. Do not proceed until approved.

> **CI-config caveat:** Phase 4 verifies the build/tests locally but never executes the CI workflow itself, so errors in CI/deploy config files surface only in Phase 7. When the plan edits CI or deploy configuration, treat it as code: give it a focused sanity pass, and ensure any version/toolchain is pinned in exactly one place (a manifest field *or* an action input, never both). Record project-specific config gotchas in the repo's own docs (e.g. CLAUDE.md or AGENTS.md), not here.
>
> **Dockerfile caveat:** A local `tsc`/bundler build does NOT exercise a container, so packaging and runtime errors (missing runtime deps, wrong workdir, bad CMD path) are invisible until something actually runs the image. Treat any Dockerfile in the plan as code that must be run, not inspected. In particular, for a monorepo using pnpm/yarn-PnP/npm-workspaces, the runner stage cannot just `COPY` the root `node_modules` — those package managers use isolated/symlinked layouts whose runtime deps live elsewhere (pnpm surfaces them via `packages/<pkg>/node_modules` symlinks into `.pnpm/`). The runner needs a self-contained `node_modules` (e.g. `pnpm deploy --prod`, hoisted node-linker, or equivalent). Do not trust a Dockerfile supplied verbatim in the issue.

After plan approval, if `--skip-e2e` was **not** passed, ask the user:

> "Should Phase 4 run the full E2E test suite, or build + type-check only? (Choose build-only for CSS, config, or copy-only changes where E2E adds no signal.)"

Save the answer as `$RUN_E2E` (`true` = full E2E, `false` = build + type-check only). If `--skip-e2e` was passed, `$RUN_E2E=false` and skip this question.

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
- Follow existing code patterns and style
- Commit your changes with a descriptive message referencing the issue: "<type>: <description> (#<number>)" where `<type>` matches the branch prefix (feat, fix, chore, docs, etc.)
- Do not open a PR

When done, report: what files you changed and a brief summary of what you implemented.
```

The agent result will include the worktree path and branch name. **Save these** — you need them for Phases 4 and 5.

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

---

## Phase 5: Review

Spawn a review sub-agent (Review Tier):
- **Claude Code**: Call `Agent({ description: "Review implementation of issue #<number>", model: "opus", prompt: <prompt> })`
- **Google Antigravity**: Call `invoke_subagent` with `TypeName: "self"`, `Role: "Reviewer"`, `Workspace: "inherit"`, and the `Prompt` below.

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

Show the findings to the user and ask: "Minor issues found — should I fix these too, or proceed to the PR?"

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

After CI passes (or after a stop-and-report exit), run a retrospective on this implementation session and propose targeted improvements to the skill's own documentation.

### Step 1 — Collect signals

Tally the following from this session:

| Signal | Count |
|--------|-------|
| Clarification rounds (back-and-forth before plan) | N |
| Plan revision cycles (user rejected/changed plan) | N |
| Review loop iterations (Phase 5 → 6 → 5) | N |
| CI fix iterations (Phase 7 loop) | N |
| Stop-and-report exits (rebase conflicts, review cap, CI cap) | N |

### Step 2 — Diagnose bottlenecks

For each signal with count ≥ 1, identify the root cause. Map each cause to one of these categories:

- **Clarify gap** — the issue lacked context that a better Phase 1 checklist would have surfaced
- **Plan gap** — an edge case or constraint was not in the plan and surfaced during review or CI
- **Agent context gap** — a sub-agent lacked information it needed (missing CLAUDE.md/AGENTS.md field, missing worktree path, etc.)
- **Skill rule gap** — the skill's key rules didn't cover a decision the agent had to make ad-hoc
- **Workflow step gap** — WORKFLOW.md was silent on how to handle a situation that came up

### Step 3 — Propose documentation changes

For each diagnosed gap, draft a concrete, minimal edit to SKILL.md or WORKFLOW.md that would prevent the same friction next time. Format each proposal as:

```
[PROPOSAL N]
File: SKILL.md | WORKFLOW.md
Location: <section heading or line reference>
Change: <add | edit | remove>
Reason: <one sentence — what friction this prevents>

--- before ---
<existing text, or "(nothing — new addition)">
--- after ---
<proposed text>
```

Only propose changes that are directly supported by what happened in this session. Do not invent hypothetical improvements.

### Step 4 — Present and apply

Show all proposals to the user in a single message. Ask:

> "Found N documentation improvement(s) based on this session. Apply all, apply selectively, or skip?"

If the user approves (all or selective), apply the accepted edits directly to the skill files using the Edit tool. Commit the changes:

```bash
# For Claude Code:
git -C ~/.claude/skills/implement-issue commit -am "docs: retrospective improvements from issue #<number>"

# For Google Antigravity:
git -C ~/.gemini/config/skills/implement-issue commit -am "docs: retrospective improvements from issue #<number>"
```

If the repository is not git-tracked or the commit fails, report what was changed and where.
