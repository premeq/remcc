#!/usr/bin/env bash
#
# install.sh — adopt remcc in a target GitHub repository.
#
# Usage (one-liner):
#   bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) init
#
# Usage (inspect first):
#   curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh -o install.sh
#   less install.sh
#   bash install.sh init
#
# Subcommands:
#   init          adopt remcc in the current working directory's repo
#   upgrade       refresh template-managed files in an already-adopted repo
#   reconfigure   re-run the GitHub-side bootstrap on an already-adopted repo
#   --help        show this message
#
# Options (init, upgrade, reconfigure):
#   --ref <ref>   remcc tag or commit to fetch templates from. Defaults to
#                 the latest release tag on premeq/remcc, falling back to
#                 'main' with a warning if no releases exist.

set -euo pipefail

readonly REMCC_REPO="premeq/remcc"
readonly REMCC_CLONE_URL="https://github.com/${REMCC_REPO}.git"
readonly INIT_BRANCH="remcc-init"
readonly INIT_COMMIT_SUBJECT="Adopt remcc via install.sh init"
readonly UPGRADE_BRANCH="remcc-upgrade"
readonly UPGRADE_COMMIT_SUBJECT="Upgrade remcc via install.sh upgrade"

# Tempdir for the remcc source clone. Cleaned up on exit.
REMCC_SRC_DIR=""
# Tempdir for the pre-overwrite working-tree snapshot (upgrade only).
UPGRADE_SNAPSHOT_DIR=""

