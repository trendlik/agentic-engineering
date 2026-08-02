#!/usr/bin/env bash
# Freezes a skill's canonical, committed state on GitHub (the origin remote's
# default branch) into an immutable versioned snapshot in the RELEASE STORE,
# so consumers (global or per-project symlinks) can pin a specific version
# instead of running a mutable checkout.
#
# This deliberately does NOT release from a local working tree or local HEAD:
# the repo is public, and this script's own bootstrap is "clone the repo,
# then run ./release.sh from the clone" -- so the only trustworthy source for
# a release is what's actually on origin, not whatever happens to be checked
# out (or uncommitted) in the clone that happens to be running this script.
#
# Model (see README.md for the full picture):
#   SOURCE     origin's default branch, skills/<name>/         (canonical)
#   RELEASE    $RELEASE_STORE/<name>/<version>/                (immutable snapshot)
#   CONSUMERS  symlinks into the release store                 (never into SOURCE)
#
# This script only builds/freezes the snapshot. It deliberately does NOT
# create, move, or re-point any symlink (global or per-project) — that is a
# separate, explicit action (see README.md's "Pin a version" / "Migrate a
# version" sections).
#
# Version source of truth: the `version:` field in the skill's SKILL.md
# frontmatter AS COMMITTED ON ORIGIN'S DEFAULT BRANCH (not the local working
# tree). The release tag and store directory are derived from it, so they can
# never drift from what's actually on GitHub.
#
# Steps:
#   1. `git fetch $ORIGIN --tags` in REPO_ROOT (a clone of the repo).
#   2. Determine $ORIGIN's default branch (or use DEFAULT_BRANCH override);
#      REF = "$ORIGIN/<default-branch>".
#   3. Read `version:` from `skills/<name>/SKILL.md` AT REF (via `git show`,
#      never from the working tree) -- error if missing/malformed, before any
#      mutation.
#   4. Compute TAG=<name>/v<version> and DEST=<release-store>/<name>/<version>.
#      Refuse if DEST already exists (release store is immutable).
#   5. Create the annotated tag TAG at REF's commit (reuse it if it already
#      exists and points at that same commit; error if it exists pointing
#      elsewhere -- never move an existing tag). Push TAG to $ORIGIN.
#   6. `git archive` the skill subtree at TAG into DEST (self-contained: only
#      what's actually committed on origin, never local/uncommitted state).
#   7. `chmod -R a-w` DEST so the snapshot can't be edited after the fact.
#
# Usage: release.sh [--dry-run]
#
# Env overrides (also what the test suite uses to run this without touching
# the real repo, the real release store, or real GitHub):
#   SKILL_NAME      skill to release (default: implement-issue)
#   REPO_ROOT       a clone containing skills/<name>/ (default: this script's
#                   own git toplevel)
#   RELEASE_STORE   release store root (default: $HOME/.agents/releases)
#   ORIGIN          remote to fetch/release from and push the tag to
#                   (default: origin)
#   DEFAULT_BRANCH  branch of $ORIGIN to release from (default: auto-detected
#                   via `git ls-remote --symref $ORIGIN HEAD`)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_color() { local code=$1; shift; printf '\033[%sm%s\033[0m\n' "$code" "$*"; }
info()  { _color '0;36' "$*" >&2; }
ok()    { _color '0;32' "$*" >&2; }
warn()  { _color '0;33' "$*" >&2; }
err()   { _color '0;31' "$*" >&2; }
die()   { err "$*"; exit 1; }

dry_run=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    *) die "usage: release.sh [--dry-run]" ;;
  esac
done

