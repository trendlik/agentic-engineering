# agentic-engineering

Provider-agnostic, version-controlled agent skills and configuration.

## Skills

Custom skills live under [`skills/`](skills/). Skills can be versioned and
released so that projects consume a frozen, pinned snapshot — see
[Versioned releases](#versioned-releases) below for the full model. A skill
that hasn't opted into versioning yet (no `version:` field in its `SKILL.md`)
is simply symlinked straight from `skills/` as before.

### Installed skills

- `implement-issue` — runs an issue from ticket to merged PR: agents do the work,
  humans approve at the key gates. Phases: clarify → plan → implement → test →
  review → PR → CI-fix loop → retrospective.
  The retrospective is what makes this **compound**: every run feeds project-specific
  learnings back into the target repo (`.implement-issue/LEARNINGS.md`), so each phase
  gets sharper with every issue — the skill isn't just a pipeline, it's a loop that
  tunes itself to the repo it runs in.
  Runs in an isolated git worktree by default; pass `--local` to work directly in
  your checkout and review each phase's changes in your editor before they're committed.
  Full setup, start to finish (install the skill, then onboard a project), lives in
  [`ONBOARDING.md`](skills/implement-issue/ONBOARDING.md) — or use the
  `onboard-implement-issue` skill below to drive it interactively.

  The flow is driven by **GitHub Issues** (via the `gh` CLI) — the only supported
  tracker today. It can be adapted to other systems (Jira, Linear, GitLab), but
  that means editing the skill's scripts and phases; it won't work with a non-GitHub
  tracker out of the box.

- `onboard-implement-issue` — the interactive setup companion to `implement-issue`.
  A checkpoint-driven driver that makes a target repository compatible with
  `implement-issue`: it runs the doctor check, seeds `.implement-issue/LEARNINGS.md`,
  sets branch conventions, syncs the permission allowlist, enforces the CI gate, and
  backfills outcomes — using [`ONBOARDING.md`](skills/implement-issue/ONBOARDING.md)
  as the single source of truth. Run `/onboard-implement-issue` once per repository
  from the target repo's root. It stages changes for review but never commits them.

## Versioned releases

A versioned skill is consumed as an immutable, pinned version snapshot, not
a mutable checkout: a project's `.claude/skills/<skill>` symlink stays on a
specific frozen release until something explicitly re-points it, rather than
source, release, and consumption sharing a single collapsed role.

Versioned skills (currently: `implement-issue` and `onboard-implement-issue`) split that single collapsed
role into three:

1. **SOURCE** (mutable, where you develop) —
   `<repo-dir>/skills/<skill>/`. This is the `skills/` directory in this repo. 
   Its `SKILL.md` frontmatter carries the `version:` field, which is the single 
   source of truth — the release tag, the release-store directory, and the 
   `CHANGELOG.md` entry all derive from it, not the other way around.
2. **RELEASE STORE** (immutable version snapshots, outside the repo) —
   `~/.agents/releases/<skill>/<version>/`. A frozen snapshot of the scoped
   git tag `<skill>/v<version>`, produced by [`release.sh`](release.sh) via
   `git archive` (so it only ever contains committed content, never
   uncommitted working-tree state) and then made read-only (`chmod -R a-w`).
3. **CONSUMERS** (symlinks that pin a version — never point at the repo) —
   e.g. `~/.claude/skills/<skill> -> ~/.agents/releases/<skill>/<version>/` for
   Claude Code or `~/.gemini/config/skills/<skill> -> ~/.agents/releases/<skill>/<version>/`
   for Antigravity/Gemini (the global defaults), or `<project>/.claude/skills/<skill> -> ...`
   (a per-project pin). Claude Code resolves a project's own `.claude/skills/`
   before the global `~/.claude/skills/`, so a project pins simply by having
   its own symlink into the release store. Antigravity gives the same
   override semantics via `<project>/.agents/skills/<skill> -> ...` ahead of
   the global `~/.gemini/config/skills/<skill>` — a per-project pin therefore
   writes *both* symlinks (one per adapter) so scripts resolve the pinned
   version regardless of which adapter is driving.

**This repo is not special.** It pins a frozen release like any other
project — there is no dogfooding exception. An earlier version of this repo
had `.claude/skills/implement-issue` symlinked straight at
`../../skills/implement-issue`, the mutable SOURCE, so that working *in this
repo* ran the live in-dev skill. That's gone: with project-before-global
resolution, a project's own `.claude/skills/`/`.agents/skills/` symlink
always wins, so a SOURCE-pointing symlink here would mean a run inside this
repo loads and executes the very files it is currently editing, mid-edit —
exactly the bug this issue fixes for every *other* project, just self-inflicted.
The accepted tradeoff: the dev loop for this repo becomes edit → commit/push →
bump `version:` → `./release.sh` → re-pin (below) — an unreleased version is
never run here before it ships, the same as any consumer.

### Cutting a release

Clone the repo, then run `release.sh` from inside the clone — there's no
curl-one-liner bootstrap; getting the release tool *is* cloning the repo:

```
git clone <this-repo-url>
cd agentic-engineering
./release.sh                                      # release implement-issue (default) & update global defaults
SKILL_NAME=onboard-implement-issue ./release.sh  # release onboard-implement-issue & update global defaults
./release.sh --no-global                          # release snapshot without updating global symlinks
./release.sh --dry-run                             # show what would happen without doing it
```

`release.sh` never releases from a local working tree or local `HEAD`. The
repo is public, so the only trustworthy source for a release is what's
actually committed on GitHub — not whatever happens to be checked out, or
dirty, in the clone that's running the script. Concretely, it:

1. `git fetch`es `origin` (branches + tags) and resolves its default branch,
   giving `REF = origin/<default-branch>`.
2. Reads `version:` from `skills/<skill>/SKILL.md` **as committed at `REF`**
   — via `git show`, never the working tree — and errors on a missing or
   non-semver value before touching anything.
3. Refuses if `~/.agents/releases/<skill>/<version>/` already exists —
   releases are immutable; bump the version instead of re-releasing.
4. Creates the annotated tag `<skill>/v<version>` at `REF`'s commit (reusing
   it if it already exists and points at that same commit; erroring if it
   exists pointing somewhere else — it never moves an existing tag), then
   **pushes the tag to origin**.
