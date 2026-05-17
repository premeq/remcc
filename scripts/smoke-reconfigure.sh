#!/usr/bin/env bash
#
# Smoke-test `install.sh reconfigure` end-to-end against a throwaway target.
# Covers task 4.4 of openspec/changes/pr-author-github-app: reconfigure
# migrates a legacy-WORKFLOW_PAT adopter to the App-credentials shape and
# is idempotent on re-run.
#
# The harness:
#   1. Creates a throwaway target repo and seeds prereqs.
#   2. Runs `install.sh init --ref $OLD_REF` (which still uses WORKFLOW_PAT).
#   3. Merges the init PR so `.remcc/version` is on origin/main.
#   4. Runs `install.sh reconfigure --ref $NEW_REF` to install App credentials.
#   5. Asserts:
#      - REMCC_APP_ID, REMCC_APP_PRIVATE_KEY secrets are present.
#      - REMCC_APP_SLUG variable matches.
#      - Legacy WORKFLOW_PAT secret is gone.
#      - Working tree was not touched; no PR was opened by reconfigure.
#   6. Re-runs reconfigure; asserts no GitHub-side state diff.
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... WORKFLOW_PAT=github_pat_... \
#   REMCC_APP_ID=12345 REMCC_APP_PRIVATE_KEY="$(cat key.pem)" \
#   REMCC_APP_SLUG=remcc-yourname \
#     scripts/smoke-reconfigure.sh \
#     [--target OWNER/NAME] [--ref REF] [--old-ref REF] [--workdir DIR] \
#     [--skip-setup] [--cleanup]
#
# Defaults: --target premeq/remcc-smoke-reconfigure --ref main --old-ref v0.2.1
#           --workdir /tmp/remcc-smoke-reconfigure

set -euo pipefail

TARGET="premeq/remcc-smoke-reconfigure"
NEW_REF="main"
OLD_REF="v0.2.1"
WORKDIR="/tmp/remcc-smoke-reconfigure"
SKIP_SETUP=0
CLEANUP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)      TARGET="$2"; shift 2 ;;
    --ref)         NEW_REF="$2"; shift 2 ;;
    --old-ref)     OLD_REF="$2"; shift 2 ;;
    --workdir)     WORKDIR="$2"; shift 2 ;;
    --skip-setup)  SKIP_SETUP=1; shift ;;
    --cleanup)     CLEANUP=1; shift ;;
    -h|--help)
      sed -n '3,29p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${ANTHROPIC_API_KEY:?must be set — init step (at --old-ref) passes it to gh-bootstrap.sh}"
: "${WORKFLOW_PAT:?must be set — legacy init step (at --old-ref) needs the pre-v0.3.0 PAT secret}"
: "${REMCC_APP_ID:?must be set — reconfigure step (at --ref) needs the App credentials}"
: "${REMCC_APP_PRIVATE_KEY:?must be set — reconfigure step (at --ref) needs the App credentials}"
: "${REMCC_APP_SLUG:?must be set — reconfigure step (at --ref) needs the App slug}"
# Package manager under test. Default pnpm keeps existing behavior and existing
# live runs byte-for-byte unchanged; SMOKE_PM=bun exercises the bun path.
# Note: `bun install` on a dependency-free package.json deletes the empty
# lockfile, so the bun fixture pulls one tiny zero-dep package (left-pad) to
# produce a real bun.lock that `bun install --frozen-lockfile` can consume.
# pnpm writes a valid lockfile even with no deps, so its fixture stays dep-free.
SMOKE_PM="${SMOKE_PM:-pnpm}"
case "$SMOKE_PM" in
  pnpm) SMOKE_PM_SPEC="pnpm@9.12.3"; SMOKE_PM_INSTALL=(pnpm install --silent) ;;
  bun)  SMOKE_PM_SPEC="bun@1.1.34";  SMOKE_PM_INSTALL=(bun add left-pad@1.3.0) ;;
  *)    echo "SMOKE_PM must be 'pnpm' or 'bun' (got: '$SMOKE_PM')" >&2; exit 1 ;;
esac
for t in gh jq "$SMOKE_PM" git curl; do
  command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

OLD_INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${OLD_REF}/install.sh"
NEW_INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${NEW_REF}/install.sh"

FAILED=0

step() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=1; }

