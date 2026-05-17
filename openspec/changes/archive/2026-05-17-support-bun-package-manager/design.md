## Context

remcc is not itself a JS package; pnpm is purely the *target repo's* package
manager that the runner must install before Claude Code runs. The pnpm coupling
lives in exactly three runtime places — `install.sh` (prereq verifier), the
`templates/workflows/opsx-apply.yml` setup+install steps, and the smoke scripts —
plus prose in docs/specs. The pnpm-only constraint was always an explicit v1
scoping decision; the `repo-adoption` spec already points non-pnpm adopters at
"a future change". This is that change.

Constraints: zero behavior change for existing pnpm adopters; no new local-tool
requirement for pnpm adopters; the workflow template must select the manager on
the runner with **no adopter edits**.

## Goals / Non-Goals

**Goals:**
- Detect the target repo's package manager and match it (pnpm or bun).
- One resolver, one source of truth, shared by all `install.sh` subcommands and
  mirrored by the workflow.
- Fail closed on an ambiguous/mismatched declaration.
- Lean test coverage: one resolver unit-test harness + one extra smoke fixture
  per script; no OS/version matrix, no real-bun E2E beyond smoke.

**Non-Goals:**
- npm or yarn support (still out of scope; verifier rejects them with the same
  "pnpm or bun" message).
- Monorepo/workspace-topology differences between managers.
- Changing the apply logic, model/effort resolution, or GitHub-side controls.
- Auto-migrating a repo from one manager to another.

## Decisions

### D1: `package.json#packageManager` is the single source of truth

The resolver reads `.packageManager` from root `package.json` and matches the
`^(pnpm|bun)@` prefix. The lockfile is **corroborating, not authoritative**:
once the manager is known, the resolver requires *that manager's* lockfile at
root (`pnpm-lock.yaml`; or `bun.lock` **or** `bun.lockb` for bun). Rationale:
`packageManager` is what `pnpm/action-setup` and `oven-sh/setup-bun` themselves
key off, so making it primary keeps the verifier and the runner in lockstep and
avoids a lockfile-vs-action version drift. Alternative considered: infer purely
from lockfile presence — rejected because a repo can carry a stale foreign
lockfile, and the setup actions still need the `packageManager` field anyway.

### D2: Mismatch fails closed with a single actionable message

If `packageManager` says `bun@` but only `pnpm-lock.yaml` exists (or vice
versa), or `packageManager` is absent/`npm@`/`yarn@`, the verifier exits
non-zero **before any mutation**, naming both the declared manager and the
missing lockfile, and stating "remcc supports pnpm- or bun-managed repos". One
message path for all unmet cases — no partial application (existing guarantee
preserved).

### D3: `install.sh` gets one `resolve_package_manager` helper

A single function returns `pnpm` or `bun` (or errors). `verify_prereqs`
replaces the hardcoded `require_local_tool pnpm` + `[ -f pnpm-lock.yaml ]` +
`verify_package_manager_field` block with: resolve → `require_local_tool <pm>`
→ assert matching lockfile. `init`/`upgrade`/`reconfigure` all already call the
shared verifier, so they inherit bun support with no per-subcommand edits.

### D4: Workflow selects the manager on the runner, no adopter edits

A new early step parses `package.json#packageManager` and writes a
`package_manager` job output (`pnpm`|`bun`), erroring identically to D2 if
unresolved. Setup is two mutually-exclusive guarded steps:

- `pnpm/action-setup@v4` with `if: package_manager == 'pnpm'` (unchanged; still
  resolves its version from `packageManager`).
- `oven-sh/setup-bun@v2` with `if: package_manager == 'bun'` (resolves its
  version from the same `packageManager` field natively).

The install step runs `${PM} install --frozen-lockfile` (both managers accept
`--frozen-lockfile`). Alternative considered: a composite action — rejected as
over-engineering for two branches; inline guarded steps keep the template
copy-pasteable and diff-reviewable, which `repo-adoption` requires.

### D5: Accept both bun lockfile names

`bun.lockb` (binary, bun < 1.2 default) and `bun.lock` (text, bun ≥ 1.2
default) are both valid. The verifier accepts either; presence of *neither*
under a `bun@` declaration is the D2 failure.

### D6: Test strategy (deliberately lean)

- **Resolver unit harness:** a small `scripts/test-resolve-pm.sh` that sources
  the helper and asserts the truth table (pnpm ok, bun+`bun.lock` ok,
  bun+`bun.lockb` ok, mismatch fails, npm fails, missing field fails). Pure
  shell, no network, runs in CI and locally.
- **Smoke scripts:** the three smoke scripts are *parameterized* by a
  `SMOKE_PM` env var (default `pnpm`) rather than duplicated. The fixture
  seeds `packageManager: <SMOKE_PM>@<v>` and runs the matching real install
  (`pnpm install` / `bun install`) to produce a valid lockfile; the tool
  preflight requires only the selected manager. Default `pnpm` keeps existing
  behavior and existing live runs byte-for-byte unchanged; an operator runs
  `SMOKE_PM=bun scripts/smoke-init.sh` to exercise the bun path. Duplicating
  every live GitHub E2E with a parallel bun run was rejected as over-testing:
  the resolver unit harness already covers the pnpm-vs-bun decision logic
  deterministically; the only incremental thing a bun smoke proves is that
  `bun install --frozen-lockfile` works on a runner, which a parameterized
  opt-in run covers without doubling default cost.
- **Workflow lint:** `actionlint` (or existing yaml lint) over the rendered
  template to catch the new `if:`-guarded steps.

Explicitly **not** done: multi-OS matrix, pinning exact bun versions across the
matrix, a full end-to-end apply run against a real bun repo in CI (cost without
proportional signal — the smoke fixture already exercises verifier + install).

## Risks / Trade-offs

- **Stale/foreign lockfile present alongside the declared manager** → D1+D2
  require the *matching* lockfile and fail closed; the message names the
  expected file.
- **`oven-sh/setup-bun@v2` version-resolution behavior differs from
  `pnpm/action-setup`** → both read `packageManager`; pin the action to a major
  tag (`@v2`) and let it resolve the version from the field, mirroring how the
  pnpm path already works. If a repo declares `bun@latest`, that is the
  adopter's choice, same as `pnpm@latest` today.
- **bun not on the local box when an adopter runs `install.sh` against a bun
  repo** → `require_local_tool bun` fails with the standard missing-tool
  message; pnpm adopters are unaffected (tool required is the declared one only).
- **`bun install` deletes an empty lockfile** (verified on bun 1.3: a
  dependency-free package.json yields "No packages! Deleted empty lockfile",
  no `bun.lock`) → only affects the *artificial* smoke fixture, not real bun
  adopters (who have real dependencies and a real lockfile). Mitigation: the
  bun smoke fixture seeds one tiny zero-dependency package via
  `bun add left-pad@1.3.0`, producing a real `bun.lock` that
  `bun install --frozen-lockfile` consumes. The pnpm fixture stays dep-free
  (pnpm writes a valid lockfile regardless), so existing pnpm runs are
  byte-for-byte unchanged.
- **Doc drift (pnpm-only prose lingers)** → specs deltas + an explicit tasks
  checklist item to grep the tree for "pnpm-only"/"pnpm-managed ... only".

## Migration Plan

Additive and backward-compatible: existing pnpm repos resolve to `pnpm` and
hit the identical code path. No data migration, no marker bump. Rollback is
reverting the change; adopted repos that merged a bun-targeting workflow would
revert to the pnpm-only template (only relevant if they were bun repos, which
could not have adopted before this change anyway).
