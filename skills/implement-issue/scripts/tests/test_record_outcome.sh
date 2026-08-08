#!/usr/bin/env bash
# Tests for record-outcome.sh (pure/offline: no gh, no network). Each test
# uses its own temp ledger via $OUTCOMES_FILE so tests don't interfere.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"
# shellcheck source=../lib/common.sh
source "$SCRIPTS_DIR/lib/common.sh"

RECORD="$SCRIPTS_DIR/record-outcome.sh"

echo "record-outcome.sh"

# --- append + second issue appends a second line ------------------------
ledger=$(mktemp)
rm -f "$ledger"  # record-outcome.sh must create it itself
OUTCOMES_FILE="$ledger" "$RECORD" 1 title=First outcome=merged >/dev/null 2>&1
assert_success "ledger file created after first record" bash -c "[[ -f '$ledger' ]]"
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "1" "first record is the only line"

OUTCOMES_FILE="$ledger" "$RECORD" 2 title=Second outcome=closed >/dev/null 2>&1
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "2" "second (different) issue appends a second line"
rm -f "$ledger"

# --- upsert: same issue replaces its line in place -----------------------
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 5 title=Original outcome=merged pr=10 >/dev/null 2>&1
OUTCOMES_FILE="$ledger" "$RECORD" 6 title=Other outcome=merged pr=11 >/dev/null 2>&1
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "2" "two distinct issues -> two lines before upsert"

OUTCOMES_FILE="$ledger" "$RECORD" 5 title=Updated outcome=closed pr=99 >/dev/null 2>&1
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "2" "re-recording issue 5 does not add a line (upsert, not append)"

line5=$(grep '"issue":5' "$ledger")
assert_eq "$(jq -r '.title' <<<"$line5")" "Updated" "upserted record reflects new title"
assert_eq "$(jq -r '.outcome' <<<"$line5")" "closed" "upserted record reflects new outcome"
assert_eq "$(jq -r '.pr' <<<"$line5")" "99" "upserted record reflects new pr"
rm -f "$ledger"

# --- unsupplied known fields serialize as JSON null ----------------------
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 7 title=Bare >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -r '.clarify_rounds' <<<"$rec")" "null" "unsupplied clarify_rounds is JSON null"
assert_eq "$(jq -r '.plan_revisions' <<<"$rec")" "null" "unsupplied plan_revisions is JSON null"
assert_eq "$(jq -r '.review_loops' <<<"$rec")" "null" "unsupplied review_loops is JSON null"
assert_eq "$(jq -r '.outcome' <<<"$rec")" "null" "unsupplied outcome is JSON null"
assert_eq "$(jq -r '.labels' <<<"$rec")" "null" "unsupplied labels is JSON null"
rm -f "$ledger"

# --- numeric fields are JSON numbers, not strings; labels is an array ----
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 8 diff_loc=123 files_changed=4 commits=2 labels=a,b,c >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -r '.diff_loc | type' <<<"$rec")" "number" "diff_loc is a JSON number"
assert_eq "$(jq -r '.files_changed | type' <<<"$rec")" "number" "files_changed is a JSON number"
assert_eq "$(jq -r '.commits | type' <<<"$rec")" "number" "commits is a JSON number"
assert_eq "$(jq -r '.labels | type' <<<"$rec")" "array" "labels is a JSON array"
rm -f "$ledger"

# --- labels=a,b,c -> 3-element array; empty labels -> empty array --------
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 9 labels=a,b,c >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -c '.labels' <<<"$rec")" '["a","b","c"]' "labels=a,b,c becomes a 3-element JSON array"

OUTCOMES_FILE="$ledger" "$RECORD" 10 labels= >/dev/null 2>&1
rec10=$(grep '"issue":10' "$ledger")
assert_eq "$(jq -c '.labels' <<<"$rec10")" '[]' "empty labels string becomes an empty JSON array"
rm -f "$ledger"

# --- validation / error paths --------------------------------------------
ledger=$(mktemp)
assert_failure "unknown key is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 bogus_field=1
assert_failure "invalid outcome value is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 outcome=merged_wrongly
assert_failure "non-integer issue is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" abc title=x
assert_failure "negative issue is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" -1 title=x
assert_failure "non-integer numeric field is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 diff_loc=1.5
assert_failure "negative count field (diff_loc) is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 diff_loc=-5
assert_failure "negative count field (files_changed) is rejected" env OUTCOMES_FILE="$ledger" "$RECORD" 20 files_changed=-1
assert_success "wall_clock_hours accepts a float" env OUTCOMES_FILE="$ledger" "$RECORD" 20 wall_clock_hours=1.5
rm -f "$ledger"

