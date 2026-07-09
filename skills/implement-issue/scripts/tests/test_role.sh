#!/usr/bin/env bash
# Tests for role.sh. Needs a real git repo (for `git rev-parse
# --show-toplevel`) plus fake-gh for the resolved user identity.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

ROLE="$SCRIPTS_DIR/role.sh"

echo "role.sh"

# required: fixed stage -> role mapping
assert_eq "$("$ROLE" required clarify)" "analyst" "clarify is owned by analyst"
assert_eq "$("$ROLE" required plan)" "architect" "plan is owned by architect"
assert_eq "$("$ROLE" required implement)" "developer" "implement is owned by developer"
assert_eq "$("$ROLE" required test)" "qa" "test is owned by qa"
assert_eq "$("$ROLE" required done)" "" "done has no owning role"
assert_failure "required rejects an unknown stage" "$ROLE" required bogus

REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
git init --quiet "$REPO"

# No ROLES.yml at all -> fails open everywhere.
assert_eq "$(cd "$REPO" && "$ROLE" whoami)" "no-roles-file" "whoami reports no-roles-file when ROLES.yml is absent"
assert_success "check fails open (no ROLES.yml)" bash -c "cd '$REPO' && '$ROLE' check plan"

# ROLES.yml present, current user not listed.
cat > "$REPO/ROLES.yml" <<'EOF'
# example roles
alice: analyst
bob: architect
EOF
FAKE_GH_USER=nobody
export FAKE_GH_USER
assert_eq "$(cd "$REPO" && "$ROLE" whoami)" "unassigned" "whoami reports unassigned for an unlisted user"
assert_success "check fails open (user not in ROLES.yml)" bash -c "cd '$REPO' && '$ROLE' check plan"

# Matching role.
FAKE_GH_USER=bob
assert_eq "$(cd "$REPO" && "$ROLE" whoami)" "architect" "whoami resolves a listed user's role"
assert_success "check passes when role matches the stage" bash -c "cd '$REPO' && '$ROLE' check plan"

# Mismatched role.
assert_failure "check fails (exit 1) on a real role mismatch" bash -c "cd '$REPO' && '$ROLE' check clarify"

# A user holding multiple comma-separated roles matches any of them.
cat >> "$REPO/ROLES.yml" <<'EOF'
erin: analyst,architect,developer,qa
EOF
FAKE_GH_USER=erin
assert_eq "$(cd "$REPO" && "$ROLE" whoami)" "analyst,architect,developer,qa" "whoami returns the full comma-separated role list"
assert_success "check passes for one of several comma-separated roles (clarify -> analyst)" bash -c "cd '$REPO' && '$ROLE' check clarify"
assert_success "check passes for a different one of the same roles (plan -> architect)" bash -c "cd '$REPO' && '$ROLE' check plan"

unset FAKE_GH_USER

echo "role.sh: $ASSERT_PASS passed, $ASSERT_FAIL failed"
[[ $ASSERT_FAIL -eq 0 ]]