5. `git archive`s the skill subtree at that tag into the release store, then
   `chmod -R a-w`s it.
6. Updates `~/.agents/releases/<skill>/latest` to point to `<version>`, and (unless `--no-global` is passed) automatically updates global default symlinks (`~/.claude/skills/<skill>` and `~/.gemini/config/skills/<skill>`) to point directly to `~/.agents/releases/<skill>/<version>`.

It defaults to skill `implement-issue` (or set `SKILL_NAME=onboard-implement-issue`), the clone it's run from as
`REPO_ROOT`, remote `origin` as `ORIGIN`, and `~/.agents/releases` as
`RELEASE_STORE` — all overridable via env vars (plus `DEFAULT_BRANCH`, which
otherwise auto-detects from `ORIGIN`). That's how
[`tests/test_release.sh`](tests/test_release.sh) exercises the full
fetch-and-push path against a throwaway bare repo standing in for GitHub,
without touching the real repo, the real store, or real GitHub.

By default, **`release.sh` automatically updates global default symlinks** (`~/.claude/skills/<skill>` and `~/.gemini/config/skills/<skill>`) to point directly to the newly released version in `~/.agents/releases/<skill>/<version>` (and updates `~/.agents/releases/<skill>/latest` to point to `<version>`). Projects that have set per-project symlinks continue using their explicitly pinned version because per-project symlinks outrank global symlinks. Pass `--no-global` if you want to cut a release snapshot without updating global default symlinks.

Before running it, bump `version:` in `SKILL.md`, add the matching entry to
[`CHANGELOG.md`](CHANGELOG.md) (including a **Migration** note if the release
has breaking changes), and **commit and push both to origin's default
branch** — `release.sh` reads the version and archives the skill from what's
on origin, not your local checkout, so a version bump that hasn't been pushed
yet is invisible to it.

### Pin a project to a version

There's no `pin.sh` yet — pinning is a few manual steps. Write **both**
adapter symlinks (Claude Code's `.claude/skills/` and Antigravity's
`.agents/skills/`) so a project's scripts resolve the pinned version
regardless of which adapter runs it — a project pinned via only one of the
two still runs the other adapter's *global* default, which is exactly the
per-project-pin bug this issue fixes:

```
mkdir -p <project>/.claude/skills <project>/.agents/skills
ln -s ~/.agents/releases/<skill>/<version> <project>/.claude/skills/<skill>
ln -s ~/.agents/releases/<skill>/<version> <project>/.agents/skills/<skill>
mkdir -p <project>/.implement-issue
echo <version> > <project>/.implement-issue/skill-version
printf '.claude/skills/\n.agents/skills/\n' >> <project>/.gitignore
```

Add `.claude/skills/` and `.agents/skills/` to the *project's own*
`.gitignore` (as above) — each pin is an absolute, machine-specific path
into the release store, so committing it would ship a link that dangles in
every other clone and in CI, the same reasoning as `settings.local.json`.
The two symlinks are the sole resolution input (per-machine, uncommitted);
the committed `.implement-issue/skill-version` is just a greppable record of
which version that is, for humans and scripts that want to check it without
`readlink` — no resolution path reads it.

### Migrate a project to a new version

Also manual for now (no `migrate.sh`):

1. Read [`CHANGELOG.md`](CHANGELOG.md) for every version between the
   project's current pin and the target version, and follow any **Migration**
   notes in order.
2. Re-point **both** of the project's symlinks:
   ```
   ln -sfn ~/.agents/releases/<skill>/<new-version> <project>/.claude/skills/<skill>
   ln -sfn ~/.agents/releases/<skill>/<new-version> <project>/.agents/skills/<skill>
   ```
3. Update `<project>/.implement-issue/skill-version` to match.

## Requirements

The skills rely on a Unix-style shell and toolchain (`bash`, `git`, `gh`, `jq`), so
they run natively on **macOS and Linux**. The `*.sh` scripts won't execute under
native Windows `cmd`/PowerShell; on **Windows** you'd need **WSL** or **Git Bash**
(and symlinking skills into place also expects a POSIX environment). Note this
hasn't been tested on Windows — WSL/Git Bash is the expected path, not a verified one.
