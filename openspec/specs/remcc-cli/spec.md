# remcc-cli Specification

## Purpose

Defines the contract for `install.sh`, the curl-invocable entry point
that automates remcc adoption in a target repository. The CLI verifies
prerequisites, fetches templates at a pinned ref, runs the
`gh-bootstrap.sh` script, writes template-managed files, records a
version marker, and opens a pull request — all without triggering an
apply-workflow run. Companion capabilities `repo-adoption` and
`apply-workflow` define what is adopted and what the workflow does
once installed.

## Requirements

### Requirement: Installer is invokable over curl in a single command

The repo SHALL ship `install.sh` at its root such that
`bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/<ref>/install.sh) <subcommand>`
executes the named subcommand against the current working directory's
target repository. The script SHALL also work under the `curl … |
bash -s -- <subcommand>` shape; interactive prompts inside the
script SHALL read from `/dev/tty` so the piped form does not hang.

#### Scenario: Adopter invokes install.sh init via process substitution

- **WHEN** the adopter runs
  `bash <(curl -fsSL .../install.sh) init` from a clone of a target
  repository that satisfies the prerequisites
- **THEN** the script exits zero after completing its steps
- **AND** `bash <(curl -fsSL .../install.sh) --help` lists `init`
  as an available subcommand

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

### Requirement: install.sh init runs the fetched bootstrap script

`install.sh init` SHALL resolve a remcc ref (default: latest release tag on `premeq/remcc`; overridable via `--ref <tag-or-sha>`), shallow-clone the repo at that ref into a tempdir, and invoke the `templates/gh-bootstrap.sh` from that clone against the resolved target repository. The invocation SHALL be idempotent: re-running `install.sh init` SHALL NOT produce diffs in branch protection, rulesets, secrets, or repository variables managed by the bootstrap script. The command SHALL pass `ANTHROPIC_API_KEY`, `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, `REMCC_APP_SLUG`, `OPSX_APPLY_MODEL`, and `OPSX_APPLY_EFFORT` from its environment to the bootstrap subprocess; `install.sh --help` (and `install.sh init --help`) SHALL document each as bootstrap-consumed environment passthrough.

#### Scenario: Re-running init is a bootstrap no-op

- **WHEN** the adopter runs `install.sh init` twice in succession
  in the same target repo
- **THEN** the second invocation produces no diffs in any
  GitHub-side configuration the bootstrap script manages, and exits
  zero

#### Scenario: install.sh init documents App credentials in --help

- **WHEN** the operator runs `install.sh init --help`
- **THEN** the output names `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, and `REMCC_APP_SLUG` as environment-variable passthroughs consumed by `gh-bootstrap.sh`
- **AND** the output does not name `WORKFLOW_PAT` (it is no longer used)

### Requirement: install.sh init writes template-managed files

`install.sh init` SHALL write the following files in the target
repo's working tree: `.github/workflows/opsx-apply.yml`,
`.claude/settings.json`, `openspec/config.yaml`, and
`.remcc/version`. If any of these paths already exist, the script
SHALL overwrite them without prompting. The expectation is that the
operator reviews the resulting diff in the pull request and
re-applies any local customizations there.

#### Scenario: Pre-existing file is overwritten and surfaces in the PR diff

- **WHEN** the adopter runs `install.sh init` in a repo whose
  `.claude/settings.json` already contains operator-authored
  configuration
- **THEN** the file is overwritten with the template's contents,
  the change is visible in the resulting pull request's diff, and
  no interactive prompt is presented during the run

### Requirement: install.sh init writes a version marker

`install.sh init` SHALL write `.remcc/version` recording at minimum the
resolved remcc source ref (tag or commit SHA the templates were fetched
from). The file format SHALL be machine-parseable (JSON). The marker
SHALL include an `installed_at` field recording the timestamp at which
the adopter first installed remcc; on re-runs of `install.sh init`
against a target that already has `.remcc/version` committed on
`origin/main`, the `installed_at` value SHALL be preserved (read from
`origin/main:.remcc/version`, not from the working tree, since the
init branch is rebuilt from `main` before the marker is written). The
marker enables the `upgrade` subcommand to identify the installed
version and preserve adoption history.