snapshot() {
  local out="$1"
  mkdir -p "$out"
  gh api "repos/$TARGET/branches/main/protection" 2>/dev/null > "$out/protection.json" || echo '{}' > "$out/protection.json"
  gh api "repos/$TARGET/rulesets" > "$out/rulesets.json"
  gh secret list --repo "$TARGET" --json name --jq '[.[].name] | sort' > "$out/secrets.json"
  gh api "repos/$TARGET/actions/variables" --jq '[.variables[] | {name, value}] | sort_by(.name)' > "$out/variables.json"
}

normalize() {
  jq -S 'walk(if type=="object" then del(.id,.node_id,.created_at,.updated_at) else . end)' "$1"
}

# ----------------------------------------------------------------------------
# Setup: create target, seed prereqs, init at OLD_REF, merge PR.
# ----------------------------------------------------------------------------
if [ "$SKIP_SETUP" = 0 ]; then
  step "Setup: create $TARGET, seed prereqs in $WORKDIR"
  rm -rf "$WORKDIR"
  gh repo create "$TARGET" --private --add-readme
  gh repo clone "$TARGET" "$WORKDIR"
  cd "$WORKDIR"
  cat > package.json <<JSON
{
  "name": "remcc-smoke-reconfigure",
  "private": true,
  "packageManager": "${SMOKE_PM_SPEC}"
}
JSON
  "${SMOKE_PM_INSTALL[@]}" >/dev/null 2>&1 \
    || { echo "${SMOKE_PM} install (seed lockfile) failed" >&2; exit 1; }
  mkdir -p openspec .claude
  touch openspec/.gitkeep .claude/.gitkeep
  git add .
  git -c user.email=smoke@example.com -c user.name=smoke commit -m "Seed prereqs"
  git push origin main

  step "Setup: install.sh init --ref $OLD_REF (legacy WORKFLOW_PAT state)"
  bash <(curl -fsSL "$OLD_INSTALL_URL") init --ref "$OLD_REF"
  gh pr merge --repo "$TARGET" remcc-init --merge --delete-branch --admin >/dev/null
  git checkout main
  git pull --ff-only >/dev/null
fi

cd "$WORKDIR"

# ----------------------------------------------------------------------------
# Step 1 — confirm pre-state: WORKFLOW_PAT present, no App secrets/var
# ----------------------------------------------------------------------------
step "Step 1: confirm pre-state (legacy WORKFLOW_PAT, no App credentials)"
PRE_SECRETS="$(gh secret list --repo "$TARGET" --json name --jq '.[].name')"
if grep -qx "WORKFLOW_PAT" <<<"$PRE_SECRETS"; then
  pass "pre-state: legacy WORKFLOW_PAT present"
else
  fail "pre-state: WORKFLOW_PAT missing — expected legacy state from OLD_REF init"
fi
if grep -qx "REMCC_APP_ID" <<<"$PRE_SECRETS"; then
  fail "pre-state: REMCC_APP_ID unexpectedly present before reconfigure"
else
  pass "pre-state: no REMCC_APP_ID yet"
fi
if PRE_SLUG="$(gh api "repos/$TARGET/actions/variables/REMCC_APP_SLUG" --jq .value 2>/dev/null)" && [ -n "$PRE_SLUG" ]; then
  fail "pre-state: REMCC_APP_SLUG unexpectedly = $PRE_SLUG"
else
  pass "pre-state: no REMCC_APP_SLUG variable yet"
fi

# ----------------------------------------------------------------------------
# Step 2 — reconfigure refuses an un-adopted target
# (Negative-mode check on a sibling temp clone with no .remcc/version on main.)
# ----------------------------------------------------------------------------
step "Step 2: reconfigure refuses targets without .remcc/version on main"
SIBLING_DIR="$(mktemp -d)"
SIBLING_TARGET="${TARGET}-unadopted-$$"
gh repo create "$SIBLING_TARGET" --private --add-readme >/dev/null
gh repo clone "$SIBLING_TARGET" "$SIBLING_DIR" >/dev/null
(
  cd "$SIBLING_DIR"
  RECONF_ERR="$(mktemp)"
  if bash <(curl -fsSL "$NEW_INSTALL_URL") reconfigure --ref "$NEW_REF" 2>"$RECONF_ERR"; then
    fail "reconfigure exited 0 on un-adopted target (expected non-zero)"
  else
    pass "reconfigure exited non-zero on un-adopted target"
  fi
  if grep -q '.remcc/version' "$RECONF_ERR"; then
    pass "error names .remcc/version"
  else
    fail "error did not mention .remcc/version"
  fi
  if grep -qi 'install.sh init' "$RECONF_ERR"; then
    pass "error points at install.sh init"
  else
    fail "error did not point at install.sh init"
  fi
  rm -f "$RECONF_ERR"
)
gh repo delete "$SIBLING_TARGET" --yes >/dev/null
rm -rf "$SIBLING_DIR"
cd "$WORKDIR"