# --- auto-fill: recorded_at / skill_sha / skill_version -------------------
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 30 title=AutoFill >/dev/null 2>&1
rec=$(cat "$ledger")
recorded_at=$(jq -r '.recorded_at' <<<"$rec")
skill_sha=$(jq -r '.skill_sha' <<<"$rec")
skill_version=$(jq -r '.skill_version' <<<"$rec")
assert_failure "recorded_at is auto-filled (non-null) when omitted" bash -c "[[ '$recorded_at' == 'null' || -z '$recorded_at' ]]"
assert_failure "skill_sha is auto-filled (non-null) when omitted" bash -c "[[ '$skill_sha' == 'null' || -z '$skill_sha' ]]"
assert_failure "skill_version is auto-filled (non-null) when omitted" bash -c "[[ '$skill_version' == 'null' || -z '$skill_version' ]]"

OUTCOMES_FILE="$ledger" "$RECORD" 31 recorded_at=2020-01-01 skill_sha=deadbee skill_version=1.2.3 >/dev/null 2>&1
rec31=$(grep '"issue":31' "$ledger")
assert_eq "$(jq -r '.recorded_at' <<<"$rec31")" "2020-01-01" "explicit recorded_at is honored"
assert_eq "$(jq -r '.skill_sha' <<<"$rec31")" "deadbee" "explicit skill_sha is honored"
assert_eq "$(jq -r '.skill_version' <<<"$rec31")" "1.2.3" "explicit skill_version is honored"
rm -f "$ledger"

# --- skill_sha_default / skill_version_default resolution order -----------
tmp_sha_work=$(mktemp -d)

# 1. git short sha available in git repo
git_repo="$tmp_sha_work/git_repo"
mkdir -p "$git_repo"
git -C "$git_repo" init >/dev/null 2>&1
git -C "$git_repo" config user.email "test@example.com"
git -C "$git_repo" config user.name "Test User"
touch "$git_repo/file.txt"
git -C "$git_repo" add file.txt
git -C "$git_repo" commit -m "initial commit" >/dev/null 2>&1
expected_git_sha=$(git -C "$git_repo" rev-parse --short HEAD)

assert_eq "$(skill_sha_default "$git_repo")" "$expected_git_sha" \
  "skill_sha_default returns git short SHA when git repo exists"

# 2. skill_version_default extracts version from SKILL.md when not a git repo; skill_sha_default returns unknown
release_store="$tmp_sha_work/release_store"
mkdir -p "$release_store"
cat <<'EOF' > "$release_store/SKILL.md"
---
name: implement-issue
description: test skill
version: 1.0.0
---
EOF

assert_eq "$(skill_version_default "$release_store")" "1.0.0" \
  "skill_version_default extracts version from SKILL.md"
assert_eq "$(skill_sha_default "$release_store")" "unknown" \
  "skill_sha_default returns 'unknown' when not a git repo"

cat <<'EOF' > "$release_store/SKILL.md"
---
name: test-quoted
version: "2.3.4-beta"
---
EOF

assert_eq "$(skill_version_default "$release_store")" "2.3.4-beta" \
  "skill_version_default handles quoted version strings in SKILL.md"

# 3. both git sha and SKILL.md version fail / missing -> returns unknown
empty_store="$tmp_sha_work/empty_store"
mkdir -p "$empty_store"

assert_eq "$(skill_sha_default "$empty_store")" "unknown" \
  "skill_sha_default returns 'unknown' when not a git repo and SKILL.md missing"
assert_eq "$(skill_version_default "$empty_store")" "unknown" \
  "skill_version_default returns 'unknown' when SKILL.md is missing"

cat <<'EOF' > "$empty_store/SKILL.md"
---
name: implement-issue
description: no version field
---
EOF

assert_eq "$(skill_sha_default "$empty_store")" "unknown" \
  "skill_sha_default returns 'unknown' when SKILL.md exists but has no version"
assert_eq "$(skill_version_default "$empty_store")" "unknown" \
  "skill_version_default returns 'unknown' when SKILL.md exists but has no version"

rm -rf "$tmp_sha_work"

# --- 3 provenance scenarios (skill_version / skill_sha) ------------------
tmp_prov_work=$(mktemp -d)

setup_mock_skill_scripts() {
  local target_dir=$1
  mkdir -p "$target_dir/scripts/lib"
  cp "$SCRIPTS_DIR/record-outcome.sh" "$target_dir/scripts/"
  cp "$SCRIPTS_DIR/lib/common.sh" "$target_dir/scripts/lib/"
}