cleanup() {
  if [ -n "${REMCC_SRC_DIR}" ] && [ -d "${REMCC_SRC_DIR}" ]; then
    rm -rf "${REMCC_SRC_DIR}"
  fi
  if [ -n "${UPGRADE_SNAPSHOT_DIR}" ] && [ -d "${UPGRADE_SNAPSHOT_DIR}" ]; then
    rm -rf "${UPGRADE_SNAPSHOT_DIR}"
  fi
}
trap cleanup EXIT

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
log()  { printf '==> %s\n' "$*"; }
sub()  { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Read a line from /dev/tty so the script works under `curl | bash -s --`
# (where stdin is the curl pipe rather than the terminal).
read_tty() {
  local prompt="$1" __varname="$2" __val=""
  if [ -r /dev/tty ]; then
    printf '%s' "${prompt}" >/dev/tty
    IFS= read -r __val </dev/tty
  else
    printf '%s' "${prompt}" >&2
    IFS= read -r __val
  fi
  printf -v "${__varname}" '%s' "${__val}"
}

# ----------------------------------------------------------------------------
# Usage / help
# ----------------------------------------------------------------------------

usage_root() {
  cat <<'USAGE'
install.sh — adopt or upgrade remcc (remote Claude Code) in a GitHub repo.

Usage:
  install.sh <subcommand> [options]
  install.sh --help

Subcommands:
  init         Adopt remcc in the current repository (prereq check, GitHub-side
               bootstrap, template-file install, pull request).
  upgrade      Refresh template-managed files in an already-adopted repo at a
               newer remcc ref. Skips bootstrap (one-time `init` work). Opens
               a pull request on branch `remcc-upgrade`.
  reconfigure  Re-run only the GitHub-side bootstrap against an already-
               adopted repo. Does NOT touch the working tree, create a
               branch, or open a pull request. Use after an upgrade that
               changed bootstrap-managed config.

Run `install.sh <subcommand> --help` for subcommand-specific help.
USAGE
}

usage_init() {
  cat <<'USAGE'
install.sh init — adopt remcc in the current repository.

Usage:
  install.sh init [--ref <tag-or-sha>] [--help]

Options:
  --ref <ref>   remcc tag or commit to fetch templates from. Defaults to
                the latest release tag on premeq/remcc, falling back to
                'main' with a warning if no releases exist.

Behavior:
  1. Verifies prerequisites (admin on target, OpenSpec initialised,
     pnpm- or bun-managed repo with a matching lockfile present,
     local tools installed).
  2. Resolves a remcc ref and shallow-clones premeq/remcc at that ref
     into a tempdir (cleaned up on exit).
  3. Runs the cloned gh-bootstrap.sh against the target repo (branch
     protection, rulesets, ANTHROPIC_API_KEY + REMCC_APP_ID +
     REMCC_APP_PRIVATE_KEY secrets, REMCC_APP_SLUG variable, apply
     configuration variables). Idempotent on re-run.
  4. Writes template-managed files (overwrites any existing copies):
       .github/workflows/opsx-apply.yml
       .claude/settings.json
       openspec/config.yaml
       .remcc/version
  5. Creates branch `remcc-init`, commits the template diff, pushes,
     and opens a pull request against `main`. PR body flags any
     pre-existing template-managed paths so the operator can verify
     the diff hasn't clobbered local customizations.

If the template diff is empty (re-install with no upstream changes),
init prints "already up to date" and exits zero without creating a
branch or PR.

Environment passthrough (consumed by gh-bootstrap.sh):
  ANTHROPIC_API_KEY      Anthropic API key (prompted if unset).
  REMCC_APP_ID           Numeric GitHub App ID of the remcc App
                         (prompted if unset).
  REMCC_APP_PRIVATE_KEY  PEM-encoded private key of the remcc GitHub App
                         (prompted if unset; multi-line, accepted via stdin).
  REMCC_APP_SLUG         GitHub App slug (the <slug> in github.com/apps/<slug>;
                         prompted if unset).
  OPSX_APPLY_MODEL       Per-repo default Claude model alias.
  OPSX_APPLY_EFFORT      Per-repo default thinking-budget level.
USAGE
}

usage_upgrade() {
  cat <<'USAGE'
install.sh upgrade — refresh remcc templates in an already-adopted repo.

Usage:
  install.sh upgrade [--ref <tag-or-sha>] [--help]

Options:
  --ref <ref>   remcc tag or commit to fetch templates from. Defaults to
                the latest release tag on premeq/remcc, falling back to
                'main' with a warning if no releases exist.

Behavior:
  1. Verifies the target was previously adopted: `.remcc/version` must
     exist on `origin/main`. If it does not, the command exits non-zero
     pointing at `install.sh init`.
  2. Verifies the same prerequisites as `init` (admin on target,
     OpenSpec initialised, pnpm- or bun-managed repo with a matching
     lockfile present, local tools).
  3. Resolves a remcc ref and shallow-clones premeq/remcc at that ref
     into a tempdir (cleaned up on exit).
  4. Overwrites template-managed files in the working tree:
       .github/workflows/opsx-apply.yml
       .claude/settings.json
       openspec/config.yaml
       .remcc/version
     `.remcc/version`'s `installed_at` is preserved from the previously
     committed marker (read from `origin/remcc-upgrade:.remcc/version`
     if that branch exists, otherwise from `origin/main:.remcc/version`).
  5. If the resolved templates match what is already on `origin/main`,
     prints `already up to date` and exits zero without creating a
     branch or PR.
  6. Creates branch `remcc-upgrade` from `main`, commits the template
     diff, pushes (force-with-lease), and opens a pull request against
     `main`. Re-running with an existing open `remcc-upgrade` PR does
     not open a duplicate.

`upgrade` does NOT re-run `gh-bootstrap.sh`. Branch protection,
rulesets, secrets, and repository variables are one-time `init` work.
If a release ships changes to bootstrap-managed config (e.g. new
secrets), use `install.sh reconfigure` after the upgrade PR merges.
USAGE
}

usage_reconfigure() {
  cat <<'USAGE'
install.sh reconfigure — re-run the GitHub-side bootstrap on an adopted repo.

Usage:
  install.sh reconfigure [--ref <tag-or-sha>] [--help]

Options:
  --ref <ref>   remcc tag or commit to fetch the bootstrap script from.
                Defaults to the latest release tag on premeq/remcc, falling
                back to 'main' with a warning if no releases exist.

Behavior:
  1. Verifies the target was previously adopted: `.remcc/version` must
     exist on `origin/main`. If it does not, the command exits non-zero
     pointing at `install.sh init`.
  2. Re-runs the same prerequisite checks as `init` and `upgrade`.
  3. Resolves a remcc ref and shallow-clones premeq/remcc at that ref
     into a tempdir (cleaned up on exit).
  4. Runs ONLY the cloned `gh-bootstrap.sh` against the target repo.
     Idempotent on re-run.

`install.sh reconfigure` does NOT touch the working tree, write a
version marker, create a branch, or open a pull request. It is the
explicit re-bootstrap entry point — use it after a remcc release that
changed bootstrap-managed config (e.g. the v0.3.0 GitHub App
migration; see `docs/SETUP.md`).

Environment passthrough (consumed by gh-bootstrap.sh):
  ANTHROPIC_API_KEY      Anthropic API key (prompted if unset).
  REMCC_APP_ID           Numeric GitHub App ID of the remcc App
                         (prompted if unset).
  REMCC_APP_PRIVATE_KEY  PEM-encoded private key of the remcc GitHub App
                         (prompted if unset; multi-line, accepted via stdin).
  REMCC_APP_SLUG         GitHub App slug (the <slug> in github.com/apps/<slug>;
                         prompted if unset).
  OPSX_APPLY_MODEL       Per-repo default Claude model alias.
  OPSX_APPLY_EFFORT      Per-repo default thinking-budget level.
USAGE
}

# ----------------------------------------------------------------------------
# Prerequisite verification — runs BEFORE any GitHub mutation or file write.
# ----------------------------------------------------------------------------

require_local_tool() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 \
    || err "required local tool not found on PATH: ${name}"
}