# ----------------------------------------------------------------------------
# Step 3 — install.sh reconfigure --ref NEW_REF
# ----------------------------------------------------------------------------
step "Step 3: install.sh reconfigure --ref $NEW_REF"
git checkout main >/dev/null 2>&1
bash <(curl -fsSL "$NEW_INSTALL_URL") reconfigure --ref "$NEW_REF"
pass "reconfigure exited 0"

POST_SECRETS="$(gh secret list --repo "$TARGET" --json name --jq '.[].name')"
for s in REMCC_APP_ID REMCC_APP_PRIVATE_KEY; do
  if grep -qx "$s" <<<"$POST_SECRETS"; then
    pass "post-reconfigure: secret $s present"
  else
    fail "post-reconfigure: secret $s missing"
  fi
done
if grep -qx "WORKFLOW_PAT" <<<"$POST_SECRETS"; then
  fail "post-reconfigure: legacy WORKFLOW_PAT still present"
else
  pass "post-reconfigure: legacy WORKFLOW_PAT removed"
fi
POST_SLUG="$(gh api "repos/$TARGET/actions/variables/REMCC_APP_SLUG" --jq .value 2>/dev/null || echo "")"
if [ "$POST_SLUG" = "$REMCC_APP_SLUG" ]; then
  pass "post-reconfigure: REMCC_APP_SLUG = $POST_SLUG"
else
  fail "post-reconfigure: REMCC_APP_SLUG = '$POST_SLUG' (expected '$REMCC_APP_SLUG')"
fi

# Reconfigure must not touch the working tree, branches, or open a PR.
if [ -z "$(git status --porcelain)" ]; then
  pass "reconfigure left working tree clean"
else
  fail "reconfigure unexpectedly left working-tree changes"
fi
RECONF_PR="$(gh pr list --repo "$TARGET" --state open --json headRefName --jq '[.[] | select(.headRefName == "remcc-init" or .headRefName == "remcc-upgrade")] | length')"
[ "$RECONF_PR" = "0" ] \
  && pass "reconfigure opened no remcc-init/remcc-upgrade PR" \
  || fail "reconfigure unexpectedly opened a remcc-init/remcc-upgrade PR"

# ----------------------------------------------------------------------------
# Step 4 — re-run reconfigure; assert no GitHub-side state diff (idempotent)
# ----------------------------------------------------------------------------
step "Step 4: re-run reconfigure — idempotent"
S_BEFORE_RC="$(mktemp -d)"; snapshot "$S_BEFORE_RC"
bash <(curl -fsSL "$NEW_INSTALL_URL") reconfigure --ref "$NEW_REF"
pass "second reconfigure exited 0"
S_AFTER_RC="$(mktemp -d)"; snapshot "$S_AFTER_RC"

for n in protection rulesets secrets variables; do
  if diff -q <(normalize "$S_BEFORE_RC/$n.json") <(normalize "$S_AFTER_RC/$n.json") >/dev/null; then
    pass "reconfigure idempotent: $n"
  else
    fail "drift detected on reconfigure re-run: $n"
    diff <(normalize "$S_BEFORE_RC/$n.json") <(normalize "$S_AFTER_RC/$n.json") | head -20 >&2
  fi
done

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
if [ "$CLEANUP" = 1 ]; then
  step "Cleanup"
  gh repo delete "$TARGET" --yes
  rm -rf "$WORKDIR" "$S_BEFORE_RC" "$S_AFTER_RC"
  pass "deleted $TARGET and $WORKDIR"
else
  printf '\nArtifacts left in place:\n  repo:    %s\n  workdir: %s\n  snaps:   %s, %s\nRe-run with --cleanup to delete.\n' \
    "$TARGET" "$WORKDIR" "$S_BEFORE_RC" "$S_AFTER_RC"
fi

echo
if [ "$FAILED" = 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
