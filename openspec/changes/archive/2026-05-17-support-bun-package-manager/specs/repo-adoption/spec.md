## MODIFIED Requirements

### Requirement: Adoption prerequisites documented

The repo SHALL document the prerequisites a target repository MUST
satisfy before adopting remcc. Prerequisites SHALL include: an
initialised OpenSpec project, a `.claude/` directory committed to
the repo, an existing `main` branch, a GitHub remote to which the
operator has admin access, and a JavaScript project managed by
**either pnpm or bun**. The package-manager prerequisite SHALL be
satisfied when `package.json` at the repo root declares a
`packageManager` field whose value starts with `pnpm@<version>` or
`bun@<version>`, AND the matching root lockfile is committed:
`pnpm-lock.yaml` for pnpm, or `bun.lock` **or** `bun.lockb` for bun.
The `packageManager` field is required because the workflow's
package-manager setup step (`pnpm/action-setup@v4` or
`oven-sh/setup-bun@v2`) has no explicit `version:` input and
resolves the version from that field; without it the action errors
at runtime.

npm-, yarn-, and unmanaged repositories remain out of scope: the
workflow template installs workspace dependencies via
`<pm> install --frozen-lockfile` and only pnpm and bun are
supported. The `packageManager` declaration is authoritative; the
lockfile must match the declared manager.

#### Scenario: Operator can verify prerequisites before starting

- **WHEN** the operator opens `docs/SETUP.md`
- **THEN** they find a checklist of prerequisites at the top of the
  document with a verification command for each item, including a
  check that `package.json` declares `packageManager` as `pnpm@<version>`
  or `bun@<version>` and that the matching lockfile
  (`pnpm-lock.yaml`, or `bun.lock`/`bun.lockb`) exists at the repo root

#### Scenario: bun-managed adopter is supported

- **WHEN** an operator whose repo declares `packageManager: bun@<version>`
  and commits a `bun.lock` (or `bun.lockb`) at the root reads
  `docs/SETUP.md`
- **THEN** the prerequisites section confirms bun-managed repos are
  supported and does not turn the operator away

#### Scenario: npm/yarn adopter is told remcc is not for them yet

- **WHEN** an operator whose repo uses npm or yarn (no pnpm or bun
  `packageManager` declaration) reads `docs/SETUP.md`
- **THEN** the prerequisites section explicitly states that remcc
  supports pnpm- or bun-managed repos only, and points the operator
  at an issue or future change for other package managers

#### Scenario: Missing or non-pnpm/bun packageManager field is caught before mutation

- **WHEN** the operator runs `install.sh init` in a repo whose
  `package.json` lacks a `packageManager` field (or whose value does
  not start with `pnpm@` or `bun@`)
- **THEN** the command exits non-zero with a message identifying the
  missing/invalid field and naming the supported managers, and no
  GitHub-side configuration or file write has been issued

#### Scenario: Declared manager without its matching lockfile is rejected

- **WHEN** the operator runs `install.sh init` in a repo that
  declares `packageManager: bun@<version>` but has no `bun.lock` or
  `bun.lockb` at the root (or declares `pnpm@<version>` without
  `pnpm-lock.yaml`)
- **THEN** the command exits non-zero with a message naming the
  declared manager and the expected lockfile, and no GitHub-side
  configuration or file write has been issued
