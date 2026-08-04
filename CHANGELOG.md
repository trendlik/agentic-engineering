# Changelog

All notable changes to the skills in this repo are documented in this file,
grouped by skill and version. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions are
[SemVer](https://semver.org/).

Each skill is versioned independently via the `version:` field in its
`SKILL.md` frontmatter (source of truth) and released via [`release.sh`](release.sh),
which freezes the scoped git tag `<skill>/v<version>` into the release store
at `~/.agents/releases/<skill>/<version>/`. See [`README.md`](README.md) for
the full source -> release store -> consumer model, and how to pin or migrate
a project's consumed version.

A version entry with breaking changes must include a **Migration** note
describing what a project pinned to the previous version needs to do before
moving its symlink forward.

## implement-issue

### [1.2.1]

Requires explicit user approval before writing project learnings to `.implement-issue/LEARNINGS.md` or executing `git commit` in Phase 8 retrospective. Adds a mandatory `STOP and wait for explicit user response` directive and reply classification consistent with Checkpoint discipline. (#47)

### [1.2.0]

Fixes skill provenance (`skill_sha`) degradation to `skill@unknown` when `implement-issue` runs from an immutable release-store installation (which carries no `.git` directory). Centralizes resolution in `scripts/lib/common.sh` using a fallback sequence: git short SHA -> `v<version>` parsed from `SKILL.md` frontmatter -> `unknown`. Updates outcome ledger recording, backfill scripts, documentation, and template provenance stamps (`skill@<sha|vVersion>`).

Not breaking — backward compatible with existing git checkouts and release store installations.

### [1.1.0]

Adds per-project version pinning on Antigravity: `$SKILL_DIR` resolution (the
inline loops in `SKILL.md` and the canonical `scripts/lib/resolve-skill-dir.sh`
that `sync-permissions.sh` now sources) checks a project's own
`.agents/skills/implement-issue` symlink alongside the existing
`.claude/skills/implement-issue`, both ahead of the global
`~/.claude/skills/implement-issue` / `~/.gemini/config/skills/implement-issue`
defaults. Previously the candidate loops probed only the two global paths, so
a project pinned to an older release still ran that release's *scripts* from
whatever the global symlink happened to point at, even though its prose
resolved the pinned version correctly.

Not breaking — a project with no project-level symlink resolves exactly as
before.

**Migration:** projects that already pin a version via
`<project>/.claude/skills/implement-issue` should additionally create the
Antigravity symlink (`<project>/.agents/skills/implement-issue`, pointing at
the same release-store version) and re-run `sync-permissions.sh` so its
allowlist rules pick up the project path. See README.md's "Pin a project to a
version" recipe.

### [1.0.0]

Initial versioned release. No prior version existed — before this, the
skill had no `version:` field, no git tags, and every consumer pointed
straight at the mutable working tree in this repo.

No breaking changes / no migration steps (first version).

## onboard-implement-issue

### [1.1.0]

Same `$SKILL_DIR` resolution fix as `implement-issue` 1.1.0: the inline
candidate loop now checks a project's own `.claude/skills/implement-issue`
and `.agents/skills/implement-issue` symlinks before falling back to the
global `~/.claude/skills/implement-issue` / `~/.gemini/config/skills/implement-issue`
defaults, so onboarding a repo that already pins a version resolves the
pinned skill's own scripts, not whatever the global symlink points at.

Not breaking — a project with no project-level symlink resolves exactly as
before.

**Migration:** already-pinned projects should add the `.agents/skills/`
symlink (Antigravity) alongside their existing `.claude/skills/` one and
re-run `sync-permissions.sh`. See README.md's "Pin a project to a version"
recipe.

### [1.0.0]

Initial versioned release. No prior version existed — before this, the
skill had no `version:` field, no git tags, and every consumer pointed
straight at the mutable working tree in this repo.

No breaking changes / no migration steps (first version).

