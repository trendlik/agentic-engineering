---
name: onboard-implement-issue
description: An interactive, checkpoint-driven skill to onboard a target repository onto implement-issue. Drives per-repo setup (doctor check, LEARNINGS.md seeding, branch conventions, permission allowlist sync, CI gate enforcement, outcome backfill) using ONBOARDING.md as source of truth. Use when the user says "onboard a repo onto implement-issue", "make this repo compatible with implement-issue", or "/onboard-implement-issue".
version: 1.1.0
---

# onboard-implement-issue

An interactive, checkpoint-driven driver that walks a user through making a target repository compatible with the `implement-issue` skill.

## Quick start

```
/onboard-implement-issue
```

Run once per repository, from the root directory of the target repository you wish to onboard onto `implement-issue`.

## Setup: resolve `$SKILL_DIR` and target repository root

Before executing the onboarding flow, resolve the `implement-issue` skill directory. This candidate loop ensures compatibility across platform adapters (Claude Code and Google Antigravity), and checks each adapter's project-scoped pin before its global default — a project can pin a specific released version of the skill via its own `<project>/.claude/skills/implement-issue` (Claude Code) or `<project>/.agents/skills/implement-issue` (Antigravity) symlink, and each adapter resolves its project-scoped location before its global one:

```bash
_repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
_candidates=()
[[ -n "$_repo_root" ]] && _candidates+=(
  "$_repo_root/.claude/skills/implement-issue"
  "$_repo_root/.agents/skills/implement-issue"
)
_candidates+=(~/.claude/skills/implement-issue ~/.gemini/config/skills/implement-issue)
for candidate in "${_candidates[@]}"; do
  [[ -d "$candidate/scripts" ]] && SKILL_DIR="$candidate" && break
done
```

Outside a git repo, `_repo_root` is empty and the project candidates are
skipped, degrading cleanly to the global fallback. Bash follows a symlinked
directory transparently, so no `readlink`/`realpath` gymnastics are needed
(those differ between BSD and GNU userlands anyway).

Verify that `$SKILL_DIR` was successfully resolved and that `$SKILL_DIR/ONBOARDING.md`, `$SKILL_DIR/scripts/`, and `$SKILL_DIR/templates/` exist and are readable. If `$SKILL_DIR` cannot be found or required assets are missing, display a clear error message explaining that `implement-issue` must be installed first (referencing the installation instructions in `ONBOARDING.md`), and **stop immediately**.

Also resolve the target repository root:
```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
```
If not inside a git repository, `doctor.sh` in Step 1 will detect it and provide remediation.

## Guardrails & Invariants

- **Single source of truth**: `ONBOARDING.md` at `$SKILL_DIR/ONBOARDING.md` is the authoritative specification for per-repo onboarding. This skill is a thin interactive driver that delegates deterministic checks to existing scripts (`doctor.sh`, `sync-permissions.sh`, `backfill-outcomes.sh`) and templates (`LEARNINGS.md`, `implement-issue-gate.yml`). It does not duplicate documentation prose, preventing drift when `ONBOARDING.md` updates.
- **Stage, never commit**: When this skill creates or modifies target repository files (such as `.implement-issue/LEARNINGS.md` or `.github/workflows/implement-issue-gate.yml`), it stages them with `git add` but **NEVER commits**. File commit is left to human review.
- **Hard requirement gate**: If Step 1 (`doctor.sh`) fails, relay the remediation instructions verbatim and **STOP execution immediately**. Do not proceed to subsequent steps.
- **Never clobber existing files**: Always check if target files already exist before creating or writing to them. If a file exists, do not overwrite it — offer to review, augment, or skip based on user confirmation.
- **Adapter-neutral commands and checkpoints**: Commands shown or executed must use the resolved `$SKILL_DIR` path rather than hardcoded `~/.claude/...` paths. Interactivity must use your platform's question/checkpoint mechanism.
- **Scope boundary**: This skill is strictly for first-time repository onboarding. It does NOT perform skill version upgrades (vN → vN+1 upgrades are handled by a separate upgrade skill).

## Checkpoint Flow

Announce each step as you enter it: **"--- Step N: Name ---"**

### Step 1: Hard requirements

*Source of truth: ONBOARDING.md §1*

1. Run `$SKILL_DIR/scripts/doctor.sh` from the target repository root (`REPO_ROOT`).
2. If `doctor.sh` exits with a non-zero exit code:
   - Relay the full remediation output verbatim to the user.
   - **STOP immediately**. Do not proceed to Step 2 or any subsequent step.
3. If `doctor.sh` exits 0:
   - Notify the user that all hard requirements pass (git, gh auth, jq, GitHub remote).
   - Proceed to Step 2.

### Step 2: Seed `.implement-issue/LEARNINGS.md`

*Source of truth: ONBOARDING.md §2*

1. Check if `.implement-issue/LEARNINGS.md` already exists in `REPO_ROOT`.
2. **If absent**:
   - Inspect the target repository to discover build, test, and lint commands. Look at files such as `package.json`, `Makefile`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `CMakeLists.txt`, `.github/workflows/`, etc.
   - Formulate proposed content for the **Build & test** section of `.implement-issue/LEARNINGS.md` based on discovered commands.
   - Present the proposed commands and ask the user via your platform's question/checkpoint mechanism for confirmation or edits.
   - Copy `$SKILL_DIR/templates/LEARNINGS.md` to `.implement-issue/LEARNINGS.md` and insert the agreed **Build & test** section.
   - Stage the file: `git add .implement-issue/LEARNINGS.md` (do NOT commit).