verify_node_version() {
  local raw major minor
  raw="$(node -v 2>/dev/null | sed 's/^v//')" \
    || err "node not found on PATH (need >= 20.19)"
  major="${raw%%.*}"
  minor="${raw#*.}"; minor="${minor%%.*}"
  if [ "${major}" -lt 20 ] || { [ "${major}" -eq 20 ] && [ "${minor}" -lt 19 ]; }; then
    err "node version ${raw} is below the required 20.19"
  fi
}

verify_target_is_admin() {
  local repo="$1" perm
  perm="$(gh repo view "${repo}" --json viewerPermission --jq .viewerPermission 2>/dev/null)" \
    || err "could not query viewer permission on ${repo} (is gh authenticated?)"
  if [ "${perm}" != "ADMIN" ]; then
    err "you are not admin on ${repo} (viewer permission: ${perm:-unknown})"
  fi
}

verify_main_branch_exists() {
  local repo="$1"
  gh api "repos/${repo}/branches/main" --silent >/dev/null 2>&1 \
    || err "remote branch 'main' does not exist on ${repo}"
}

verify_prereqs() {
  local repo="$1" pm
  log "Verifying prerequisites"

  require_local_tool gh
  require_local_tool jq
  require_local_tool git
  verify_node_version

  # Resolve the target repo's declared package manager (pnpm or bun) and
  # require only that manager's local tool — pnpm adopters need pnpm, bun
  # adopters need bun, neither needs the other.
  pm="$(resolve_package_manager)"
  require_local_tool "${pm}"
  sub "local tools: gh, jq, git, node, ${pm} ok"

  gh auth status >/dev/null 2>&1 \
    || err "gh is not authenticated; run 'gh auth login' first"

  verify_target_is_admin "${repo}"
  sub "admin on ${repo}"

  verify_main_branch_exists "${repo}"
  sub "remote branch 'main' present"

  [ -d openspec ] || err "openspec/ not found at repo root (initialise OpenSpec first)"
  sub "openspec/ present"

  [ -d .claude ] || err ".claude/ not found at repo root (commit Claude Code skills/commands first)"
  sub ".claude/ present"

  verify_package_manager_lockfile "${pm}"
}

# remcc supports pnpm- or bun-managed target repos. The package manager is
# declared authoritatively in package.json#packageManager — the same field
# pnpm/action-setup@v4 and oven-sh/setup-bun@v2 resolve their version from,
# which keeps the verifier and the workflow runner in lockstep. Echoes
# `pnpm` or `bun` on stdout; errs (no stdout) on absent/npm@/yarn@/unparseable.
# Emits no log/sub output: the result is captured via command substitution.
resolve_package_manager() {
  [ -f package.json ] \
    || err "package.json not found at repo root (remcc supports pnpm- or bun-managed repos only)"
  local pm
  pm="$(jq -r '.packageManager // empty' < package.json 2>/dev/null)" \
    || err "could not parse package.json as JSON"
  [ -n "${pm}" ] \
    || err "package.json is missing the 'packageManager' field (set it to e.g. 'pnpm@9.12.3' or 'bun@1.1.34' — required by the workflow's package-manager setup step)"
  case "${pm}" in
    pnpm@*) echo pnpm ;;
    bun@*)  echo bun ;;
    *) err "package.json#packageManager is '${pm}'; remcc supports pnpm- or bun-managed repos only (value must start with 'pnpm@' or 'bun@')" ;;
  esac
}

# Given the resolved manager, require its matching root lockfile: pnpm-lock.yaml
# for pnpm, or bun.lock (text, bun >= 1.2) / bun.lockb (binary, bun < 1.2) for
# bun. Fails closed on a mismatch so a stale foreign lockfile cannot mask a
# misdeclared packageManager.
verify_package_manager_lockfile() {
  local pm="$1"
  case "${pm}" in
    pnpm)
      [ -f pnpm-lock.yaml ] \
        || err "package.json declares pnpm but pnpm-lock.yaml is not present at the repo root"
      sub "package manager: pnpm (package.json#packageManager + pnpm-lock.yaml present)"
      ;;
    bun)
      [ -f bun.lock ] || [ -f bun.lockb ] \
        || err "package.json declares bun but neither bun.lock nor bun.lockb is present at the repo root"
      sub "package manager: bun (package.json#packageManager + bun lockfile present)"
      ;;
    *) err "internal: unsupported package manager '${pm}'" ;;
  esac
}

# ----------------------------------------------------------------------------
# Pre-mutation guards: target must be a git repo, on main, clean.
# ----------------------------------------------------------------------------

resolve_target_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || err "not inside a git repository"
  gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null \
    || err "could not resolve a GitHub repo from the current git context (no 'origin' remote?)"
}

verify_clean_main() {
  local subcmd="${1:-init}" branch
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
  [ "${branch}" = "main" ] \
    || err "must be on branch 'main' to run ${subcmd} (currently on '${branch:-DETACHED}')"
  if [ -n "$(git status --porcelain)" ]; then
    err "working tree is dirty; commit or stash changes before running ${subcmd}"
  fi
}

