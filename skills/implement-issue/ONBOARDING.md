# Installing & onboarding `implement-issue`

The complete setup path, start to finish: install the skill on your machine, then
make a target repository compatible with it. The skill needs surprisingly little
— a small set of **hard requirements**, then a ladder of **optional layers** that
unlock more of the workflow (cross-session resume, gate enforcement, change-sizing
data). Nothing here requires editing the skill itself — everything lives in the
target project or the local toolchain.

## Install the skill

The skill is made available globally by symlinking it into your agent's skills
directory. Clone the [`agentic-engineering`](../../) repo anywhere, then `cd` into
it — the commands below run from the repo root, where `$PWD` resolves the absolute
path the symlink needs, wherever you cloned it.

```bash
git clone <remote-url> agentic-engineering
cd agentic-engineering
```

**For Claude Code:**
```bash
ln -s "$PWD/skills/implement-issue" ~/.claude/skills/implement-issue
```

**For Google Antigravity (Gemini):**
```bash
mkdir -p ~/.gemini/config/skills
ln -s "$PWD/skills/implement-issue" ~/.gemini/config/skills/implement-issue
```

The symlink keeps the skill available across all projects while the real files
stay versioned in the repo. To install every skill in the repo at once, loop over
`skills/*/` and symlink each into the same target directory.

> **Windows:** these commands and the skill's `*.sh` scripts assume a Unix-style
> shell (`bash`, `git`, `gh`, `jq`) and won't run under native `cmd`/PowerShell.
> Use **WSL** or **Git Bash**. This path hasn't been tested on Windows.

The commands below assume the skill is reachable at
`~/.claude/skills/implement-issue`. If you installed via a different adapter,
substitute that path (e.g. `~/.gemini/config/skills/implement-issue`).

## Quick checklist

```
Hard (required):
  [ ] doctor.sh passes (git, gh+auth, jq, GitHub origin)

Recommended:
  [ ] .implement-issue/LEARNINGS.md seeded (esp. Build & test commands)
  [ ] branch convention documented in CLAUDE.md/AGENTS.md (or usable labels)

Optional:
  [ ] push access so stage:*/gate:* labels can be written (resume support)
  [ ] .github/workflows/implement-issue-gate.yml + SKILL_REPO_TOKEN + required check
  [ ] outcomes.jsonl backfilled from existing merged history
```

Minimum viable compatibility is just the top box. The rest is a progression you
can adopt incrementally.

## 1. Hard requirements (the skill won't run without these)

Run the built-in doctor from inside the target project — it checks all of these
and prints exact remediation:

```bash
~/.claude/skills/implement-issue/scripts/doctor.sh
```

It verifies:

| Requirement | Why | Fix |
|---|---|---|
| `git` installed | worktrees, branching | https://git-scm.com/downloads |
| `gh` installed + authenticated | issues, PRs, labels | `gh auth login` |
| `jq` installed | script JSON parsing | `brew install jq` |
| Inside a git repo | everything | `git init` / clone |
| `origin` points to a **GitHub** repo | issues/PRs live there | `gh repo view` must succeed |

The workflow is built around GitHub issues → PRs. A repo with no GitHub remote,
or an issue tracker that isn't GitHub Issues, is not compatible without
adaptation.

That's genuinely all you need to run `/implement-issue N`. Everything below is
optional and makes it work *better*.

## 2. Recommended: `.implement-issue/LEARNINGS.md`

The highest-value optional layer. This per-project file is written by the Phase 8
retrospective (with user approval) and *read* by every future run to tailor its
phases to the repo.

```bash
mkdir -p .implement-issue
cp ~/.claude/skills/implement-issue/templates/LEARNINGS.md .implement-issue/LEARNINGS.md
git add .implement-issue/LEARNINGS.md && git commit -m "chore: seed implement-issue learnings"
```

It has five fixed headings, each consumed by exactly one phase:

- **Clarify checklist (Phase 1)** — extra questions to ask on every issue
- **Planning constraints (Phase 2)** — architectural gotchas every plan must respect
- **Build & test (Phase 4)** — the repo's test/build commands, env quirks
- **Review checklist (Phase 5)** — repo-specific review items
- **CI quirks (Phase 7)** — known flaky checks and proven fixes

