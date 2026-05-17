## 1. Package-manager resolver in install.sh

- [x] 1.1 Add `resolve_package_manager` helper: parse `.packageManager` from root `package.json` via `jq`, match `^(pnpm|bun)@`, echo `pnpm`|`bun`; error (no output, non-zero) on absent/`npm@`/`yarn@`/unparseable, with a message naming the supported managers
- [x] 1.2 Add lockfile assertion: given the resolved manager, require `pnpm-lock.yaml` for pnpm, or `bun.lock` OR `bun.lockb` for bun; error names the declared manager and the expected lockfile(s)
- [x] 1.3 Rewrite `verify_prereqs`: replace hardcoded `require_local_tool pnpm` + `[ -f pnpm-lock.yaml ]` + `verify_package_manager_field` with resolve → `require_local_tool <pm>` → lockfile assertion; keep the "no partial mutation on failure" ordering
- [x] 1.4 Update `sub`/log lines so success prints the detected manager (e.g. "package manager: bun@<v> (bun.lock present)")
- [x] 1.5 Confirm `init`/`upgrade`/`reconfigure` need no per-subcommand edits (they call the shared verifier) — verify by reading the three entrypoints (all call `verify_prereqs "${repo}"`: init L766, upgrade L834, reconfigure L906)

## 2. Workflow template (opsx-apply.yml)

- [x] 2.1 Add a "Resolve package manager" step early in the job: read `package.json#packageManager`, set `package_manager` job/step output (`pnpm`|`bun`), fail non-zero before any Claude Code step if unresolved, mirroring install.sh's message (step `id: pm`, output `name`)
- [x] 2.2 Replace the unconditional `Setup pnpm` step with two guarded steps: `pnpm/action-setup@v4` (`if:` resolved == pnpm) and `oven-sh/setup-bun@v2` (`if:` resolved == bun), each resolving version from `packageManager`
- [x] 2.3 Replace `pnpm install --frozen-lockfile` with `${PM} install --frozen-lockfile` using the resolved manager (`${{ steps.pm.outputs.name }} install --frozen-lockfile`)
- [x] 2.4 Keep Node.js setup and CLI-install steps unchanged; verify step ordering still satisfies "runtime prepared before apply" (order: resolve → node → pnpm/bun → CLIs → deps → … → apply; all before Claude Code)

## 3. Resolver unit-test harness

- [x] 3.1 Add `scripts/test-resolve-pm.sh`: source the resolver, drive a temp-dir truth table — pnpm+lock ok, bun+`bun.lock` ok, bun+`bun.lockb` ok, `bun@` without bun lockfile fails, `pnpm@` without `pnpm-lock.yaml` fails, `npm@` fails, missing field fails — assert exit codes + messages, no network (added source-guard to install.sh so it is sourceable; 14/14 cases pass)
- [x] 3.2 Make `test-resolve-pm.sh` discoverable/runnable for contributors. ADAPTED: this repo has no CI workflow and no aggregate lint/smoke runner (it is a docs-and-templates kit with standalone smoke scripts). Rather than invent a full CI pipeline (scope creep vs. "do not over-test"), document the resolver test + smoke scripts under a "Local checks" section in CONTRIBUTING.md as the pre-PR gate.

## 4. Smoke scripts cover both managers

  ADAPTED (see design D6): parameterize the three smoke scripts by `SMOKE_PM`
  (default `pnpm`) instead of duplicating each into a pnpm+bun double run.
  Duplication would double every live GitHub E2E for signal the resolver unit
  harness already covers — over-testing. Default stays `pnpm` so existing
  behavior/live runs are unchanged; `SMOKE_PM=bun` exercises the bun path.
- [x] 4.1 `scripts/smoke-init.sh`: seed `packageManager: ${SMOKE_PM}@<v>` and run the matching real install (`pnpm`/`bun`) to produce a valid lockfile; default `pnpm` unchanged
- [x] 4.2 `scripts/smoke-upgrade.sh`: same `SMOKE_PM` parameterization
- [x] 4.3 `scripts/smoke-reconfigure.sh`: same `SMOKE_PM` parameterization
- [x] 4.4 Update the smoke scripts' tool preflight (`for t in gh jq pnpm git curl`) so the package-manager tool required is the selected `SMOKE_PM` only, not unconditionally pnpm

## 5. Docs

- [x] 5.1 `README.md`: limitations line → "pnpm- or bun-managed JavaScript repos only (npm/yarn unsupported)"; prereq bullet updated
- [x] 5.2 `docs/SETUP.md`: prereq rows 5/5b/6 accept pnpm OR bun with new verification commands; pnpm-only callout rewritten; workflow-internals row covers both setup actions + resolve step; upgrade-behavior + cold-cache prose generalized
- [x] 5.3 `CONTRIBUTING.md`: scope line → "pnpm- or bun-managed"; added a "Local checks" section (folds in task 3.2 — resolver test + SMOKE_PM smoke as the pre-PR gate)
- [x] 5.4 Swept the tree for residual pnpm-only prose (excl. `openspec/`); reconciled the one hit (`docs/SETUP.md:200`). Remaining `pnpm` mentions are intentional bun-aware code / the conditional `Setup pnpm` step

## 6. Verification

- [x] 6.1 `openspec validate support-bun-package-manager --strict` passes
- [x] 6.2 Run `scripts/test-resolve-pm.sh` locally — 14/14 truth-table cases pass
- [x] 6.3 Smoke scripts: `bash -n` + `shellcheck -S warning` clean on all three; the only new behavior (lockfile seeding) verified in isolated temp dirs — `pnpm install` → `pnpm-lock.yaml`; `bun add left-pad@1.3.0` → `bun.lock`; `bun install --frozen-lockfile` consumes it. NOT RUN: the full live-GitHub E2E (creates throwaway repos, needs ANTHROPIC_API_KEY + App creds + network) — outward-facing/destructive, out of scope to auto-execute; run manually per CONTRIBUTING with `SMOKE_PM=bun`
- [x] 6.4 ADAPTED: `actionlint` unavailable (its `brew install` was denied in this environment). Fallback applied — `python3 yaml.safe_load` parses the rendered workflow cleanly + manual structural review of the new `id: pm` step, the two `if:`-guarded setup steps, and the `${{ steps.pm.outputs.name }} install --frozen-lockfile` wiring (all correct; resolve step precedes Claude Code)