# Upgrade pre-flight: refuse if `.remcc/version` is absent from origin/main.
# Reads from origin/main rather than the working tree so the answer is
# unambiguous about what is actually committed (and so it survives a future
# branch rebuild from main). Runs BEFORE any GitHub mutation or file write.
verify_marker_on_main() {
  local repo="$1"
  git fetch --quiet origin main 2>/dev/null \
    || err "could not fetch origin/main from ${repo}; check network/auth"
  if ! git cat-file -e origin/main:.remcc/version 2>/dev/null; then
    err ".remcc/version not found on origin/main of ${repo}; this target has not been adopted yet — run 'install.sh init' first"
  fi
}

# ----------------------------------------------------------------------------
# Resolve the remcc ref, then shallow-clone into a tempdir.
# ----------------------------------------------------------------------------

resolve_ref() {
  local explicit="$1"
  if [ -n "${explicit}" ]; then
    printf '%s' "${explicit}"
    return
  fi
  local tag
  tag="$(gh api "repos/${REMCC_REPO}/releases/latest" --jq .tag_name 2>/dev/null || true)"
  if [ -n "${tag}" ] && [ "${tag}" != "null" ]; then
    printf '%s' "${tag}"
    return
  fi
  warn "no releases on ${REMCC_REPO}; falling back to 'main' (unstable)"
  printf 'main'
}

clone_remcc_at() {
  local ref="$1"
  REMCC_SRC_DIR="$(mktemp -d -t remcc-src-XXXXXX)"
  log "Fetching remcc@${ref} into ${REMCC_SRC_DIR}"
  # `git clone --branch` rejects raw commit SHAs; use init + fetch + checkout
  # so the same code path serves tags, branches, and SHAs (the documented
  # forms of --ref). GitHub's allowReachableSHA1InWant permits SHA fetches.
  (
    cd "${REMCC_SRC_DIR}" \
      && git init --quiet \
      && git remote add origin "${REMCC_CLONE_URL}" \
      && git fetch --quiet --depth 1 origin "${ref}" \
      && git checkout --quiet FETCH_HEAD
  ) || err "git clone of ${REMCC_REPO}@${ref} failed"
  sub "ok"
}

# ----------------------------------------------------------------------------
# Template-managed paths.
# ----------------------------------------------------------------------------

readonly TEMPLATE_PATHS=(
  ".github/workflows/opsx-apply.yml"
  ".claude/settings.json"
  "openspec/config.yaml"
  ".remcc/version"
)

template_source_for() {
  case "$1" in
    ".github/workflows/opsx-apply.yml") printf '%s' "${REMCC_SRC_DIR}/templates/workflows/opsx-apply.yml" ;;
    ".claude/settings.json")            printf '%s' "${REMCC_SRC_DIR}/templates/claude/settings.json" ;;
    "openspec/config.yaml")             printf '%s' "${REMCC_SRC_DIR}/templates/openspec/config.yaml" ;;
    ".remcc/version")                   printf '' ;;   # generated, not copied
    *) err "internal: no source mapping for template path: $1" ;;
  esac
}

# ----------------------------------------------------------------------------
# .remcc/version marker.
# ----------------------------------------------------------------------------

resolved_source_sha() {
  git -C "${REMCC_SRC_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown"
}

write_version_marker() {
  local target="$1" ref="$2" prev_json="$3" sha now prev_at
  sha="$(resolved_source_sha)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Preserve installed_at from the previously committed marker (caller passes
  # the JSON bytes; empty means "no previous marker, stamp now"). Reads from a
  # git ref rather than the working tree because the upgrade/init branch is
  # rebuilt from main before the marker is written.
  if [ -n "${prev_json}" ]; then
    prev_at="$(printf '%s' "${prev_json}" | jq -r '.installed_at // empty' 2>/dev/null || true)"
    [ -n "${prev_at}" ] && now="${prev_at}"
  fi

  mkdir -p "$(dirname -- "${target}")"
  cat >"${target}" <<JSON
{
  "source_ref": "${ref}",
  "source_sha": "${sha}",
  "installed_at": "${now}"
}
JSON
}

# Read .remcc/version from origin/<branch>. Fetches the branch silently
# (failures are tolerated — a missing remote ref produces an empty string),
# then `git show`s the file. Empty stdout means absent.
read_marker_from_origin() {
  local branch="$1"
  git fetch --quiet origin "${branch}" 2>/dev/null || true
  git show "origin/${branch}:.remcc/version" 2>/dev/null || true
}

# ----------------------------------------------------------------------------
# Snapshot pre-existing template paths (for PR-body collision flagging).
# ----------------------------------------------------------------------------

snapshot_preexisting() {
  local path
  for path in "${TEMPLATE_PATHS[@]}"; do
    if [ -e "${path}" ]; then
      printf '%s\n' "${path}"
    fi
  done
}

