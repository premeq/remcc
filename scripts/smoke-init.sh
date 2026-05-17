#!/usr/bin/env bash
#
# Smoke-test `install.sh init` end-to-end against a throwaway target repo.
# Covers task 7.1 of openspec/changes/gh-remcc-init (plus task 3.4 — the
# second-run idempotency check).
#
# Usage:
#   ANTHROPIC_API_KEY=sk-... \
#   REMCC_APP_ID=12345 REMCC_APP_PRIVATE_KEY="$(cat key.pem)" \
#   REMCC_APP_SLUG=remcc-yourname \
#     scripts/smoke-init.sh \
#     [--target OWNER/NAME] [--ref REF|auto] [--workdir DIR] \
#     [--skip-setup] [--cleanup]
#
# Defaults: --target premeq/remcc-smoke, --ref main, --workdir /tmp/remcc-smoke
#
# --ref auto: resolve the latest release tag on premeq/remcc, fetch install.sh
# from that tag's URL, and omit --ref to install.sh so it resolves the source
# ref via its own `releases/latest` path. This is the third-party-operator
# shape (covers task 8.2 of gh-remcc-init).

set -euo pipefail

TARGET="premeq/remcc-smoke"
REF="main"
WORKDIR="/tmp/remcc-smoke"
SKIP_SETUP=0
CLEANUP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)      TARGET="$2"; shift 2 ;;
    --ref)         REF="$2"; shift 2 ;;
    --workdir)     WORKDIR="$2"; shift 2 ;;
    --skip-setup)  SKIP_SETUP=1; shift ;;
    --cleanup)     CLEANUP=1; shift ;;
    -h|--help)
      sed -n '3,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${ANTHROPIC_API_KEY:?must be set — install.sh passes it through to gh-bootstrap.sh}"
: "${REMCC_APP_ID:?must be set — numeric App ID for the remcc GitHub App}"
: "${REMCC_APP_PRIVATE_KEY:?must be set — PEM-encoded private key for the remcc GitHub App}"
: "${REMCC_APP_SLUG:?must be set — slug from the App URL (github.com/apps/<slug>)}"
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

if [ "$REF" = "auto" ]; then
  RESOLVED_REF="$(gh api repos/premeq/remcc/releases/latest --jq .tag_name 2>/dev/null || true)"
  [ -n "$RESOLVED_REF" ] || { echo "no release tag found on premeq/remcc" >&2; exit 1; }
  INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${RESOLVED_REF}/install.sh"
  INIT_REF_ARGS=()
  EXPECTED_SRC_REF="$RESOLVED_REF"
  echo "ref=auto resolved to ${RESOLVED_REF}"
else
  INSTALL_URL="https://raw.githubusercontent.com/premeq/remcc/${REF}/install.sh"
  INIT_REF_ARGS=(--ref "$REF")
  EXPECTED_SRC_REF="$REF"
fi
FAILED=0

step() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=1; }

snapshot() {
  # snapshot <out-dir>
  local out="$1"
  mkdir -p "$out"
  gh api "repos/$TARGET/branches/main/protection" 2>/dev/null > "$out/protection.json" || echo '{}' > "$out/protection.json"
  gh api "repos/$TARGET/rulesets" > "$out/rulesets.json"
}

normalize() {
  # normalize <file> — strip volatile fields before diffing
  jq -S 'walk(if type=="object" then del(.id,.node_id,.created_at,.updated_at) else . end)' "$1"
}

# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------
if [ "$SKIP_SETUP" = 0 ]; then
  step "Setup: create $TARGET, seed prereqs in $WORKDIR"
  gh repo create "$TARGET" --private --add-readme
  gh repo clone "$TARGET" "$WORKDIR"
  cd "$WORKDIR"
  cat > package.json <<JSON
{
  "name": "remcc-smoke",
  "private": true,
  "packageManager": "${SMOKE_PM_SPEC}"
}
JSON
  # An empty lockfile is rejected by both managers' `--frozen-lockfile` the
  # moment the workflow runs `<pm> install`. Seed a real lockfile instead
  # (pnpm: a dep-free `pnpm install`; bun: `bun add` one tiny zero-dep pkg,
  # since `bun install` deletes an empty lockfile — see note above).
  "${SMOKE_PM_INSTALL[@]}" >/dev/null 2>&1 \
    || { echo "${SMOKE_PM} seed install (${SMOKE_PM_INSTALL[*]}) failed" >&2; exit 1; }
  mkdir -p openspec .claude
  # Seed a realistic operator-customized .claude/settings.json so the
  # overwrite assertion in Step 3 has something concrete to detect.
  cat > .claude/settings.json <<'JSON'
{
  "permissions": {
    "allow": ["Bash(npm test)"]
  }
}
JSON
  touch openspec/.gitkeep
  git add .
  git -c user.email=smoke@example.com -c user.name=smoke commit -m "Seed prereqs"
  git push origin main
