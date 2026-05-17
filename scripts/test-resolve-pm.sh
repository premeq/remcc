#!/usr/bin/env bash
#
# Unit truth-table for the package-manager resolver in install.sh
# (`resolve_package_manager` + `verify_package_manager_lockfile`).
#
# Pure-local: no network, no GitHub, no real package installs. Sources
# install.sh for its functions (the BASH_SOURCE guard there prevents the
# subcommand dispatcher from running on source).
#
# Usage: scripts/test-resolve-pm.sh
# Exit:  0 if every case passes, 1 otherwise.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/install.sh"

# install.sh sets `set -euo pipefail`; relax it here so the negative cases
# (which intentionally exit non-zero in a subshell) don't abort the driver.
set +e +u
set +o pipefail

ERRFILE="$(mktemp -t remcc-pmtest-err-XXXXXX)"
trap 'rm -f "${ERRFILE}"' EXIT

PASS=0
FAIL=0
ok()  { printf '  PASS  %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

case_dir() { mktemp -d -t remcc-pmtest-XXXXXX; }

# Write a package.json declaring the given packageManager value into <dir>.
pkg() {
  printf '{\n  "name": "t",\n  "private": true,\n  "packageManager": "%s"\n}\n' \
    "$1" > "$2/package.json"
}

assert_resolves() {
  # assert_resolves <dir> <expected-pm>
  local dir="$1" want="$2" got rc
  got="$(cd "$dir" && resolve_package_manager 2>"${ERRFILE}")"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    ok "resolve -> ${want}"
  else
    bad "resolve expected '${want}' got '${got}' rc=${rc} ($(cat "${ERRFILE}"))"
  fi
}

assert_resolve_fails() {
  # assert_resolve_fails <dir> <stderr-substring>
  local dir="$1" needle="$2" got rc
  got="$(cd "$dir" && resolve_package_manager 2>"${ERRFILE}")"; rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$got" ] && grep -qi -- "$needle" "${ERRFILE}"; then
    ok "resolve fails as expected (${needle})"
  else
    bad "resolve should fail on '${needle}': got='${got}' rc=${rc} err=$(cat "${ERRFILE}")"
  fi
}

assert_lock_ok() {
  # assert_lock_ok <dir> <pm>
  local dir="$1" pm="$2" rc
  ( cd "$dir" && verify_package_manager_lockfile "$pm" ) >/dev/null 2>"${ERRFILE}"; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "lockfile ok: ${pm}"
  else
    bad "lockfile should pass for ${pm}: $(cat "${ERRFILE}")"
  fi
}

assert_lock_fails() {
  # assert_lock_fails <dir> <pm> <stderr-substring>
  local dir="$1" pm="$2" needle="$3" rc
  ( cd "$dir" && verify_package_manager_lockfile "$pm" ) >/dev/null 2>"${ERRFILE}"; rc=$?
  if [ "$rc" -ne 0 ] && grep -qi -- "$needle" "${ERRFILE}"; then
    ok "lockfile fails as expected: ${pm} (${needle})"
  else
    bad "lockfile should fail for ${pm} (${needle}) rc=${rc} err=$(cat "${ERRFILE}")"
  fi
}

# 1. pnpm@ + pnpm-lock.yaml -> pnpm, ok
d=$(case_dir); pkg "pnpm@9.12.3" "$d"; : > "$d/pnpm-lock.yaml"
assert_resolves "$d" pnpm; assert_lock_ok "$d" pnpm; rm -rf "$d"

# 2. bun@ + bun.lock (text, bun >= 1.2) -> bun, ok
d=$(case_dir); pkg "bun@1.2.2" "$d"; : > "$d/bun.lock"
assert_resolves "$d" bun; assert_lock_ok "$d" bun; rm -rf "$d"

# 3. bun@ + bun.lockb (binary, bun < 1.2) -> bun, ok
d=$(case_dir); pkg "bun@1.1.34" "$d"; : > "$d/bun.lockb"
assert_resolves "$d" bun; assert_lock_ok "$d" bun; rm -rf "$d"

# 4. bun@ + no bun lockfile -> resolves bun, lockfile assertion fails
d=$(case_dir); pkg "bun@1.1.34" "$d"
assert_resolves "$d" bun; assert_lock_fails "$d" bun "bun.lock"; rm -rf "$d"

# 5. pnpm@ + no pnpm-lock.yaml -> resolves pnpm, lockfile assertion fails
d=$(case_dir); pkg "pnpm@9.12.3" "$d"
assert_resolves "$d" pnpm; assert_lock_fails "$d" pnpm "pnpm-lock.yaml"; rm -rf "$d"

# 6. npm@ -> resolve fails (out of scope)
d=$(case_dir); pkg "npm@10.2.0" "$d"
assert_resolve_fails "$d" "pnpm- or bun-managed"; rm -rf "$d"

# 7. yarn@ -> resolve fails (out of scope)
d=$(case_dir); pkg "yarn@4.1.0" "$d"
assert_resolve_fails "$d" "pnpm- or bun-managed"; rm -rf "$d"

# 8. missing packageManager field -> resolve fails
d=$(case_dir); printf '{ "name": "t" }\n' > "$d/package.json"
assert_resolve_fails "$d" "missing the 'packageManager'"; rm -rf "$d"

# 9. no package.json at all -> resolve fails
d=$(case_dir)
assert_resolve_fails "$d" "package.json not found"; rm -rf "$d"

echo
echo "resolve-pm: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