# ----------------------------------------------------------------------------
# Write templates unconditionally; generate the version marker.
# ----------------------------------------------------------------------------

install_templates() {
  local ref="$1" prev_marker_json="$2" path src
  log "Installing template-managed files"
  for path in "${TEMPLATE_PATHS[@]}"; do
    if [ "${path}" = ".remcc/version" ]; then
      write_version_marker "${path}" "${ref}" "${prev_marker_json}"
      sub "wrote ${path} (generated)"
      continue
    fi
    src="$(template_source_for "${path}")"
    [ -f "${src}" ] || err "fetched template missing: ${src}"
    mkdir -p "$(dirname -- "${path}")"
    cp "${src}" "${path}"
    sub "wrote ${path}"
  done
}

# ----------------------------------------------------------------------------
# Invoke the cloned bootstrap script (GitHub-side configuration).
# ----------------------------------------------------------------------------

run_bootstrap() {
  local bootstrap="${REMCC_SRC_DIR}/templates/gh-bootstrap.sh"
  log "Running gh-bootstrap.sh (GitHub-side configuration)"
  [ -f "${bootstrap}" ] || err "fetched bootstrap script missing: ${bootstrap}"
  bash "${bootstrap}"
}

# ----------------------------------------------------------------------------
# Branch / commit / push / PR.
# ----------------------------------------------------------------------------

create_init_branch() {
  # Re-runs leave the branch behind. Drop it so we always rebuild from main
  # with the current templates.
  if git rev-parse --verify --quiet "${INIT_BRANCH}" >/dev/null; then
    git branch -D "${INIT_BRANCH}" >/dev/null
  fi
  git checkout -b "${INIT_BRANCH}" main >/dev/null
}

stage_and_commit() {
  local ref="$1" sha
  sha="$(resolved_source_sha)"
  git add -- "${TEMPLATE_PATHS[@]}"
  if git diff --cached --quiet; then
    return 1   # nothing to commit
  fi
  git commit -m "$(cat <<EOF
${INIT_COMMIT_SUBJECT}

Source: remcc ${ref} (${sha})

Files written by install.sh init:
  .github/workflows/opsx-apply.yml
  .claude/settings.json
  openspec/config.yaml
  .remcc/version
EOF
)" >/dev/null
  return 0
}

build_pr_body() {
  local repo="$1" preexisting="$2" ref="$3" sha
  sha="$(resolved_source_sha)"

  printf '## remcc adoption\n\n'
  printf 'This PR was opened by `install.sh init`. It installs the\n'
  printf 'template-managed files remcc needs and records the source ref.\n\n'
  printf '**Source:** remcc `%s` (`%s`)\n\n' "${ref}" "${sha}"

  printf '### Files written\n\n'
  local p
  for p in "${TEMPLATE_PATHS[@]}"; do
    printf -- '- `%s`\n' "${p}"
  done
  printf '\n'

  if [ -n "${preexisting}" ]; then
    printf '### Pre-existing files (verify the diff)\n\n'
    printf 'These paths existed in your repo before `init` ran. The\n'
    printf 'installer overwrote them with the template contents; if you\n'
    printf 'had local customizations, re-apply them before merging.\n\n'
    while IFS= read -r p; do
      [ -z "${p}" ] && continue
      printf -- '- `%s`\n' "${p}"
    done <<<"${preexisting}"
    printf '\n'
  else
    printf '### Pre-existing files\n\nNone — every template-managed path was new.\n\n'
  fi

  printf '### Smoke test (after merging)\n\n'
  printf 'Run this from a clone of `%s` once this PR is on `main`:\n\n' "${repo}"
  printf '```sh\n'
  printf 'git checkout main && git pull --ff-only\n'
  printf 'git checkout -b change/test-apply\n'
  printf 'mkdir -p openspec/changes/test-apply\n'
  printf "cat > openspec/changes/test-apply/proposal.md <<'EOF'\n"
  printf '## Why\n\nSmoke-test the remcc apply path end-to-end.\n\n'
  printf '## What Changes\n\nCreate a single empty file `smoke.txt`.\n'
  printf 'EOF\n'
  printf "cat > openspec/changes/test-apply/tasks.md <<'EOF'\n"
  printf '## 1. Smoke\n\n- [ ] 1.1 Create empty file `smoke.txt` at repo root.\n'
  printf 'EOF\n'
  printf 'git add openspec/changes/test-apply\n'
  printf "git commit -m 'Add smoke test change'\n"
  printf 'git push -u origin change/test-apply\n'
  printf "git commit --allow-empty -m '@change-apply: smoke test'\n"
  printf 'git push\n'
  printf '```\n\n'
  printf 'Watch the Actions tab for the `opsx-apply` run.\n'
}