#### Scenario: Marker records the source ref

- **WHEN** the adopter runs `install.sh init` against a `premeq/remcc`
  release tagged `v0.2.0` (the default ref resolution)
- **THEN** `.remcc/version` in the target repo contains a parseable
  JSON object whose `source_ref` field is `v0.2.0`

#### Scenario: Re-running init preserves installed_at from origin/main

- **WHEN** the adopter runs `install.sh init` twice against the same
  target repo and the first run's PR was merged to `main` between
  invocations
- **THEN** the second invocation's `.remcc/version` contains the same
  `installed_at` value as the first run's marker on `origin/main`

### Requirement: install.sh init opens a pull request

`install.sh init` SHALL commit the written template files to a
branch (default: `remcc-init`) and SHALL open a pull request against
`main` after the template-write and bootstrap steps complete. The
PR body SHALL list every file written and SHALL explicitly flag any
path that existed in the target repo before the run, identifying it
as a potential customization collision the operator should verify
in the diff.

#### Scenario: PR is opened and identifies pre-existing files

- **WHEN** `install.sh init` runs successfully in a repo that had a
  pre-existing `.claude/settings.json`
- **THEN** a pull request exists from `remcc-init` to `main` on the
  target repo, with a body listing every file written and flagging
  `.claude/settings.json` as a pre-existing file requiring diff
  review

### Requirement: install.sh init does not trigger an apply run

`install.sh init` SHALL NOT push to a `change/**` branch, SHALL NOT
push any commit with a subject starting `@change-apply`, and SHALL
NOT cause an `opsx-apply` workflow run on the target repo. The
operator runs a smoke test manually after merging the PR; the PR
body SHALL include a copy-pasteable smoke-test one-liner.

#### Scenario: No apply run is triggered during init

- **WHEN** `install.sh init` completes against a freshly configured
  target repo
- **THEN** no `opsx-apply` workflow run exists on the target repo
  as a consequence of the invocation, and the PR body includes a
  smoke-test command the operator can run after merging

### Requirement: install.sh exposes an upgrade subcommand

The `install.sh` CLI SHALL expose an `upgrade` subcommand in addition
to `init`. `install.sh --help` and the no-argument invocation SHALL
list both subcommands. `install.sh upgrade --help` SHALL describe the
subcommand's flow, the `--ref <tag-or-sha>` option, and the requirement
that the target repository has previously been adopted (must contain
`.remcc/version` on `origin/main`).

#### Scenario: Help lists upgrade alongside init

- **WHEN** the operator runs `bash <(curl -fsSL .../install.sh) --help`
- **THEN** the output lists both `init` and `upgrade` as available
  subcommands
- **AND** `bash <(curl -fsSL .../install.sh) upgrade --help` prints
  upgrade-specific behaviour and the `--ref` option

### Requirement: install.sh upgrade refuses targets without a version marker

`install.sh upgrade` SHALL verify that `.remcc/version` exists on the
target repository's `origin/main` branch before mutating anything. If
the marker is absent, the command SHALL exit non-zero with a message
identifying the missing marker and pointing the operator at
`install.sh init`, and SHALL NOT have issued any `gh api` mutation or
filesystem write.

#### Scenario: Upgrade refuses an un-adopted target

- **WHEN** the operator runs `install.sh upgrade` in a repository that
  has never been adopted via `install.sh init` (no `.remcc/version` on
  `origin/main`)
- **THEN** the command exits non-zero, the error message names the
  missing marker file and directs the operator to `install.sh init`,
  and no GitHub-side configuration or working-tree file has been
  changed

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

### Requirement: install.sh upgrade does not re-run gh-bootstrap.sh

