## Why

remcc currently hard-requires a pnpm-managed target repo: the prereq verifier
rejects anything without `pnpm-lock.yaml` + `packageManager: pnpm@<version>`,
and the workflow template unconditionally runs `pnpm install --frozen-lockfile`.
bun-managed repositories cannot adopt remcc **at all** today. The driver is
adopter coverage — not a bun-vs-pnpm merit judgement. remcc should detect the
target repo's declared package manager and match it, rather than imposing one.

## What Changes

- **Detect-and-match package manager.** A single resolver derives the manager
  from `package.json#packageManager` (`pnpm@<v>` or `bun@<v>`), corroborated by
  the matching root lockfile (`pnpm-lock.yaml`, or `bun.lock` / `bun.lockb`).
  pnpm remains the default; bun becomes a first-class peer.
- **`install.sh` prereq verifier** accepts pnpm **or** bun: requires the matching
  lockfile at root and a `packageManager` field whose value starts with `pnpm@`
  or `bun@`. The local-tool check requires whichever manager the repo declares
  (not both). Shared by `init`, `upgrade`, and `reconfigure`.
- **`opsx-apply.yml` workflow template** conditionally sets up the declared
  manager — `pnpm/action-setup@v4` for pnpm, `oven-sh/setup-bun@v2` for bun —
  and runs the matching `<pm> install --frozen-lockfile`. Selection is derived
  on the runner from `package.json#packageManager`, no adopter edits required.
- **Smoke scripts** parameterized to seed and exercise both a pnpm fixture and
  a bun fixture (one extra fixture per script, not a full matrix).
- **Docs/specs** (`repo-adoption`, `remcc-cli`, `project-readme`, README,
  SETUP.md) restated as "pnpm- or bun-managed" instead of "pnpm-only", including
  the prerequisite checklist, verification commands, and the limitations section.

No BREAKING change: every currently-supported pnpm repo keeps working unchanged.

## Capabilities

### New Capabilities
<!-- none — this generalizes existing behavior -->

### Modified Capabilities
- `repo-adoption`: adoption prerequisites change from "pnpm-managed only" to
  "pnpm- or bun-managed"; the "non-pnpm adopter is turned away" scenario is
  replaced by a bun-accepted scenario; smoke-test procedure covers both managers.
- `remcc-cli`: the prerequisite verifier shared by `init`/`upgrade`/`reconfigure`
  accepts a bun lockfile + `packageManager: bun@<version>` as an alternative to
  the pnpm pair.
- `apply-workflow`: "Workflow prepares runtime before apply" is made explicit
  that the runtime-setup and dependency-install steps select the package manager
  declared by the target repo (pnpm or bun) rather than assuming pnpm.
- `project-readme`: the honest-limitations requirement no longer lists
  "pnpm-managed JavaScript repos only"; it states pnpm- or bun-managed.

## Impact

- Code: `install.sh` (prereq verifier + a new package-manager resolver helper),
  `templates/workflows/opsx-apply.yml` (conditional setup + install steps),
  `scripts/smoke-init.sh`, `scripts/smoke-upgrade.sh`, `scripts/smoke-reconfigure.sh`.
- Docs: `README.md`, `docs/SETUP.md`, `CONTRIBUTING.md`.
- Dependencies (CI only): adds `oven-sh/setup-bun@v2` as a workflow action used
  on the bun path; pnpm path unchanged. No new local-tool requirement for pnpm
  adopters.
- Risk surface: lockfile/`packageManager` mismatch (e.g. `bun@` declared but
  only `pnpm-lock.yaml` present) must fail closed with a clear message.