push_and_open_pr() {
  local repo="$1" preexisting="$2" ref="$3" body existing_pr

  # If the remote branch exists and its tree matches ours, skip the push
  # (the previous run's tip is already correct).
  git fetch origin "${INIT_BRANCH}" >/dev/null 2>&1 || true
  if git rev-parse --verify --quiet "refs/remotes/origin/${INIT_BRANCH}" >/dev/null \
     && [ "$(git rev-parse 'HEAD^{tree}')" = "$(git rev-parse "origin/${INIT_BRANCH}^{tree}")" ]; then
    log "Branch ${INIT_BRANCH} already in sync with origin; skipping push"
  else
    log "Pushing branch ${INIT_BRANCH} to origin"
    git push --force-with-lease -u origin "${INIT_BRANCH}" >/dev/null 2>&1 \
      || err "failed to push ${INIT_BRANCH} to origin"
  fi

  # If a PR is already open for this branch, leave it alone.
  existing_pr="$(gh pr list --repo "${repo}" --head "${INIT_BRANCH}" --state open \
                   --json number --jq '.[0].number // empty' 2>/dev/null || true)"
  if [ -n "${existing_pr}" ]; then
    log "Pull request #${existing_pr} already open for ${INIT_BRANCH}; not opening another"
    return 0
  fi

  body="$(build_pr_body "${repo}" "${preexisting}" "${ref}")"
  log "Opening pull request"
  gh pr create \
    --base main \
    --head "${INIT_BRANCH}" \
    --title "${INIT_COMMIT_SUBJECT}" \
    --body "${body}" \
    || err "failed to open pull request"
}

# ----------------------------------------------------------------------------
# Upgrade-specific helpers.
# ----------------------------------------------------------------------------

# Capture pre-overwrite working-tree contents of each template path (except
# the generated `.remcc/version`) into a tempdir. These feed the per-path
# "Local diffs before upgrade" flag in the PR body — paths whose pre-upgrade
# content diverges from the *previous* template are about to be overwritten
# by the new template.
snapshot_preupgrade_paths() {
  local out="$1" path
  for path in "${TEMPLATE_PATHS[@]}"; do
    [ "${path}" = ".remcc/version" ] && continue
    if [ -f "${path}" ]; then
      mkdir -p "${out}/$(dirname -- "${path}")"
      cp "${path}" "${out}/${path}"
    fi
  done
}

# Diff each pre-overwrite snapshot against the new template source.
# Prints (newline-separated) the paths where the operator's tree differed
# from the new template.
compute_flagged_paths() {
  local snap="$1" path src
  for path in "${TEMPLATE_PATHS[@]}"; do
    [ "${path}" = ".remcc/version" ] && continue
    src="$(template_source_for "${path}")"
    if [ -f "${snap}/${path}" ] && [ -f "${src}" ]; then
      if ! diff -q "${snap}/${path}" "${src}" >/dev/null 2>&1; then
        printf '%s\n' "${path}"
      fi
    fi
  done
}

create_upgrade_branch() {
  if git rev-parse --verify --quiet "${UPGRADE_BRANCH}" >/dev/null; then
    git branch -D "${UPGRADE_BRANCH}" >/dev/null
  fi
  git checkout -b "${UPGRADE_BRANCH}" main >/dev/null
}

stage_and_commit_upgrade() {
  local prev_ref="$1" prev_sha="$2" new_ref="$3" new_sha="$4"
  git add -- "${TEMPLATE_PATHS[@]}"
  if git diff --cached --quiet; then
    return 1   # nothing to commit
  fi
  git commit -m "$(cat <<EOF
${UPGRADE_COMMIT_SUBJECT}

Upgrading remcc ${prev_ref} (${prev_sha}) -> ${new_ref} (${new_sha})

Files refreshed by install.sh upgrade:
  .github/workflows/opsx-apply.yml
  .claude/settings.json
  openspec/config.yaml
  .remcc/version
EOF
)" >/dev/null
  return 0
}

build_upgrade_pr_body() {
  local repo="$1" prev_ref="$2" prev_sha="$3" new_ref="$4" new_sha="$5" flagged_paths="$6"

  printf '## remcc upgrade\n\n'
  printf 'This PR was opened by `install.sh upgrade`. It refreshes the\n'
  printf 'template-managed files at a newer remcc ref.\n\n'
  printf '**Upgrading remcc** `%s` (`%s`) → `%s` (`%s`)\n\n' \
    "${prev_ref}" "${prev_sha}" "${new_ref}" "${new_sha}"

  printf '### Files written\n\n'
  local p
  for p in "${TEMPLATE_PATHS[@]}"; do
    printf -- '- `%s`\n' "${p}"
  done
  printf '\n'

  if [ -n "${flagged_paths}" ]; then
    printf '### Local diffs before upgrade\n\n'
    printf 'These paths diverged from the previous template before this\n'
    printf 'upgrade ran. The upgrade overwrote them with the new template;\n'
    printf 'verify the merge in the PR diff below before merging.\n\n'
    while IFS= read -r p; do
      [ -z "${p}" ] && continue
      printf -- '- `%s`\n' "${p}"
    done <<<"${flagged_paths}"
    printf '\n'
  fi

  printf '### What happens next\n\n'
  printf 'The upgraded workflow takes effect on the next apply run after\n'
  printf 'this PR merges. Your next `change/**` push on `%s` exercises\n' "${repo}"
  printf 'the refreshed templates end-to-end — no separate smoke test is\n'
  printf 'needed (you already ran one at `init`).\n'
}