`install.sh upgrade` SHALL NOT invoke `templates/gh-bootstrap.sh`. The
subcommand SHALL NOT change branch protection, rulesets, secrets,
repository variables, or any other GitHub-side configuration. Upgrade
operates exclusively on template-managed files inside the target
repo's working tree.

#### Scenario: Upgrade leaves GitHub configuration untouched

- **WHEN** the operator runs `install.sh upgrade` against an adopted
  target
- **THEN** snapshots of branch protection, rulesets, repository secrets,
  and repository variables taken before and after the run are
  bit-identical

### Requirement: install.sh upgrade resolves a ref and refreshes template files

`install.sh upgrade` SHALL resolve a remcc ref (default: latest release
tag on `premeq/remcc`; overridable via `--ref <tag-or-sha>`),
shallow-clone the repo at that ref into a tempdir, and overwrite the
template-managed files (`.github/workflows/opsx-apply.yml`,
`.claude/settings.json`, `openspec/config.yaml`, `.remcc/version`) in
the target repo's working tree using the templates from that clone.
The tempdir SHALL be cleaned up on exit.

#### Scenario: Upgrade refreshes all template-managed files at the new ref

- **WHEN** an adopted repo currently records `source_ref: v0.1.1` in
  its `.remcc/version`
- **AND** the operator runs `install.sh upgrade --ref v0.2.0`
- **THEN** every template-managed file in the working tree matches the
  contents of `templates/...` at `v0.2.0`
- **AND** `.remcc/version` records `source_ref: v0.2.0` and the
  corresponding `source_sha`

### Requirement: install.sh upgrade preserves installed_at across upgrades

`install.sh upgrade` SHALL preserve the `installed_at` value from the
previously committed `.remcc/version` when writing the upgraded marker.
The previous marker SHALL be read from
`origin/remcc-upgrade:.remcc/version` if that branch exists on the
remote, falling back to `origin/main:.remcc/version`. The previous
marker SHALL NOT be read from the working tree, because the upgrade
branch is rebuilt from `main` before the marker is written. If the
previous marker is malformed JSON or lacks an `installed_at` field,
the upgraded marker's `installed_at` SHALL default to the current UTC
timestamp.

#### Scenario: installed_at is preserved on upgrade

- **WHEN** an adopted repo's `origin/main:.remcc/version` records
  `installed_at: 2026-04-01T10:00:00Z`
- **AND** the operator runs `install.sh upgrade --ref v0.2.0` and
  merges the resulting PR
- **THEN** the merged `.remcc/version` on `main` still records
  `installed_at: 2026-04-01T10:00:00Z`

#### Scenario: Re-running upgrade keeps installed_at stable

- **WHEN** the operator runs `install.sh upgrade --ref v0.2.0` twice
  in succession against the same adopted target, the first
  invocation having opened a PR that is still open on the
  `remcc-upgrade` branch
- **THEN** the second invocation's marker has the same `installed_at`
  value as the first invocation's marker (read back from
  `origin/remcc-upgrade:.remcc/version`)

### Requirement: install.sh upgrade opens a single reused branch pull request

`install.sh upgrade` SHALL commit the refreshed template-managed files
to a single reused branch (default: `remcc-upgrade`) and SHALL open a
pull request against `main` after the templates are written. If a
pull request from `remcc-upgrade` to `main` is already open on the
target repository, the command SHALL update the branch tip via
force-with-lease push and SHALL NOT open a duplicate pull request.

Before the push, `install.sh upgrade` SHALL prune the local tracking
ref for the upgrade branch if it no longer exists on the remote, so
that a previously-merged-and-deleted `remcc-upgrade` branch does not
cause the force-with-lease push to abort with `stale info`.
Concretely, the pre-push fetch SHALL use `--prune` (or equivalent
ref-state cleanup) scoped to the upgrade branch, so the lease is
computed against the remote's current state rather than against a
stale local tracking ref.