fi

cd "$WORKDIR"

# ----------------------------------------------------------------------------
# Step 1 — curl-piped --help (scenario: process substitution)
# ----------------------------------------------------------------------------
step "Step 1: curl-piped --help"
HELP_OUT="$(bash <(curl -fsSL "$INSTALL_URL") --help)"
if grep -qE '^\s*init\b' <<<"$HELP_OUT"; then
  pass "help lists 'init' subcommand"
else
  fail "help does not list 'init' subcommand"
  printf '%s\n' "$HELP_OUT" >&2
fi

# ----------------------------------------------------------------------------
# Step 2 — first init
# ----------------------------------------------------------------------------
step "Step 2: first init"
git checkout main
bash <(curl -fsSL "$INSTALL_URL") init ${INIT_REF_ARGS[@]+"${INIT_REF_ARGS[@]}"}
pass "first init exited 0"

# Snapshot after run #1 (this is the reference state for idempotency)
S1="$(mktemp -d)"; snapshot "$S1"

# ----------------------------------------------------------------------------
# Step 2b — verify App credentials + legacy PAT cleanup
# Asserts the bootstrap installed the three new App config items and
# (since this target was freshly created) no legacy WORKFLOW_PAT exists.
# ----------------------------------------------------------------------------
step "Step 2b: App credentials installed + legacy WORKFLOW_PAT absent"
SECRET_NAMES="$(gh secret list --repo "$TARGET" --json name --jq '.[].name')"
for s in REMCC_APP_ID REMCC_APP_PRIVATE_KEY; do
  if grep -qx "$s" <<<"$SECRET_NAMES"; then
    pass "secret $s present"
  else
    fail "secret $s missing"
  fi
done
if grep -qx "WORKFLOW_PAT" <<<"$SECRET_NAMES"; then
  fail "legacy WORKFLOW_PAT secret unexpectedly present on a fresh init"
else
  pass "no legacy WORKFLOW_PAT secret"
fi
SLUG_VAL="$(gh api "repos/$TARGET/actions/variables/REMCC_APP_SLUG" --jq .value 2>/dev/null || echo "")"
if [ "$SLUG_VAL" = "$REMCC_APP_SLUG" ]; then
  pass "variable REMCC_APP_SLUG = $SLUG_VAL"
else
  fail "variable REMCC_APP_SLUG mismatch (got: '$SLUG_VAL', want: '$REMCC_APP_SLUG')"
fi

# ----------------------------------------------------------------------------
# Step 3 — verify written artifacts on remcc-init branch
# ----------------------------------------------------------------------------
step "Step 3: verify written artifacts"
git fetch origin remcc-init
git checkout remcc-init

for f in .github/workflows/opsx-apply.yml .claude/settings.json openspec/config.yaml .remcc/version; do
  [ -f "$f" ] && pass "exists: $f" || fail "missing: $f"
done

# Operator-seeded .claude/settings.json should be overwritten by the template.
if grep -q '"Bash(npm test)"' .claude/settings.json; then
  fail "operator seed survived in .claude/settings.json — template did NOT overwrite"
else
  pass "operator-seeded .claude/settings.json was overwritten by the template"
fi

