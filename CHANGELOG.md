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

### [1.0.0]

Initial versioned release. No prior version existed — before this, the
skill had no `version:` field, no git tags, and every consumer pointed
straight at the mutable working tree in this repo.

No breaking changes / no migration steps (first version).

## onboard-implement-issue

### [1.0.0]

Initial versioned release. No prior version existed — before this, the
skill had no `version:` field, no git tags, and every consumer pointed
straight at the mutable working tree in this repo.

No breaking changes / no migration steps (first version).