The PR title SHALL identify the upgrade as a remcc upgrade and name
the new ref. The PR body SHALL include: a source line stating both
the previous ref/sha and the new ref/sha; the list of files written;
a per-path flag for any path whose pre-upgrade working-tree content
differed from the new template (potential customization collision);
and a pointer that the upgraded workflow takes effect on the next
apply run after merge. The PR body SHALL NOT include a smoke-test
one-liner (the operator already ran one at `init`).

#### Scenario: PR is opened against main from remcc-upgrade

- **WHEN** the operator runs `install.sh upgrade --ref v0.2.0` against
  an adopted target whose previous source ref was `v0.1.1`
- **THEN** a pull request exists from `remcc-upgrade` to `main` on the
  target repo, the title identifies the upgrade, and the body's
  source line reads `v0.1.1 (<old_sha>) → v0.2.0 (<new_sha>)`
- **AND** the body lists each of the four template-managed files
- **AND** the body does not include a smoke-test one-liner

#### Scenario: Re-running upgrade does not open a duplicate PR

- **WHEN** the operator runs `install.sh upgrade` while a PR from
  `remcc-upgrade` to `main` is already open on the target
- **THEN** no second pull request is opened
- **AND** the existing PR's head branch is updated to the new tip
  via force-with-lease push, if the new templates differ from the
  branch's previous tip

#### Scenario: Second upgrade after merge-and-delete succeeds

- **WHEN** a previous `install.sh upgrade` run opened a PR that the
  operator merged
- **AND** the target repository's default post-merge cleanup deleted
  the remote `remcc-upgrade` branch
- **AND** the operator's local clone still holds
  `refs/remotes/origin/remcc-upgrade` pointing at the merged commit
- **AND** the operator runs `install.sh upgrade --ref <new>` against
  the same target with a new release
- **THEN** the upgrade pushes the new tip to a fresh `remcc-upgrade`
  branch on origin and opens a new pull request, without the
  force-with-lease push aborting on a stale local tracking ref

### Requirement: install.sh upgrade short-circuits when no diff exists

`install.sh upgrade` SHALL skip branch creation, commit, push, and PR
opening when the refreshed template-managed files match what is
already committed on `origin/main`. In that case the command SHALL
print an `already up to date` message and exit zero. No GitHub-side
state SHALL be mutated.

#### Scenario: Upgrade at the same ref is a no-op

- **WHEN** the operator runs `install.sh upgrade --ref v0.1.1` against
  an adopted target whose `origin/main:.remcc/version` already records
  `source_ref: v0.1.1`
- **THEN** the command prints `already up to date` and exits zero
- **AND** no commit, push, or pull request creation has occurred

### Requirement: install.sh upgrade does not trigger an apply run

`install.sh upgrade` SHALL NOT push to a `change/**` branch, SHALL
NOT push any commit with a subject starting `@change-apply`, and
SHALL NOT cause an `opsx-apply` workflow run on the target repo as
a consequence of its execution.

#### Scenario: No apply run is triggered during upgrade

- **WHEN** `install.sh upgrade` completes against an adopted target
- **THEN** no `opsx-apply` workflow run on the target repo has been
  triggered by the upgrade invocation

### Requirement: install.sh exposes a reconfigure subcommand

The `install.sh` CLI SHALL expose a `reconfigure` subcommand in addition to `init` and `upgrade`. `install.sh --help` and the no-argument invocation SHALL list all three subcommands. `install.sh reconfigure --help` SHALL describe the subcommand's flow, the `--ref <tag-or-sha>` option, and the requirement that the target repository has previously been adopted (must contain `.remcc/version` on `origin/main`).

#### Scenario: Help lists reconfigure alongside init and upgrade

- **WHEN** the operator runs `bash <(curl -fsSL .../install.sh) --help`
- **THEN** the output lists `init`, `upgrade`, and `reconfigure` as available subcommands
- **AND** `bash <(curl -fsSL .../install.sh) reconfigure --help` prints reconfigure-specific behaviour and the `--ref` option

### Requirement: install.sh reconfigure refuses targets without a version marker