: "${SKILL_NAME:=implement-issue}"
[[ "$SKILL_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid SKILL_NAME: $SKILL_NAME"

: "${ORIGIN:=origin}"
[[ "$ORIGIN" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid ORIGIN: $ORIGIN"

: "${REPO_ROOT:=$(cd "$DIR" && git rev-parse --show-toplevel 2>/dev/null || true)}"
[[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]] || die "could not resolve REPO_ROOT (not a git repo, and REPO_ROOT not set)"
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "REPO_ROOT is not a git repository: $REPO_ROOT"
git -C "$REPO_ROOT" remote get-url "$ORIGIN" >/dev/null 2>&1 || die "remote '$ORIGIN' not found in $REPO_ROOT"

: "${RELEASE_STORE:=$HOME/.agents/releases}"

# --- 1. Fetch origin (branches + tags), so REF and any existing release tag
#        both reflect what's actually on GitHub right now. ---
git -C "$REPO_ROOT" fetch "$ORIGIN" --tags --quiet \
  || die "git fetch $ORIGIN failed"

# --- 2. Determine origin's default branch. ---
: "${DEFAULT_BRANCH:=}"
if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH=$(git -C "$REPO_ROOT" ls-remote --symref "$ORIGIN" HEAD 2>/dev/null \
    | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }')
fi
[[ -n "$DEFAULT_BRANCH" ]] \
  || die "could not determine the default branch of $ORIGIN (set DEFAULT_BRANCH to override)"

REF="$ORIGIN/$DEFAULT_BRANCH"
ref_sha=$(git -C "$REPO_ROOT" rev-parse -q --verify "$REF") \
  || die "could not resolve $REF (fetch failed, or $DEFAULT_BRANCH doesn't exist on $ORIGIN)"

SKILL_PATH="skills/$SKILL_NAME/SKILL.md"

# --- 3. Read version from REF's committed SKILL.md, never the working tree. ---
skill_md=$(git -C "$REPO_ROOT" show "$REF:$SKILL_PATH" 2>/dev/null) \
  || die "could not read $SKILL_PATH at $REF (does the skill exist on $DEFAULT_BRANCH?)"

# Extract the version from the FIRST YAML frontmatter block only (between the
# first two '---' lines), so a stray "version:" mention in the skill's prose
# body can never be picked up by mistake.
frontmatter=$(awk '/^---[[:space:]]*$/{n++; if (n==2) exit; next} n==1' <<<"$skill_md")
version_line=$(grep -E '^version:[[:space:]]*' <<<"$frontmatter" | head -1 || true)
version=$(sed -E 's/^version:[[:space:]]*//' <<<"$version_line" \
  | sed -E "s/^['\"]//; s/['\"][[:space:]]*\$//" \
  | sed -E 's/[[:space:]]+$//')

[[ -n "$version" ]] || die "no 'version:' field found in $SKILL_PATH at $REF"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "malformed version in $SKILL_PATH at $REF: '$version' (expected semver X.Y.Z)"

# --- 4. Compute TAG/DEST; refuse if DEST already exists (immutability). This
#        check runs regardless of --dry-run since it's a validation, not a
#        mutation. ---
TAG="$SKILL_NAME/v$version"
DEST="$RELEASE_STORE/$SKILL_NAME/$version"

[[ -e "$DEST" ]] && die "release already exists (immutable, refusing to overwrite): $DEST"

# --- 5a. Check for a pre-existing tag: reuse if it matches REF's commit,
#         error if it points elsewhere (never move an existing tag). This,
#         too, is a validation and runs in --dry-run. ---
tag_exists=0
if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  tag_exists=1
  tag_commit=$(git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG^{commit}") \
    || die "tag $TAG exists but could not be resolved to a commit"
  if [[ "$tag_commit" != "$ref_sha" ]]; then
    die "tag $TAG already exists but points at $tag_commit, not $REF's commit ($ref_sha) -- refusing to move it"
  fi
fi

if [[ $dry_run -eq 1 ]]; then
  info "[dry-run] skill:          $SKILL_NAME"
  info "[dry-run] origin:         $ORIGIN"
  info "[dry-run] default branch: $DEFAULT_BRANCH ($REF @ $ref_sha)"
  info "[dry-run] version:        $version"
  if [[ $tag_exists -eq 1 ]]; then
    info "[dry-run] tag:            $TAG (already exists at $REF's commit -- would reuse)"
  else
    info "[dry-run] tag:            $TAG (would create at $REF's commit)"
  fi
  info "[dry-run] would push $TAG to $ORIGIN"
  info "[dry-run] would archive skills/$SKILL_NAME @ $TAG into: $DEST"
  info "[dry-run] would chmod -R a-w: $DEST"
  exit 0
fi

# --- 5b. Create (or reuse) the tag, then push it. ---
if [[ $tag_exists -eq 1 ]]; then
  info "tag $TAG already exists at $REF's commit -- reusing"
else
  git -C "$REPO_ROOT" tag -a "$TAG" "$ref_sha" -m "Release $SKILL_NAME v$version" \
    || die "failed to create tag $TAG"
  ok "created tag $TAG at $ref_sha ($REF)"
fi

git -C "$REPO_ROOT" push "$ORIGIN" "$TAG" \
  || die "failed to push tag $TAG to $ORIGIN"
ok "pushed tag $TAG to $ORIGIN"

# --- 6. Archive the skill subtree at TAG into DEST. ---
mkdir -p "$DEST" || die "could not create $DEST"

git -C "$REPO_ROOT" archive "$TAG:skills/$SKILL_NAME" | tar -x -C "$DEST" \
  || die "git archive failed for $TAG:skills/$SKILL_NAME"

# --- 7. Freeze it read-only. ---
chmod -R a-w "$DEST" || die "could not chmod -R a-w $DEST"

ok "released $SKILL_NAME v$version -> $DEST (read-only)"
