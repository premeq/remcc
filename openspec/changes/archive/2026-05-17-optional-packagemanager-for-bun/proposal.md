## Why

bun projects routinely ship without a `packageManager` field — bun does
not use Corepack, so there is no idiomatic reason to set it. remcc's
resolver nonetheless hard-rejects them ("package.json is missing the
'packageManager' field"), turning away otherwise-valid bun adopters
(reported against `foster-systems/renew-1`). The requirement's stated
justification — that the setup action "errors at runtime" without the
field — holds for `pnpm/action-setup@v4` (no version default) but is
**false** for `oven-sh/setup-bun@v2`, which installs the latest Bun
when no version source is present. The constraint is stricter than the
bun toolchain actually needs, and the docs assert a reason that is not
true on the bun path.

## What Changes

- **`packageManager` becomes optional on the bun path.** The resolver
  keeps `package.json#packageManager` as the primary signal; when it is
  **absent**, it falls back to lockfile-based detection: a lone
  `bun.lock`/`bun.lockb` (no `pnpm-lock.yaml`) resolves to bun, and the
  runner lets `oven-sh/setup-bun@v2` default to the latest Bun.
- **pnpm path is unchanged.** A pnpm repo without `packageManager`
  still fails, because `pnpm/action-setup@v4` has no version default and
  genuinely needs the field; the error now says so explicitly instead of
  citing a generic "missing field".
- **Ambiguity fails closed.** `packageManager` absent **and** both a
  pnpm and a bun lockfile present → error (cannot disambiguate). `npm@`,
  `yarn@`, unparseable, and "no package.json" keep failing as today.
- **When `packageManager` is present** (`pnpm@`/`bun@`): behaviour is
  byte-for-byte unchanged — fully backward compatible.
- **Docs corrected.** `docs/SETUP.md` / `repo-adoption` stop claiming
  `oven-sh/setup-bun@v2` errors without the field; the prerequisite is
  restated as "`packageManager` required for pnpm; optional for bun when
  a bun lockfile is committed".

No BREAKING change: every repo that resolves today resolves identically.

## Capabilities

### New Capabilities
<!-- none — this relaxes an existing constraint -->

### Modified Capabilities
- `remcc-cli`: the prerequisite verifier shared by
  `init`/`upgrade`/`reconfigure` no longer requires `packageManager`
  when the repo is unambiguously bun (lone bun lockfile, no
  `packageManager`); pnpm still requires it, with a pnpm-specific
  message; the both-lockfiles-no-field case is a new rejection.
- `apply-workflow`: "Workflow prepares runtime before apply" — the
  runner's package-manager resolution gains the same absent-field
  lockfile fallback; an absent `packageManager` is no longer an
  unconditional pre-apply failure when a lone bun lockfile is present.
- `repo-adoption`: "Adoption prerequisites documented" — the
  `packageManager` field is required for pnpm but optional for bun when
  a `bun.lock`/`bun.lockb` is committed; the inaccurate
  setup-bun-errors-without-it rationale is removed.

## Impact

- Code: `install.sh` (`resolve_package_manager` + the
  `verify_prereqs`/lockfile-assertion ordering — resolution must now
  consult lockfiles to disambiguate when `packageManager` is absent),
  `templates/workflows/opsx-apply.yml` (the "Resolve package manager"
  step gains the identical fallback so verifier and runner stay in
  lockstep).
- Tests: `scripts/test-resolve-pm.sh` gains truth-table cases — bun
  lockfile + no field → bun ok; pnpm lockfile + no field → fail with
  the pnpm-needs-field message; both lockfiles + no field → ambiguous
  fail; existing cases unchanged.
- Docs: `docs/SETUP.md` (prereq rows 5/5b + corrected rationale),
  `README.md`, `CONTRIBUTING.md` as needed.
- Risk surface: re-opens the prior change's D1 ("`packageManager` is the
  single source of truth", chosen to avoid trusting a stale foreign
  lockfile). The fallback is bun-only, triggers **only** when
  `packageManager` is absent, and rejects the both-lockfiles ambiguity —
  so a stale foreign lockfile cannot silently mask the declared manager.
  design.md must work this tradeoff explicitly.
