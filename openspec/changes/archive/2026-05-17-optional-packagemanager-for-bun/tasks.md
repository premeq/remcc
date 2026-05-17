## 1. Resolver fallback in install.sh

- [x] 1.1 In `resolve_package_manager`: keep the present-`packageManager` path unchanged (`pnpm@`→pnpm, `bun@`→bun, `npm@`/`yarn@`/other→existing error). Add the absent-field branch: glob the root for `bun.lock`/`bun.lockb` and `pnpm-lock.yaml` and decide — lone bun lockfile (no `pnpm-lock.yaml`) → echo `bun`; lone `pnpm-lock.yaml` → error with a pnpm-specific message ("pnpm-managed repos must declare packageManager: pnpm@<version> — pnpm/action-setup has no version default; bun may omit it"); both lockfiles → ambiguous error; neither → existing missing-field error. Keep "no package.json"/"unparseable JSON" errors as-is.
- [x] 1.2 Verify `verify_package_manager_lockfile` still composes correctly: when bun was resolved via the absent-field fallback the bun-lockfile assertion is trivially satisfied; when `packageManager` was present, behaviour is unchanged. Adjust the success `sub` line so it distinguishes "package manager: bun (resolved from bun.lock, packageManager unset)" from the declared case.
- [x] 1.3 Confirm `verify_prereqs` ordering still holds "no partial mutation on failure" — resolution + lockfile assertion remain read-only and run before any mutation; `init`/`upgrade`/`reconfigure` inherit the new behaviour through the shared verifier with no per-subcommand edits (re-verify the three call sites).

## 2. Workflow template (opsx-apply.yml)

- [x] 2.1 In the "Resolve package manager" step, mirror install.sh's precedence exactly: `jq` the field; on empty, `test -f bun.lock`/`bun.lockb`/`pnpm-lock.yaml` and apply the same lone-bun→bun, lone-pnpm→pnpm-specific-fail, both→ambiguous-fail, neither→fail decision, with byte-identical error strings to install.sh. Resolve before any Claude Code step.
- [x] 2.2 Confirm the guarded setup steps need no change: `oven-sh/setup-bun@v2` with no version input installs latest Bun on the absent-field bun path; `pnpm/action-setup@v4` is only reached when `packageManager: pnpm@` is present (pnpm-without-field already failed at 2.1). `${{ steps.pm.outputs.name }} install --frozen-lockfile` unchanged.

## 3. Resolver unit-test harness

- [x] 3.1 Extend `scripts/test-resolve-pm.sh` truth table: bun lockfile + no `packageManager` → resolves bun ok; `bun.lockb` + no field → bun ok; lone `pnpm-lock.yaml` + no field → fails with the pnpm-specific message; both lockfiles + no field → fails as ambiguous; preserve all existing cases (present-field, npm@, yarn@, missing-everything, declared-without-lockfile). Pure-local, no network; assert exit codes + message substrings.

## 4. Docs

- [x] 4.1 `docs/SETUP.md`: prereq rows 5/5b — state `packageManager` required for pnpm, optional for bun when a bun lockfile is committed; update verification commands; **remove** the inaccurate "the action errors at runtime [without packageManager]" rationale and replace with the pnpm-only reason.
- [x] 4.2 `README.md` / `CONTRIBUTING.md`: adjust any prereq prose that implies `packageManager` is universally required so it reflects "required for pnpm, optional for bun" (limitations line "pnpm- or bun-managed" stays correct — no requirement-level change there).
- [x] 4.3 Sweep the tree (excl. `openspec/`) for any other text asserting `packageManager` is mandatory for bun or that setup-bun errors without it; reconcile hits.

## 5. Verification

- [x] 5.1 `openspec validate optional-packagemanager-for-bun --strict` passes.
- [x] 5.2 Run `scripts/test-resolve-pm.sh` locally — all cases (existing + new) pass.
- [x] 5.3 `bash -n` + `shellcheck -S warning` clean on `install.sh` and `scripts/*.sh`.
- [x] 5.4 Validate the rendered workflow parses (`actionlint` if available, else `python3 yaml.safe_load`) and manually confirm the resolve step's fallback precedence + identical error strings vs install.sh, and that resolution still precedes the Claude Code step.
- [x] 5.5 Confirm smoke scripts need no change: they seed `packageManager: ${SMOKE_PM_SPEC}` (present-field path, unchanged). The absent-field branches are covered deterministically by the unit harness (3.1); duplicating a no-field live E2E is over-testing per the prior change's lean-test rationale — note this explicitly rather than adding a fixture.