push_and_open_upgrade_pr() {
  local repo="$1" prev_ref="$2" prev_sha="$3" new_ref="$4" new_sha="$5" flagged_paths="$6"
  local body existing_pr

  # --prune drops a stale local tracking ref when the remote branch was
  # deleted post-merge, so force-with-lease below doesn't abort with `stale info`.
  git fetch --prune origin "${UPGRADE_BRANCH}" >/dev/null 2>&1 || true
  if git rev-parse --verify --quiet "refs/remotes/origin/${UPGRADE_BRANCH}" >/dev/null \
     && [ "$(git rev-parse 'HEAD^{tree}')" = "$(git rev-parse "origin/${UPGRADE_BRANCH}^{tree}")" ]; then
    log "Branch ${UPGRADE_BRANCH} already in sync with origin; skipping push"
  else
    log "Pushing branch ${UPGRADE_BRANCH} to origin"
    git push --force-with-lease -u origin "${UPGRADE_BRANCH}" >/dev/null 2>&1 \
      || err "failed to push ${UPGRADE_BRANCH} to origin"
  fi

  # Idempotency: if a PR is already open for this branch, leave it.
  existing_pr="$(gh pr list --repo "${repo}" --head "${UPGRADE_BRANCH}" --state open \
                   --json number --jq '.[0].number // empty' 2>/dev/null || true)"
  if [ -n "${existing_pr}" ]; then
    log "Pull request #${existing_pr} already open for ${UPGRADE_BRANCH}; not opening another"
    return 0
  fi

  body="$(build_upgrade_pr_body "${repo}" "${prev_ref}" "${prev_sha}" "${new_ref}" "${new_sha}" "${flagged_paths}")"
  log "Opening pull request"
  gh pr create \
    --base main \
    --head "${UPGRADE_BRANCH}" \
    --title "Upgrade remcc to ${new_ref} via install.sh upgrade" \
    --body "${body}" \
    || err "failed to open pull request"
}

# ----------------------------------------------------------------------------
# `init` orchestration.
# ----------------------------------------------------------------------------

cmd_init() {
  local explicit_ref=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage_init; exit 0 ;;
      --ref) shift; [ $# -gt 0 ] || err "--ref requires a value"; explicit_ref="$1"; shift ;;
      --ref=*) explicit_ref="${1#--ref=}"; shift ;;
      *) err "unknown option to init: $1" ;;
    esac
  done

  local repo ref preexisting prev_marker
  repo="$(resolve_target_repo)"
  log "Target repository: ${repo}"

  verify_prereqs "${repo}"
  verify_clean_main

  ref="$(resolve_ref "${explicit_ref}")"
  log "Using remcc ref: ${ref}"
  clone_remcc_at "${ref}"

  # Snapshot pre-existing paths BEFORE we overwrite anything, so the PR body
  # can flag potential customization collisions.
  preexisting="$(snapshot_preexisting)"

  # Resolve the previous .remcc/version contents so installed_at survives
  # re-runs. origin/main is the authoritative source; working-tree is a
  # fallback for the rare "first install on a clone whose main wasn't pushed".
  prev_marker="$(read_marker_from_origin main)"
  if [ -z "${prev_marker}" ] && [ -f .remcc/version ]; then
    prev_marker="$(cat .remcc/version 2>/dev/null || true)"
  fi

  # Run the GitHub-side bootstrap first; failures here leave the working
  # tree untouched (templates haven't been written yet).
  run_bootstrap

  install_templates "${ref}" "${prev_marker}"

  if [ -z "$(git status --porcelain -- "${TEMPLATE_PATHS[@]}")" ]; then
    log "already up to date"
    sub "no template diff vs. ${repo}@main; nothing to commit"
    exit 0
  fi

  create_init_branch
  if ! stage_and_commit "${ref}"; then
    log "already up to date"
    sub "templates matched the staged tree; no commit created"
    git checkout main >/dev/null 2>&1 || true
    git branch -D "${INIT_BRANCH}" >/dev/null 2>&1 || true
    exit 0
  fi

  push_and_open_pr "${repo}" "${preexisting}" "${ref}"
  log "Done. Review the pull request and run the smoke test from its body after merging."
}

# ----------------------------------------------------------------------------
# `upgrade` orchestration.
# ----------------------------------------------------------------------------