# Scenario (a): Non-git release directory
rel_dir="$tmp_prov_work/release_dir"
mkdir -p "$rel_dir"
cat <<'EOF' > "$rel_dir/SKILL.md"
---
name: implement-issue
version: 1.0.0
---
EOF
setup_mock_skill_scripts "$rel_dir"

assert_eq "$(skill_version_default "$rel_dir")" "1.0.0" \
  "provenance (a): non-git release dir skill_version_default returns parsed version"
assert_eq "$(skill_sha_default "$rel_dir")" "unknown" \
  "provenance (a): non-git release dir skill_sha_default returns 'unknown'"

rel_ledger="$tmp_prov_work/rel_ledger.jsonl"
OUTCOMES_FILE="$rel_ledger" "$rel_dir/scripts/record-outcome.sh" 10 title="Release run" >/dev/null 2>&1
rel_rec=$(cat "$rel_ledger")
assert_eq "$(jq -r '.skill_version' <<<"$rel_rec")" "1.0.0" \
  "provenance (a): non-git release dir records parsed skill_version"
assert_eq "$(jq -r '.skill_sha' <<<"$rel_rec")" "unknown" \
  "provenance (a): non-git release dir records skill_sha='unknown'"

# Scenario (b): Source checkout directory
src_dir="$tmp_prov_work/source_checkout"
mkdir -p "$src_dir"
git -C "$src_dir" init >/dev/null 2>&1
git -C "$src_dir" config user.email "test@example.com"
git -C "$src_dir" config user.name "Test User"
touch "$src_dir/file.txt"
git -C "$src_dir" add file.txt
git -C "$src_dir" commit -m "initial commit" >/dev/null 2>&1
expected_src_sha=$(git -C "$src_dir" rev-parse --short HEAD)
cat <<'EOF' > "$src_dir/SKILL.md"
---
name: implement-issue
version: 2.1.0
---
EOF
setup_mock_skill_scripts "$src_dir"

assert_eq "$(skill_version_default "$src_dir")" "2.1.0" \
  "provenance (b): source checkout skill_version_default returns parsed version"
assert_eq "$(skill_sha_default "$src_dir")" "$expected_src_sha" \
  "provenance (b): source checkout skill_sha_default returns commit SHA"

src_ledger="$tmp_prov_work/src_ledger.jsonl"
OUTCOMES_FILE="$src_ledger" "$src_dir/scripts/record-outcome.sh" 11 title="Source run" >/dev/null 2>&1
src_rec=$(cat "$src_ledger")
assert_eq "$(jq -r '.skill_version' <<<"$src_rec")" "2.1.0" \
  "provenance (b): source checkout records parsed skill_version"
assert_eq "$(jq -r '.skill_sha' <<<"$src_rec")" "$expected_src_sha" \
  "provenance (b): source checkout records valid commit skill_sha"

# Scenario (c): Skill directory nested inside an unrelated git repository
unrelated_repo="$tmp_prov_work/unrelated_repo"
mkdir -p "$unrelated_repo"
git -C "$unrelated_repo" init >/dev/null 2>&1
git -C "$unrelated_repo" config user.email "test@example.com"
git -C "$unrelated_repo" config user.name "Test User"
touch "$unrelated_repo/app.js"
git -C "$unrelated_repo" add app.js
git -C "$unrelated_repo" commit -m "app init" >/dev/null 2>&1
git -C "$unrelated_repo" config remote.origin.url "git@github.com:unrelated-org/unrelated-repo.git"

nested_skill_dir="$unrelated_repo/.claude/skills/implement-issue"
mkdir -p "$nested_skill_dir"
cat <<'EOF' > "$nested_skill_dir/SKILL.md"
---
name: implement-issue
version: 3.0.0
---
EOF
setup_mock_skill_scripts "$nested_skill_dir"

assert_eq "$(skill_version_default "$nested_skill_dir")" "3.0.0" \
  "provenance (c): nested in unrelated git repo skill_version_default returns parsed version"
assert_eq "$(skill_sha_default "$nested_skill_dir")" "unknown" \
  "provenance (c): nested in unrelated git repo skill_sha_default degrades to 'unknown'"

nested_ledger="$tmp_prov_work/nested_ledger.jsonl"
OUTCOMES_FILE="$nested_ledger" "$nested_skill_dir/scripts/record-outcome.sh" 12 title="Nested run" >/dev/null 2>&1
nested_rec=$(cat "$nested_ledger")
assert_eq "$(jq -r '.skill_version' <<<"$nested_rec")" "3.0.0" \
  "provenance (c): nested in unrelated git repo records parsed skill_version"