`install.sh reconfigure` SHALL verify that `.remcc/version` exists on the target repository's `origin/main` branch before mutating anything. If the marker is absent, the command SHALL exit non-zero with a message identifying the missing marker and pointing the operator at `install.sh init`, and SHALL NOT have issued any `gh api` mutation or filesystem write.

#### Scenario: Reconfigure refuses an un-adopted target

- **WHEN** the operator runs `install.sh reconfigure` in a repository that has never been adopted via `install.sh init` (no `.remcc/version` on `origin/main`)
- **THEN** the command exits non-zero, the error message names the missing marker file and directs the operator to `install.sh init`, and no GitHub-side configuration has been changed

### Requirement: install.sh reconfigure verifies prerequisites before mutating

`install.sh reconfigure` SHALL run the same prerequisite verifier as `init` and `upgrade` (admin on target, `main` exists, OpenSpec initialised, `.claude/` present, a supported package manager **resolvable** by the same rules as `init` — `packageManager` authoritative when present; absent-field fallback resolves a lone bun lockfile to bun, fails a lone `pnpm-lock.yaml` with a pnpm-specific message, and fails the both-lockfiles case as ambiguous — and the required local tools, where the package-manager tool required is the resolved one) before making any change to the target repository's filesystem or GitHub configuration. On verification failure, the command SHALL exit non-zero with a message identifying the unmet prerequisite and SHALL NOT have applied any partial change.

#### Scenario: pnpm repo that dropped its packageManager field is rejected before mutation

- **WHEN** the operator runs `install.sh reconfigure` in an adopted repo with `pnpm-lock.yaml` whose `package.json` no longer contains a `packageManager` field
- **THEN** the command exits non-zero, the error states that pnpm-managed repos must declare `packageManager: pnpm@<version>`, and no GitHub-side configuration has been changed

#### Scenario: bun repo without a packageManager field still reconfigures

- **WHEN** the operator runs `install.sh reconfigure` in an adopted repo that has `bun.lock` (or `bun.lockb`), no `pnpm-lock.yaml`, and no `packageManager` field
- **THEN** the package manager resolves to bun, the prerequisite verifier passes, and the reconfigure proceeds (other prerequisites permitting)

### Requirement: install.sh reconfigure runs only the fetched bootstrap script

`install.sh reconfigure` SHALL resolve a remcc ref (default: latest release tag on `premeq/remcc`; overridable via `--ref <tag-or-sha>`), shallow-clone the repo at that ref into a tempdir, and invoke the cloned `templates/gh-bootstrap.sh` against the resolved target repository. `reconfigure` SHALL NOT touch the working tree, SHALL NOT write `.remcc/version`, SHALL NOT create a branch, and SHALL NOT open a pull request. The tempdir SHALL be cleaned up on exit. Re-running `reconfigure` with the same inputs SHALL be idempotent (no diffs in any GitHub-side configuration the bootstrap manages).

#### Scenario: Reconfigure applies only bootstrap-managed config

- **WHEN** the operator runs `install.sh reconfigure --ref v0.3.0` against an adopted target
- **THEN** the cloned `gh-bootstrap.sh` runs to completion
- **AND** the working tree of the target repo is unchanged after the run
- **AND** no `remcc-init` or `remcc-upgrade` branch was created locally or pushed
- **AND** no pull request was opened

#### Scenario: Re-running reconfigure is a bootstrap no-op

- **WHEN** the operator runs `install.sh reconfigure` twice in succession with the same inputs in the same target repo
- **THEN** the second invocation produces no diffs in any GitHub-side configuration the bootstrap script manages, and exits zero

### Requirement: install.sh reconfigure does not trigger an apply run

`install.sh reconfigure` SHALL NOT push to a `change/**` branch, SHALL NOT push any commit with a subject starting `@change-apply`, and SHALL NOT cause an `opsx-apply` workflow run on the target repo as a consequence of its execution.

#### Scenario: No apply run is triggered during reconfigure

- **WHEN** `install.sh reconfigure` completes against an adopted target
- **THEN** no `opsx-apply` workflow run on the target repo has been triggered by the invocation
