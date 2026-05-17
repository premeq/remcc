## MODIFIED Requirements

### Requirement: install.sh init verifies prerequisites before mutating

`install.sh init` SHALL verify the prerequisites enumerated in
`repo-adoption` (admin on target, `main` exists, OpenSpec
initialised, `.claude/` present, a supported package manager
**resolvable**, and the required local tools, where the
package-manager tool required is the resolved one) before making any
change to the target repository's GitHub configuration, filesystem,
or remote refs. The package manager SHALL be resolved as follows:
when `package.json#packageManager` is present it is authoritative
(`pnpm@<version>` requires `pnpm-lock.yaml`; `bun@<version>` requires
`bun.lock` or `bun.lockb`); when `packageManager` is **absent**, a
lone `bun.lock`/`bun.lockb` (and no `pnpm-lock.yaml`) SHALL resolve
to bun, a lone `pnpm-lock.yaml` SHALL fail with a pnpm-specific
message stating `packageManager: pnpm@<version>` is required, and the
presence of both a pnpm and a bun lockfile SHALL fail as ambiguous.
On verification failure, the command SHALL exit non-zero with a
message identifying the unmet prerequisite and SHALL NOT have applied
any partial change.

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

#### Scenario: bun repo without a packageManager field passes via lockfile fallback

- **WHEN** the adopter runs `install.sh init` in a repo that has no
  `packageManager` field, commits `bun.lock` (or `bun.lockb`) at the
  root, has no `pnpm-lock.yaml`, and has `bun` available locally
- **THEN** the package manager resolves to bun and the prerequisite
  passes without requiring `packageManager` to be declared

#### Scenario: pnpm repo without a packageManager field is rejected with a pnpm-specific message

- **WHEN** the adopter runs `install.sh init` in a repo that has
  `pnpm-lock.yaml`, no `bun.lock`/`bun.lockb`, and no `packageManager`
  field
- **THEN** the command exits non-zero with a message stating that
  pnpm-managed repos must declare `packageManager: pnpm@<version>`
  (because `pnpm/action-setup` has no version default), and no
  GitHub-side configuration or file write has been issued

#### Scenario: Absent packageManager with both lockfiles is rejected as ambiguous

- **WHEN** the adopter runs `install.sh init` in a repo with no
  `packageManager` field that has **both** a bun lockfile and
  `pnpm-lock.yaml` at the root
- **THEN** the command exits non-zero with a message that the
  package manager is ambiguous and that `packageManager` must be
  declared to disambiguate, and no GitHub-side configuration or file
  write has been issued

### Requirement: install.sh upgrade verifies prerequisites before mutating

`install.sh upgrade` SHALL run the same prerequisite verifier as
`install.sh init` (admin on target, `main` exists, OpenSpec
initialised, `.claude/` present, a supported package manager
**resolvable** by the same rules as `init` — `packageManager`
authoritative when present; absent-field fallback resolves a lone
bun lockfile to bun, fails a lone `pnpm-lock.yaml` with a
pnpm-specific message, and fails the both-lockfiles case as
ambiguous — and the required local tools, where the package-manager
tool required is the resolved one) before making any change to the
target repository's filesystem or remote refs. On verification
failure, the command SHALL exit non-zero with a message identifying
the unmet prerequisite and SHALL NOT have applied any partial change.

#### Scenario: pnpm repo that dropped its packageManager field is rejected before mutation

- **WHEN** the operator runs `install.sh upgrade` in an adopted repo
  with `pnpm-lock.yaml` whose `package.json` no longer contains a
  `packageManager` field
- **THEN** the command exits non-zero, the error states that
  pnpm-managed repos must declare `packageManager: pnpm@<version>`,
  and no GitHub-side configuration or template file has been
  rewritten

#### Scenario: bun repo without a packageManager field still upgrades

- **WHEN** the operator runs `install.sh upgrade` in an adopted repo
  that has `bun.lock` (or `bun.lockb`), no `pnpm-lock.yaml`, and no
  `packageManager` field
- **THEN** the package manager resolves to bun, the prerequisite
  verifier passes, and the upgrade proceeds (other prerequisites
  permitting)

### Requirement: install.sh reconfigure verifies prerequisites before mutating

`install.sh reconfigure` SHALL run the same prerequisite verifier as `init` and `upgrade` (admin on target, `main` exists, OpenSpec initialised, `.claude/` present, a supported package manager **resolvable** by the same rules as `init` — `packageManager` authoritative when present; absent-field fallback resolves a lone bun lockfile to bun, fails a lone `pnpm-lock.yaml` with a pnpm-specific message, and fails the both-lockfiles case as ambiguous — and the required local tools, where the package-manager tool required is the resolved one) before making any change to the target repository's filesystem or GitHub configuration. On verification failure, the command SHALL exit non-zero with a message identifying the unmet prerequisite and SHALL NOT have applied any partial change.

#### Scenario: pnpm repo that dropped its packageManager field is rejected before mutation

- **WHEN** the operator runs `install.sh reconfigure` in an adopted repo with `pnpm-lock.yaml` whose `package.json` no longer contains a `packageManager` field
- **THEN** the command exits non-zero, the error states that pnpm-managed repos must declare `packageManager: pnpm@<version>`, and no GitHub-side configuration has been changed

#### Scenario: bun repo without a packageManager field still reconfigures

- **WHEN** the operator runs `install.sh reconfigure` in an adopted repo that has `bun.lock` (or `bun.lockb`), no `pnpm-lock.yaml`, and no `packageManager` field
- **THEN** the package manager resolves to bun, the prerequisite verifier passes, and the reconfigure proceeds (other prerequisites permitting)