cmd_upgrade() {
  local explicit_ref=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage_upgrade; exit 0 ;;
      --ref) shift; [ $# -gt 0 ] || err "--ref requires a value"; explicit_ref="$1"; shift ;;
      --ref=*) explicit_ref="${1#--ref=}"; shift ;;
      *) err "unknown option to upgrade: $1" ;;
    esac
  done

  local repo ref prev_marker prev_ref prev_sha new_sha flagged_paths
  repo="$(resolve_target_repo)"
  log "Target repository: ${repo}"

  # Pre-flight: marker must exist on origin/main BEFORE any other check that
  # could mutate state. (verify_prereqs and verify_clean_main are read-only,
  # but the task order is: marker-on-main → prereqs → clean-main.)
  verify_marker_on_main "${repo}"

  verify_prereqs "${repo}"
  verify_clean_main upgrade

  ref="$(resolve_ref "${explicit_ref}")"
  log "Using remcc ref: ${ref}"
  clone_remcc_at "${ref}"

  # Snapshot pre-overwrite working-tree contents for per-path diff flagging.
  UPGRADE_SNAPSHOT_DIR="$(mktemp -d -t remcc-upgrade-snap-XXXXXX)"
  snapshot_preupgrade_paths "${UPGRADE_SNAPSHOT_DIR}"

  # Resolve the previous marker: prefer origin/remcc-upgrade (re-run on an
  # open upgrade PR) so installed_at stays stable across re-runs; fall back
  # to origin/main (the pre-flight guaranteed it exists there).
  prev_marker="$(read_marker_from_origin "${UPGRADE_BRANCH}")"
  if [ -z "${prev_marker}" ]; then
    prev_marker="$(read_marker_from_origin main)"
  fi

  install_templates "${ref}" "${prev_marker}"

  # Empty-diff short-circuit: nothing changed vs. main, so don't branch/push.
  if [ -z "$(git status --porcelain -- "${TEMPLATE_PATHS[@]}")" ]; then
    log "already up to date"
    sub "no template diff vs. ${repo}@main; nothing to commit"
    exit 0
  fi

  # Compute paths whose pre-overwrite content differed from the new template
  # (operator's tree diverged from what the previous template installed).
  flagged_paths="$(compute_flagged_paths "${UPGRADE_SNAPSHOT_DIR}")"

  prev_ref="$(printf '%s' "${prev_marker}" | jq -r '.source_ref // "unknown"' 2>/dev/null || echo unknown)"
  prev_sha="$(printf '%s' "${prev_marker}" | jq -r '.source_sha // "unknown"' 2>/dev/null || echo unknown)"
  new_sha="$(resolved_source_sha)"

  create_upgrade_branch
  if ! stage_and_commit_upgrade "${prev_ref}" "${prev_sha}" "${ref}" "${new_sha}"; then
    log "already up to date"
    sub "templates matched the staged tree; no commit created"
    git checkout main >/dev/null 2>&1 || true
    git branch -D "${UPGRADE_BRANCH}" >/dev/null 2>&1 || true
    exit 0
  fi

  push_and_open_upgrade_pr "${repo}" "${prev_ref}" "${prev_sha}" "${ref}" "${new_sha}" "${flagged_paths}"
  log "Done. Review the upgrade PR; the refreshed workflow takes effect on the next apply run after merge."
}

# ----------------------------------------------------------------------------
# `reconfigure` orchestration.
# ----------------------------------------------------------------------------

cmd_reconfigure() {
  local explicit_ref=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage_reconfigure; exit 0 ;;
      --ref) shift; [ $# -gt 0 ] || err "--ref requires a value"; explicit_ref="$1"; shift ;;
      --ref=*) explicit_ref="${1#--ref=}"; shift ;;
      *) err "unknown option to reconfigure: $1" ;;
    esac
  done

  local repo ref
  repo="$(resolve_target_repo)"
  log "Target repository: ${repo}"

  # Marker-on-main must come first so an un-adopted target is rejected
  # before any other GitHub or filesystem work runs.
  verify_marker_on_main "${repo}"

  verify_prereqs "${repo}"
  verify_clean_main reconfigure

  ref="$(resolve_ref "${explicit_ref}")"
  log "Using remcc ref: ${ref}"
  clone_remcc_at "${ref}"

  # Run ONLY the GitHub-side bootstrap. No working-tree writes, no
  # version-marker update, no branch, no PR — that's the contract.
  run_bootstrap

  log "Done. Reconfigure complete for ${repo}."
}

# ----------------------------------------------------------------------------
# Dispatch.
# ----------------------------------------------------------------------------

main() {
  case "${1:-}" in
    ''|-h|--help|help) usage_root; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    upgrade) shift; cmd_upgrade "$@" ;;
    reconfigure) shift; cmd_reconfigure "$@" ;;
    *) printf 'unknown subcommand: %s\n\n' "$1" >&2; usage_root >&2; exit 1 ;;
  esac
}

# Dispatch only when executed directly. Sourcing the script (e.g. from
# scripts/test-resolve-pm.sh) loads the functions without running a subcommand.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
