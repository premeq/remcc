## MODIFIED Requirements

### Requirement: install.sh init verifies prerequisites before mutating

`install.sh init` SHALL verify the prerequisites enumerated in
`repo-adoption` (admin on target, `main` exists, OpenSpec
initialised, `.claude/` present, a supported package manager
declared and its matching root lockfile present — `pnpm@<version>`
with `pnpm-lock.yaml`, or `bun@<version>` with `bun.lock` or
`bun.lockb` — and the required local tools, where the package-manager
tool required is the one the repo declares) before making any change
to the target repository's GitHub configuration, filesystem, or
remote refs. On verification failure, the command SHALL exit
non-zero with a message identifying the unmet prerequisite and SHALL
NOT have applied any partial change.

#### Scenario: Missing lockfile for the declared manager is detected before mutation

- **WHEN** the adopter runs `install.sh init` in a repo whose
  `package.json` declares `pnpm@<version>` but lacks `pnpm-lock.yaml`
  at the root (or declares `bun@<version>` but lacks both `bun.lock`
  and `bun.lockb`)
- **THEN** the command exits non-zero, prints which prerequisite
  failed and the expected lockfile for the declared manager, and
  `gh api` calls that would mutate GitHub configuration have not
  been issued

#### Scenario: bun-managed repo passes prerequisite verification

- **WHEN** the adopter runs `install.sh init` in a repo that
  declares `packageManager: bun@<version>`, commits `bun.lock` (or
  `bun.lockb`) at the root, and has `bun` available locally
- **THEN** the package-manager prerequisite passes and the command
  proceeds (other prerequisites permitting) without requiring pnpm

### Requirement: install.sh upgrade verifies prerequisites before mutating

`install.sh upgrade` SHALL run the same prerequisite verifier as
`install.sh init` (admin on target, `main` exists, OpenSpec
initialised, `.claude/` present, a supported package manager
declared and its matching root lockfile present — `pnpm@<version>`
with `pnpm-lock.yaml`, or `bun@<version>` with `bun.lock` or
`bun.lockb` — and the required local tools, where the package-manager
tool required is the one the repo declares) before making any change
to the target repository's filesystem or remote refs. On
verification failure, the command SHALL exit non-zero with a message
identifying the unmet prerequisite and SHALL NOT have applied any
partial change.

#### Scenario: Missing prerequisite is detected before mutation

- **WHEN** the operator runs `install.sh upgrade` in an adopted repo
  whose `package.json` no longer contains a `packageManager` field
- **THEN** the command exits non-zero, the error names the unmet
  prerequisite and the supported managers, and no GitHub-side
  configuration or template file has been rewritten

### Requirement: install.sh reconfigure verifies prerequisites before mutating

`install.sh reconfigure` SHALL run the same prerequisite verifier as `init` and `upgrade` (admin on target, `main` exists, OpenSpec initialised, `.claude/` present, a supported package manager declared and its matching root lockfile present — `pnpm@<version>` with `pnpm-lock.yaml`, or `bun@<version>` with `bun.lock` or `bun.lockb` — and the required local tools, where the package-manager tool required is the one the repo declares) before making any change to the target repository's filesystem or GitHub configuration. On verification failure, the command SHALL exit non-zero with a message identifying the unmet prerequisite and SHALL NOT have applied any partial change.

#### Scenario: Missing prerequisite is detected before mutation

- **WHEN** the operator runs `install.sh reconfigure` in an adopted repo whose `package.json` no longer contains a `packageManager` field
- **THEN** the command exits non-zero, the error names the unmet prerequisite and the supported managers, and no GitHub-side configuration has been changed