SRC_REF="$(jq -r .source_ref < .remcc/version)"
SRC_SHA="$(jq -r .source_sha < .remcc/version)"
INST_AT="$(jq -r .installed_at < .remcc/version)"
[ "$SRC_REF" = "$EXPECTED_SRC_REF" ] && pass "source_ref=$SRC_REF" || fail "source_ref=$SRC_REF (expected $EXPECTED_SRC_REF)"
[[ "$SRC_SHA" =~ ^[0-9a-f]{40}$ ]] && pass "source_sha is 40-char SHA" || fail "source_sha=$SRC_SHA"
[[ "$INST_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] && pass "installed_at ISO 8601: $INST_AT" || fail "installed_at=$INST_AT"

# ----------------------------------------------------------------------------
# Step 4 — PR body
# ----------------------------------------------------------------------------
step "Step 4: PR body"
PR_BODY="$(gh pr view remcc-init --repo "$TARGET" --json body --jq .body)"
for f in opsx-apply.yml .claude/settings.json openspec/config.yaml .remcc/version; do
  grep -q "$f" <<<"$PR_BODY" && pass "PR body mentions $f" || fail "PR body missing $f"
done
grep -qiE 'pre-existing|customization|collision|verify the diff' <<<"$PR_BODY" \
  && pass "PR body flags pre-existing paths" \
  || fail "PR body does not flag pre-existing paths"
grep -qi 'smoke' <<<"$PR_BODY" \
  && pass "PR body has smoke-test one-liner" \
  || fail "PR body lacks smoke-test one-liner"

# ----------------------------------------------------------------------------
# Step 5 — no apply run triggered
# ----------------------------------------------------------------------------
step "Step 5: no opsx-apply run"
RUNS="$(gh run list --repo "$TARGET" --workflow opsx-apply.yml --json databaseId --jq 'length' 2>/dev/null || echo 0)"
[ "$RUNS" = "0" ] && pass "no opsx-apply runs" || fail "$RUNS opsx-apply run(s) triggered"

# ----------------------------------------------------------------------------
# Step 6 — second init for bootstrap idempotency
# Spec scenario: "Re-running init is a bootstrap no-op" — exits zero, no
# GitHub-side config drift, and reuses the existing PR rather than opening
# another. (Task 5.6's "already up to date" path requires post-merge state
# and is exercised by task 7.3, not here.)
# ----------------------------------------------------------------------------
step "Step 6: second init (idempotency)"
git checkout main
bash <(curl -fsSL "$INSTALL_URL") init ${INIT_REF_ARGS[@]+"${INIT_REF_ARGS[@]}"}
pass "second init exited 0"

PR_COUNT="$(gh pr list --repo "$TARGET" --head remcc-init --state open --json number --jq 'length')"
[ "$PR_COUNT" = "1" ] \
  && pass "exactly one open PR for remcc-init (no duplicate opened)" \
  || fail "expected 1 open PR for remcc-init, found $PR_COUNT"

S2="$(mktemp -d)"; snapshot "$S2"
for n in protection rulesets; do
  if diff -q <(normalize "$S1/$n.json") <(normalize "$S2/$n.json") >/dev/null; then
    pass "idempotent: $n"
  else
    fail "drift detected: $n"
    diff <(normalize "$S1/$n.json") <(normalize "$S2/$n.json") | head -20 >&2
  fi
done

# ----------------------------------------------------------------------------
# Step 7 — re-run init after merge preserves installed_at (task 1.4 of
# install-sh-upgrade). After merging the init PR, .remcc/version is on main;
# re-running init should read it from origin/main and preserve installed_at.
# Templates already match main, so the run hits "already up to date".
# ----------------------------------------------------------------------------
step "Step 7: re-run init after merge preserves installed_at"
git checkout main
gh pr merge --repo "$TARGET" remcc-init --merge --delete-branch >/dev/null
git pull --ff-only >/dev/null

INST_AT_BEFORE="$(jq -r .installed_at < .remcc/version)"
pass "post-merge installed_at on main: $INST_AT_BEFORE"

bash <(curl -fsSL "$INSTALL_URL") init ${INIT_REF_ARGS[@]+"${INIT_REF_ARGS[@]}"}
pass "post-merge init exited 0"

git fetch --quiet origin main
INST_AT_AFTER="$(git show origin/main:.remcc/version | jq -r .installed_at)"
[ "$INST_AT_BEFORE" = "$INST_AT_AFTER" ] \
  && pass "installed_at preserved on origin/main: $INST_AT_AFTER" \
  || fail "installed_at changed: $INST_AT_BEFORE → $INST_AT_AFTER"

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------
if [ "$CLEANUP" = 1 ]; then
  step "Cleanup"
  gh repo delete "$TARGET" --yes
  rm -rf "$WORKDIR" "$S1" "$S2"
  pass "deleted $TARGET and $WORKDIR"
else
  printf '\nArtifacts left in place:\n  repo:    %s\n  workdir: %s\n  snaps:   %s, %s\nRe-run with --cleanup to delete.\n' \
    "$TARGET" "$WORKDIR" "$S1" "$S2"
fi

echo
if [ "$FAILED" = 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
