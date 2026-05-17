## MODIFIED Requirements

### Requirement: Adoption prerequisites documented

The repo SHALL document the prerequisites a target repository MUST
satisfy before adopting remcc. Prerequisites SHALL include: an
initialised OpenSpec project, a `.claude/` directory committed to
the repo, an existing `main` branch, a GitHub remote to which the
operator has admin access, and a JavaScript project managed by
**either pnpm or bun**. The package-manager prerequisite SHALL be
satisfied as follows:

- **pnpm:** `package.json` at the repo root declares a
  `packageManager` field whose value starts with `pnpm@<version>`,
  AND `pnpm-lock.yaml` is committed at the root. The `packageManager`
  field is **required** for pnpm because `pnpm/action-setup@v4` has
  no explicit `version:` input and no built-in default; it resolves
  the pnpm version solely from that field and fails on the runner
  without it.
- **bun:** `bun.lock` **or** `bun.lockb` is committed at the root. A
  `packageManager` field starting with `bun@<version>` is
  **optional**: when present it is authoritative; when absent the
  package manager is resolved from the lone bun lockfile and
  `oven-sh/setup-bun@v2` installs the latest Bun (it has no version
  source and does not require one). The earlier documentation claim
  that the bun setup action "errors at runtime" without
  `packageManager` is incorrect and SHALL NOT be stated.

When `packageManager` is absent, resolution SHALL fail closed if it
is ambiguous: a lone `pnpm-lock.yaml` (no bun lockfile) SHALL be
rejected with a pnpm-specific message that `packageManager:
pnpm@<version>` is required; the presence of **both** a pnpm and a
bun lockfile SHALL be rejected as ambiguous; neither lockfile SHALL
be rejected naming the supported managers.

npm-, yarn-, and unmanaged repositories remain out of scope: the
workflow template installs workspace dependencies via
`<pm> install --frozen-lockfile` and only pnpm and bun are
supported. A present `packageManager` declaration is authoritative;
the lockfile must match the declared manager.

#### Scenario: Operator can verify prerequisites before starting

- **WHEN** the operator opens `docs/SETUP.md`
- **THEN** they find a checklist of prerequisites at the top of the
  document with a verification command for each item, including that
  pnpm-managed repos declare `packageManager: pnpm@<version>` with
  `pnpm-lock.yaml`, and that bun-managed repos commit
  `bun.lock`/`bun.lockb` with `packageManager: bun@<version>` noted
  as optional

#### Scenario: bun-managed adopter is supported

- **WHEN** an operator whose repo declares `packageManager: bun@<version>`
  and commits a `bun.lock` (or `bun.lockb`) at the root reads
  `docs/SETUP.md`
- **THEN** the prerequisites section confirms bun-managed repos are
  supported and does not turn the operator away

#### Scenario: bun adopter without a packageManager field is supported

- **WHEN** an operator whose repo commits `bun.lock` (or `bun.lockb`)
  at the root, has no `pnpm-lock.yaml`, and has no `packageManager`
  field reads `docs/SETUP.md` and runs `install.sh init`
- **THEN** the prerequisites section states `packageManager` is
  optional for bun, and `install.sh init` resolves the manager to
  bun and passes the package-manager prerequisite

#### Scenario: npm/yarn adopter is told remcc is not for them yet

- **WHEN** an operator whose repo uses npm or yarn (no pnpm or bun
  lockfile and no `pnpm@`/`bun@` `packageManager` declaration) reads
  `docs/SETUP.md`
- **THEN** the prerequisites section explicitly states that remcc
  supports pnpm- or bun-managed repos only, and points the operator
  at an issue or future change for other package managers

#### Scenario: pnpm repo without a packageManager field is caught before mutation

- **WHEN** the operator runs `install.sh init` in a repo that has
  `pnpm-lock.yaml`, no bun lockfile, and no `packageManager` field
- **THEN** the command exits non-zero with a message stating that
  pnpm-managed repos must declare `packageManager: pnpm@<version>`,
  and no GitHub-side configuration or file write has been issued

#### Scenario: Absent packageManager with both lockfiles is rejected as ambiguous

- **WHEN** the operator runs `install.sh init` in a repo with no
  `packageManager` field that has **both** a bun lockfile and
  `pnpm-lock.yaml` at the root
- **THEN** the command exits non-zero with a message that the
  package manager is ambiguous and `packageManager` must be declared,
  and no GitHub-side configuration or file write has been issued

#### Scenario: Non-pnpm/bun packageManager value is caught before mutation

- **WHEN** the operator runs `install.sh init` in a repo whose
  `package.json` declares a `packageManager` value that does not
  start with `pnpm@` or `bun@`
- **THEN** the command exits non-zero with a message identifying the
  invalid field and naming the supported managers, and no
  GitHub-side configuration or file write has been issued

#### Scenario: Declared manager without its matching lockfile is rejected

- **WHEN** the operator runs `install.sh init` in a repo that
  declares `packageManager: bun@<version>` but has no `bun.lock` or
  `bun.lockb` at the root (or declares `pnpm@<version>` without
  `pnpm-lock.yaml`)
- **THEN** the command exits non-zero with a message naming the
  declared manager and the expected lockfile, and no GitHub-side
  configuration or file write has been issued