3. **If already present**:
   - Do not overwrite the file.
   - Inform the user that `.implement-issue/LEARNINGS.md` already exists.
   - Offer via your platform's question/checkpoint mechanism to review and augment its **Build & test** section with any newly discovered repository commands.

### Step 3: Branch convention

*Source of truth: ONBOARDING.md §3*

1. Inspect `REPO_ROOT` for `CLAUDE.md` or `AGENTS.md`. Check if either file documents a repository branch-naming convention.
2. **If a documented convention is found**:
   - Summarize the detected convention and confirm with the user via your platform's question/checkpoint mechanism that the workflow will follow it.
3. **If no documented convention is found**:
   - Display the default label → prefix mapping:
     - `bug` / `fix` / `defect` → `fix/`
     - `feature` / `enhancement` / `feat` → `feat/`
     - `chore` / `maintenance` / `refactor` → `chore/`
     - `docs` → `docs/`
     - fallback / unlabelled → `feat/`
   - Ask the user via your platform's question/checkpoint mechanism to confirm whether this default fits the repository.
   - If the repository uses a custom convention, suggest documenting it in `CLAUDE.md` or `AGENTS.md`.
   - No mandatory file writes are required for this step.

### Step 4: Permission allowlist

*Source of truth: ONBOARDING.md §4*

1. Explain the security trade-off: syncing the permission allowlist updates `.claude/settings.local.json` to allow prompt-free execution for worktree file edits, git, and gh tool calls, trading manual approval for autonomous operation.
2. Run a dry run first:
   ```bash
   "$SKILL_DIR/scripts/sync-permissions.sh" --dry-run
   ```
3. Show the `--dry-run` output to the user.
4. Ask the user via your platform's question/checkpoint mechanism for confirmation to apply the allowlist.
5. If confirmed, execute:
   ```bash
   "$SKILL_DIR/scripts/sync-permissions.sh"
   ```
6. Note: `sync-permissions.sh` updates the git-ignored `.claude/settings.local.json` file. Do NOT attempt to run `git add` on this file.

### Step 5: CI gate enforcement

*Source of truth: ONBOARDING.md §6*

1. Explain that CI gate enforcement is a repository-admin action affecting all collaborators by turning gate approvals (`gate:analysis-approved`, `gate:plan-approved`) into a required PR status check (`implement-issue-gate`).
2. Ask the user via your platform's question/checkpoint mechanism whether to set up CI gate enforcement.
3. If confirmed:
   - Check if `.github/workflows/implement-issue-gate.yml` exists.
   - If absent: Copy `$SKILL_DIR/templates/implement-issue-gate.yml` to `.github/workflows/implement-issue-gate.yml` and stage it: `git add .github/workflows/implement-issue-gate.yml` (do NOT commit).
   - If present: Inform the user and do not overwrite.
   - Explain the PAT secret setup for private skill repo access (`trendlik/agentic-engineering`):
     - Create a fine-grained PAT with read-only Contents+Metadata on `trendlik/agentic-engineering`.
     - Set the secret: `gh secret set SKILL_REPO_TOKEN --repo <owner>/<target-repo>` (or org secret: `gh secret set SKILL_REPO_TOKEN --org <your-org> --repos "<target-repo-name>"`).
   - Walk the user through branch protection setup (GitHub Settings → Branches → Branch protection rules → Require status checks to pass before merging → search and select `implement-issue-gate`).
   - Confirm with the user before proceeding past any blocking steps.
4. Note: Workflow stage and gate labels (ONBOARDING §5) are initialized automatically on first run via `state.sh init`, so no separate label setup step is required.

### Step 6: Outcome backfill

*Source of truth: ONBOARDING.md §7*

1. Check if the target repository has merged pull request history (e.g., via `gh pr list --state merged --limit 1` or git log history).
2. **If no merged PR history exists**: Skip this step silently.
3. **If merged PR history exists** and `.implement-issue/outcomes.jsonl` is absent or empty:
   - Run a dry run to preview historical outcome extraction:
     ```bash
     "$SKILL_DIR/scripts/backfill-outcomes.sh" run --dry-run
     ```
   - Display the dry-run output to the user.
   - Ask the user via your platform's question/checkpoint mechanism whether to backfill historical outcomes into `.implement-issue/outcomes.jsonl`.
   - If confirmed, execute:
     ```bash
     "$SKILL_DIR/scripts/backfill-outcomes.sh" run
     ```

### Step 7: Finish

*Source of truth: ONBOARDING "After onboarding"*

1. Summarize all steps completed, configured, or skipped during the onboarding session.
2. List all staged files (e.g. `.implement-issue/LEARNINGS.md`, `.github/workflows/implement-issue-gate.yml`).
3. Remind the user to review and commit staged files:
   ```bash
   git commit -m "chore: onboard implement-issue"
   ```
4. Propose running a first issue implementation:
   ```
   /implement-issue <issue-number>
   ```