assert_eq "$(jq -r '.skill_sha' <<<"$nested_rec")" "unknown" \
  "provenance (c): nested in unrelated git repo records skill_sha='unknown'"

rm -rf "$tmp_prov_work"

# --- platform + per-phase *_model fields: all 7 accepted as JSON strings -
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 40 \
  platform=claude-code coordinator_model=claude-opus-5 implement_model=sonnet \
  test_model=sonnet review_model=opus fix_model=sonnet ci_fix_model=haiku >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -r '.platform' <<<"$rec")" "claude-code" "platform stores the exact value passed"
assert_eq "$(jq -r '.coordinator_model' <<<"$rec")" "claude-opus-5" "coordinator_model stores the exact value passed"
assert_eq "$(jq -r '.implement_model' <<<"$rec")" "sonnet" "implement_model stores the exact value passed"
assert_eq "$(jq -r '.test_model' <<<"$rec")" "sonnet" "test_model stores the exact value passed"
assert_eq "$(jq -r '.review_model' <<<"$rec")" "opus" "review_model stores the exact value passed"
assert_eq "$(jq -r '.fix_model' <<<"$rec")" "sonnet" "fix_model stores the exact value passed"
assert_eq "$(jq -r '.ci_fix_model' <<<"$rec")" "haiku" "ci_fix_model stores the exact value passed"
assert_eq "$(jq -r '.platform | type' <<<"$rec")" "string" "platform serializes as a JSON string, not a number"
assert_eq "$(jq -r '.coordinator_model | type' <<<"$rec")" "string" "coordinator_model serializes as a JSON string"
assert_eq "$(jq -r '.implement_model | type' <<<"$rec")" "string" "implement_model serializes as a JSON string"
assert_eq "$(jq -r '.test_model | type' <<<"$rec")" "string" "test_model serializes as a JSON string"
assert_eq "$(jq -r '.review_model | type' <<<"$rec")" "string" "review_model serializes as a JSON string"
assert_eq "$(jq -r '.fix_model | type' <<<"$rec")" "string" "fix_model serializes as a JSON string"
assert_eq "$(jq -r '.ci_fix_model | type' <<<"$rec")" "string" "ci_fix_model serializes as a JSON string"
rm -f "$ledger"

# --- unsupplied model fields are JSON null, including mixed supplied/omitted
# `jq -r '.platform'` alone can't tell a present-but-null key from an
# altogether ABSENT one — both print the literal string "null" — so each
# field also gets a `has()` presence check; only the pair together proves
# the key survives in the record shape even when its value is unset.
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 41 title=NoModels >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -r '.platform' <<<"$rec")" "null" "unsupplied platform is JSON null"
assert_eq "$(jq -r 'has("platform")' <<<"$rec")" "true" "unsupplied platform key is present (not absent)"
assert_eq "$(jq -r '.coordinator_model' <<<"$rec")" "null" "unsupplied coordinator_model is JSON null"
assert_eq "$(jq -r 'has("coordinator_model")' <<<"$rec")" "true" "unsupplied coordinator_model key is present (not absent)"
assert_eq "$(jq -r '.implement_model' <<<"$rec")" "null" "unsupplied implement_model is JSON null"
assert_eq "$(jq -r 'has("implement_model")' <<<"$rec")" "true" "unsupplied implement_model key is present (not absent)"
assert_eq "$(jq -r '.test_model' <<<"$rec")" "null" "unsupplied test_model is JSON null"
assert_eq "$(jq -r 'has("test_model")' <<<"$rec")" "true" "unsupplied test_model key is present (not absent)"
assert_eq "$(jq -r '.review_model' <<<"$rec")" "null" "unsupplied review_model is JSON null"
assert_eq "$(jq -r 'has("review_model")' <<<"$rec")" "true" "unsupplied review_model key is present (not absent)"
assert_eq "$(jq -r '.fix_model' <<<"$rec")" "null" "unsupplied fix_model is JSON null"
assert_eq "$(jq -r 'has("fix_model")' <<<"$rec")" "true" "unsupplied fix_model key is present (not absent)"
assert_eq "$(jq -r '.ci_fix_model' <<<"$rec")" "null" "unsupplied ci_fix_model is JSON null"
assert_eq "$(jq -r 'has("ci_fix_model")' <<<"$rec")" "true" "unsupplied ci_fix_model key is present (not absent)"
rm -f "$ledger"

# Mixed case: an LGTM review + green-first-CI run supplies platform and the
# phases that actually ran, but omits fix_model/ci_fix_model because those
# agents were never spawned.
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 42 \
  platform=claude-code coordinator_model=claude-opus-5 implement_model=sonnet \
  test_model=sonnet review_model=opus >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -r '.platform' <<<"$rec")" "claude-code" "mixed case: supplied platform is honored"