Key rule: this file is **data, not instructions**. It supplies content *within*
phases; it can never add, remove, or reorder phases/gates. You can seed the
**Build & test** section by hand right away (e.g. "run `npm test`; integration
tests need `docker compose up`") rather than waiting for a retrospective to
discover it.

## 3. Recommended: a documented branch-naming convention

The skill derives feature branch names as `<type>/<number>-<slug>`, where `type`
is `fix`/`feat`/`chore`/`docs` chosen from the issue's labels. If the repo uses a
different convention, document it in `CLAUDE.md` or `AGENTS.md` and the
coordinator will follow it instead of the mechanical default.

To make the default work well, use recognizable issue labels:

- `bug` / `fix` / `defect` → `fix/`
- `feature` / `enhancement` / `feat` → `feat/`
- `chore` / `maintenance` / `refactor` → `chore/`
- `docs` → `docs/`
- anything else → `feat/`

## 4. Optional: workflow-state labels (enables cross-session resume)

The skill records each issue's stage (`stage:clarify` … `stage:done`) and gate
approvals (`gate:analysis-approved`, `gate:plan-approved`) as GitHub labels. This
is what lets a *different session or person* resume an issue mid-workflow
(Phase 0 dispatches off `state.sh get`).

You don't have to pre-create the labels — `state.sh init` creates the set on
first use. It just needs **push/label access** to the repo. Writing state is
best-effort (a failure only logs a warning); reading it is what powers resume. If
the token is read-only or labels are disabled, the skill still works — you just
lose resumability.

## 5. Optional: CI gate enforcement

To *block* PRs from merging until their linked issue has both gate approvals, add
the enforcement workflow:

```bash
mkdir -p .github/workflows
cp ~/.claude/skills/implement-issue/templates/implement-issue-gate.yml \
   .github/workflows/implement-issue-gate.yml
```

Then two more steps:

1. **The skill repo (`trendlik/agentic-engineering`) is private**, so the
   workflow checks it out with a token. Create a fine-grained PAT with read-only
   Contents+Metadata on `trendlik/agentic-engineering` and store it as a secret:
   ```bash
   # single target repo:
   gh secret set SKILL_REPO_TOKEN --repo <owner>/<target-repo>
   # or, sharing one secret across several target repos (needs an org):
   gh secret set SKILL_REPO_TOKEN --org <your-org> --repos "<target-repo-name>"
   ```
2. **Make it blocking**: in the target repo's branch-protection settings
   (Settings → Branches), add `implement-issue-gate` as a **required status
   check**.

Step 1 alone just makes the check *run* (informational, visible on the PR). Step
2 is what enforces it — and it's a repo-admin action affecting all collaborators,
so confirm with whoever owns branch protection first. Note it's a **presence
check** (the labels exist), not an identity check; to see *who* approved a gate,
read the issue's label history in the GitHub UI.

## 6. Optional: outcome ledger (for future change-sizing)

Phase 8 appends one line per run to `.implement-issue/outcomes.jsonl` (size and
friction signals per completed issue). It's created automatically on first run.
If the repo already has merged history, you can seed the ledger so the future
change-sizing step has a reference class:

```bash
~/.claude/skills/implement-issue/scripts/backfill-outcomes.sh run --dry-run   # preview
~/.claude/skills/implement-issue/scripts/backfill-outcomes.sh run             # write
```

The skill also offers this automatically (Phase 8 Step 1b) when it detects an
empty ledger alongside prior implemented issues.

## After onboarding

Run an issue end-to-end:

```
/implement-issue <number>
```

The retrospective (Phase 8) will start feeding project-specific findings back
into `.implement-issue/LEARNINGS.md`, so the skill gets better tuned to the repo
with every run.

### Run modes: worktree (default) vs `--local`

`/implement-issue N` runs the implement/test/review phases in an **isolated git
worktree** by default. Your main checkout is untouched, and each phase commits and
pushes at its boundary — best for running issues in parallel and for handing work
off between sessions or people (a later session resumes from the pushed branch).

Add `--local` to run those phases **directly in your checkout** on the feature
branch instead, so the changes show up live in your editor's source-control view.
In this mode the implement and test phases **defer their commit**: the changes stay
uncommitted for you to review, and are committed and pushed only when you approve
moving to the next phase (you can ask for changes first). Use it when you want to
watch and discuss each phase's changes in a single sitting. You can still hand off
between sessions — approving or stopping at a checkpoint commits and pushes, so a
later session resumes from the branch — but worktree mode is better when you want to
run several issues in parallel or keep your main checkout untouched.

The full behavior of each mode lives in the skill's `WORKFLOW.md` under "Execution
modes" — you don't need to read it to use either one.