assert_eq "$(jq -r '.implement_model' <<<"$rec")" "sonnet" "mixed case: supplied implement_model is honored"
assert_eq "$(jq -r '.review_model' <<<"$rec")" "opus" "mixed case: supplied review_model is honored"
assert_eq "$(jq -r '.fix_model' <<<"$rec")" "null" "mixed case: omitted fix_model (no fix round) is JSON null"
assert_eq "$(jq -r '.ci_fix_model' <<<"$rec")" "null" "mixed case: omitted ci_fix_model (green first CI) is JSON null"
rm -f "$ledger"

# --- platform is genuinely free-form: no enum, unlike `outcome` -----------
# This is the assertion that would fail if someone later bolted an enum
# check onto `platform` the way `outcome` has one.
ledger=$(mktemp)
assert_success "platform accepts an arbitrary unknown value (no enum, unlike outcome)" \
  env OUTCOMES_FILE="$ledger" "$RECORD" 43 platform=some-future-adapter
rec=$(grep '"issue":43' "$ledger")
assert_eq "$(jq -r '.platform' <<<"$rec")" "some-future-adapter" "arbitrary platform value is stored verbatim"
rm -f "$ledger"

# --- platform= (explicit empty string) pins the omit-vs-empty distinction:
# no emptiness check is enforced, so `platform=` stores "" (a caller
# mistake), distinguishable from an omitted argument (which stores null —
# see the "unsupplied model fields" block above). The header comment
# documents omission, not an empty string, as the "phase never ran"
# convention.
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 46 platform= >/dev/null 2>&1
rec=$(cat "$ledger")
assert_eq "$(jq -r '.platform' <<<"$rec")" "" "explicit platform= stores an empty JSON string (no emptiness check enforced)"
assert_eq "$(jq -r '.platform | type' <<<"$rec")" "string" "explicit platform= is a JSON string, distinguishable from an omitted (null) field"
rm -f "$ledger"

# --- *_model fields are not integer-validated: non-numeric values pass ----
ledger=$(mktemp)
assert_success "implement_model accepts a non-numeric value (not integer-validated)" \
  env OUTCOMES_FILE="$ledger" "$RECORD" 44 implement_model=sonnet
rec=$(cat "$ledger")
assert_eq "$(jq -r '.implement_model' <<<"$rec")" "sonnet" "non-numeric implement_model is stored as-is"
assert_eq "$(jq -r '.implement_model | type' <<<"$rec")" "string" "non-numeric implement_model is not coerced to a number"
rm -f "$ledger"

# --- unknown/misspelled model key is rejected by the known-key check ------
ledger=$(mktemp)
assert_failure "misspelled model key (implement_modl) is rejected" \
  env OUTCOMES_FILE="$ledger" "$RECORD" 45 implement_modl=sonnet
rm -f "$ledger"

# --- upsert preserves model fields; re-recording replaces only that line --
ledger=$(mktemp)
OUTCOMES_FILE="$ledger" "$RECORD" 50 title=Keep platform=claude-code implement_model=sonnet >/dev/null 2>&1
line50_before=$(grep '"issue":50' "$ledger")
OUTCOMES_FILE="$ledger" "$RECORD" 51 title=Untouched platform=claude-code implement_model=opus >/dev/null 2>&1
line51_before=$(grep '"issue":51' "$ledger")
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "2" "two distinct issues -> two lines before model-field upsert"

OUTCOMES_FILE="$ledger" "$RECORD" 50 title=Keep platform=antigravity implement_model=haiku coordinator_model=claude-opus-5 >/dev/null 2>&1
assert_eq "$(wc -l <"$ledger" | tr -d ' ')" "2" "re-recording issue 50 with new model values does not add a line"

line50_after=$(grep '"issue":50' "$ledger")
line51_after=$(grep '"issue":51' "$ledger")
assert_eq "$(jq -r '.platform' <<<"$line50_after")" "antigravity" "upserted record reflects new platform"
assert_eq "$(jq -r '.implement_model' <<<"$line50_after")" "haiku" "upserted record reflects new implement_model"
assert_eq "$(jq -r '.coordinator_model' <<<"$line50_after")" "claude-opus-5" "upserted record reflects newly-added coordinator_model"
assert_eq "$line51_after" "$line51_before" "untouched issue 51 line is byte-identical after unrelated upsert (existing lines not migrated)"
assert_ne "$line50_after" "$line50_before" "issue 50's line actually changed after re-recording (sanity check on the upsert itself)"
rm -f "$ledger"

echo "record-outcome.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]

