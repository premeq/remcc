# repo-adoption Specification

## Purpose

Defines the contract a target repository's adoption of remcc must
satisfy: the prerequisites the operator confirms, the templates this
repo ships (workflow, Claude settings, bootstrap script), the
GitHub-side configuration the bootstrap script applies (idempotently),
the documentation set, the smoke-test procedure, and the
reversibility guarantee. The companion capability `apply-workflow`
defines what the workflow itself does once installed.
## Requirements
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

### Requirement: Workflow template provided

The repo SHALL ship a copy-pasteable GitHub Actions workflow file at
`templates/workflows/opsx-apply.yml` that satisfies the
`apply-workflow` capability with no edits required for a minimal
adoption.

#### Scenario: Adopter copies the workflow file unchanged

- **WHEN** the operator copies `templates/workflows/opsx-apply.yml`
  to the target repo's `.github/workflows/opsx-apply.yml`
- **THEN** no further edits to the workflow file are required for
  the apply flow to function

### Requirement: Claude settings template provided

The repo SHALL ship a `templates/claude/settings.json` file
containing minimal, runner-safe defaults intended to be merged into
the target repo's `.claude/settings.json`.

#### Scenario: Adopter merges settings into existing .claude/

- **WHEN** the operator merges `templates/claude/settings.json`
  into a pre-existing `.claude/settings.json` in the target repo
- **THEN** the merged file contains the union of both, with no
  conflicting permissive defaults overriding existing local
  restrictions

### Requirement: GitHub bootstrap script provided

The repo SHALL ship `templates/gh-bootstrap.sh`, an idempotent POSIX
shell script run from inside a target repository that uses `gh api`
to apply the GitHub-side configuration the safety contract requires.

#### Scenario: Bootstrap script run twice is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` twice in succession
  in the same target repo
- **THEN** the second invocation produces no diffs in repo
  configuration and exits zero

### Requirement: Bootstrap enables secret scanning and push protection when supported

`gh-bootstrap.sh` SHALL enable GitHub secret scanning and secret
push protection on the target repository **when the feature is
available** for that repository's visibility and plan. Public
repositories receive the feature for free; private repositories
require GitHub Advanced Security (organization-level paid feature).
On private repositories without GHAS, the script SHALL emit a clear
warning identifying the limitation, SHALL NOT fail, and SHALL
continue with the remaining bootstrap steps. SECURITY.md documents
the resulting reliance on Actions log redaction as the only
secret-leak protection in that configuration.

#### Scenario: Public or GHAS-enabled target gets secret scanning

- **WHEN** the operator runs `gh-bootstrap.sh` against a repository
  where secret scanning is available
- **AND** a subsequent commit contains a token matching a known
  secret pattern
- **THEN** the push is rejected by secret push protection

#### Scenario: Private user-owned target produces a documented warning

- **WHEN** the operator runs `gh-bootstrap.sh` against a private
  repository where secret scanning is unavailable
- **THEN** the script prints a warning that secret scanning is
  unavailable and that the only remaining secret-leak protection is
  Actions log redaction, and continues with subsequent steps

### Requirement: Bootstrap installs ANTHROPIC_API_KEY secret

`gh-bootstrap.sh` SHALL prompt the operator for an Anthropic API
key (or accept it via environment variable) and install it as the
repository secret `ANTHROPIC_API_KEY`. The script SHALL NOT echo
the key value to stdout or commit it to disk.

#### Scenario: Operator provides key interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without
  `ANTHROPIC_API_KEY` in the environment
- **THEN** the script prompts for the key with input hidden, and
  uploads it as the repository secret

### Requirement: Documentation set is sufficient for unaided adoption

The repo SHALL include `docs/SETUP.md`, `docs/SECURITY.md`, and `docs/COSTS.md`. SETUP.md SHALL contain a complete adoption checklist runnable without external context, including a "Create and install the remcc GitHub App" section that documents the App's required permissions (`Contents: write`, `Pull requests: write`, `Workflows: write`, `Metadata: read`), where to create the App, how to generate and download the private-key PEM, and how to install the App on the target repository. SECURITY.md SHALL document the two-layer safety model, enumerate the controls each layer relies on, explicitly call out which controls are unavailable on user-owned and on private-without-GHAS targets, document the GitHub App as the bot's identity (including credential-rotation procedure for the private key and the resulting blast-radius implications), together with the substitutions that take their place. COSTS.md SHALL document Anthropic admin console budget configuration and GitHub Actions minute usage.

#### Scenario: A second adopter completes setup using docs alone

- **WHEN** an operator who has not previously interacted with remcc
  follows `docs/SETUP.md` end to end on a fresh repository
- **THEN** the adoption completes successfully and the smoke test
  passes without questions back to the remcc maintainer

#### Scenario: SETUP.md walks through GitHub App creation

- **WHEN** an operator who has never created a GitHub App opens `docs/SETUP.md`
- **THEN** they find a step-by-step section that names every form field they need to fill in (App name, homepage URL, webhook off, the four required permissions), how to generate a private-key PEM, and how to install the App on a single repository

#### Scenario: SECURITY.md documents App credential rotation

- **WHEN** an operator opens `docs/SECURITY.md` looking for how to rotate the App private key
- **THEN** they find a procedure (regenerate key in App settings → re-run `install.sh reconfigure` → revoke old key) and a paragraph describing the blast radius if the key is exfiltrated

### Requirement: Smoke test procedure documented

`docs/SETUP.md` SHALL include a smoke-test procedure that verifies
adoption succeeded. The procedure SHALL involve pushing a trivial
`change/<test-name>` branch and observing the workflow run, the
PR creation, and the agent's behaviour on a no-op change.

#### Scenario: Smoke test exercises the full path

- **WHEN** the operator follows the smoke-test procedure after
  adoption
- **THEN** they observe (a) workflow trigger, (b) Claude Code run
  to completion, (c) `openspec validate` pass, (d) PR creation, in
  that order, all without manual intervention

### Requirement: Bootstrap installs OPSX_APPLY_MODEL and OPSX_APPLY_EFFORT variables

`gh-bootstrap.sh` SHALL prompt the operator for `OPSX_APPLY_MODEL`
and `OPSX_APPLY_EFFORT` values (or accept them via environment
variables of the same name) and write them as repository variables
via `gh variable set`. The prompts SHALL accept empty input; an
empty value SHALL NOT write a variable, allowing the workflow's
baked-in default for that knob to take effect. Running the script
twice with the same inputs SHALL be a no-op on the resulting
repository configuration.

#### Scenario: Operator supplies values interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without the
  `OPSX_APPLY_MODEL` or `OPSX_APPLY_EFFORT` environment variables
  set
- **AND** answers the prompts with `opus` and `high`
- **THEN** the script sets `OPSX_APPLY_MODEL=opus` and
  `OPSX_APPLY_EFFORT=high` as repository variables

#### Scenario: Operator skips a knob by leaving the prompt empty

- **WHEN** the operator runs `gh-bootstrap.sh` and answers the
  `OPSX_APPLY_MODEL` prompt with empty input
- **THEN** the script does not write the `OPSX_APPLY_MODEL`
  repository variable, leaving the workflow's baked-in default
  in effect

#### Scenario: Re-running the script with the same answers is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` twice in succession
  with the same answers for the model/effort prompts
- **THEN** the second invocation produces no diffs in the
  repository's variables and exits zero

### Requirement: SETUP.md documents model and effort configuration

`docs/SETUP.md` SHALL document the `OPSX_APPLY_MODEL` and
`OPSX_APPLY_EFFORT` repository variables, the workflow's baked-in
defaults, and the override precedence (`workflow_dispatch` input >
commit trailer > repository variable > baked-in default). The
section SHALL include the exact commit-trailer syntax
(`Opsx-Model: <value>`, `Opsx-Effort: <value>`) and a worked
example of overriding from a manual dispatch.

#### Scenario: Adopter learns how to set defaults from SETUP.md

- **WHEN** an operator follows `docs/SETUP.md` end to end
- **THEN** they encounter a section explaining the two
  configuration variables, their baked-in defaults, and how to
  override per run via dispatch or commit trailer

### Requirement: COSTS.md covers model and effort cost guidance

`docs/COSTS.md` SHALL include guidance on choosing `model` and
`effort` for cost/quality trade-offs, and SHALL note that the
resolved values appear in the PR body so the operator can audit
run cost decisions after the fact.

#### Scenario: Adopter consults COSTS.md before raising defaults

- **WHEN** an operator opens `docs/COSTS.md` before changing
  `OPSX_APPLY_MODEL` to a more expensive model
- **THEN** they find guidance on the cost implications of model
  and effort choices, plus a pointer to the PR body as the source
  of truth for what each run actually used

### Requirement: Adoption is reversible

The repo SHALL document how to remove remcc from a target
repository, covering removal of the workflow file, removal of the
ruleset and secret via `gh api`, and any other adoption-time
configuration.

#### Scenario: Operator removes adoption cleanly

- **WHEN** the operator follows the documented removal procedure
- **THEN** no remcc-specific configuration remains on the target
  repository (no workflow file, no push ruleset, no secret),
  while the repo's own files outside `.github/` are untouched

### Requirement: Automated install path is provided

The repo SHALL provide an automated install path via the curl-piped
`install.sh init` invocation (defined in `remcc-cli`) and an automated
update path via `install.sh upgrade`. `docs/SETUP.md` SHALL present
`install.sh init` as the primary adoption flow and SHALL preserve the
existing manual checklist as a fallback for operators who cannot or
will not pipe a remote script to bash. `docs/SETUP.md` SHALL also
document `install.sh upgrade` as the primary update flow once a repo
has been adopted, including the curl one-liner and the `--ref`
override. The automated paths SHALL replace the manual steps for
prerequisite verification, template-file copying, bootstrap-script
invocation (init only), and PR opening.

#### Scenario: Operator adopts via the automated path

- **WHEN** the operator runs the documented `install.sh init`
  one-liner in a target repository that satisfies the prerequisites
- **THEN** the adoption completes by opening a single pull request
  for the operator to review, and the operator was not required to
  copy any template files by hand

#### Scenario: Operator upgrades via the automated path

- **WHEN** the operator runs the documented `install.sh upgrade`
  one-liner in a target repository that was previously adopted via
  `install.sh init`
- **THEN** the upgrade completes by opening a single pull request
  refreshing every template-managed file at the new remcc ref, and
  the operator was not required to copy any template files by hand

#### Scenario: Manual fallback remains documented

- **WHEN** an operator who will not pipe a remote script to bash
  reads `docs/SETUP.md`
- **THEN** the document contains the manual step-by-step checklist
  (template copies, bootstrap invocation, smoke test) as an
  explicit fallback path

### Requirement: Adopted repos contain a remcc version marker

Repositories adopted via `install.sh init` SHALL contain a
`.remcc/version` file recording the remcc ref the templates were
sourced from. The marker SHALL be committed to the repository as
part of the adoption pull request and SHALL persist on `main` after
merge. Its presence enables future update-delivery commands (out of
scope here) to identify the installed version.

#### Scenario: Marker is present after adoption

- **WHEN** the operator completes `install.sh init` and merges the
  resulting pull request
- **THEN** the target repository's `main` branch contains
  `.remcc/version`

### Requirement: Version marker preserves installed_at across upgrades

The `.remcc/version` marker in an adopted repository SHALL retain its
`installed_at` value across `install.sh upgrade` invocations. The
`installed_at` field records the date the operator first adopted
remcc; it SHALL NOT be re-stamped to the upgrade date on subsequent
upgrades. The mechanism by which the value is preserved is specified
in `remcc-cli`.

#### Scenario: installed_at survives an upgrade-and-merge cycle

- **WHEN** an adopted repo's `main` branch records
  `installed_at: 2026-04-01T10:00:00Z` in `.remcc/version`
- **AND** the operator runs `install.sh upgrade` and merges the
  resulting pull request
- **THEN** `main` still records `installed_at: 2026-04-01T10:00:00Z`
  in `.remcc/version` after the merge

### Requirement: Bootstrap installs REMCC_APP_ID and REMCC_APP_PRIVATE_KEY secrets

`gh-bootstrap.sh` SHALL prompt the operator for (or read from environment variables of the same name) the GitHub App ID and PEM-encoded private key associated with the operator's remcc GitHub App, and install them as the repository secrets `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY`. The PEM is multi-line; the script SHALL accept it via `/dev/tty` or env without mangling newlines, and SHALL upload it to GitHub via `gh secret set` with the body piped on stdin (so multi-line content is preserved). The script SHALL NOT echo either value to stdout and SHALL NOT commit them to disk. The `--uninstall` path SHALL delete both secrets (it does not delete the App or revoke its credentials on GitHub).

#### Scenario: Operator provides App credentials interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without `REMCC_APP_ID` or `REMCC_APP_PRIVATE_KEY` in the environment
- **THEN** the script prompts for each value with input hidden, uploads both as repository secrets, and the prompts name the required GitHub App permissions (`Contents: write`, `Pull requests: write`, `Workflows: write`, `Metadata: read`)

#### Scenario: Multi-line PEM is preserved on upload

- **WHEN** the operator supplies a multi-line PEM via the `REMCC_APP_PRIVATE_KEY` environment variable
- **AND** runs `gh-bootstrap.sh`
- **THEN** the resulting repository secret's value matches the supplied PEM byte-for-byte (including all newlines), as verifiable by minting an installation token in a subsequent workflow run

#### Scenario: Uninstall removes both secrets

- **WHEN** the operator runs `gh-bootstrap.sh --uninstall` on a target where the App secrets have been installed
- **THEN** the repository secrets `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY` are deleted and the script exits zero

### Requirement: Bootstrap installs REMCC_APP_SLUG repository variable

`gh-bootstrap.sh` SHALL prompt the operator for (or read from the environment variable of the same name) the GitHub App's slug (the lower-cased, hyphen-separated identifier visible in the App's URL on GitHub), and write it as the repository variable `REMCC_APP_SLUG` via `gh variable set`. An empty value SHALL be a hard error (the workflow needs the slug to construct the bot's git identity). The `--uninstall` path SHALL delete the variable.

#### Scenario: Operator supplies slug interactively

- **WHEN** the operator runs `gh-bootstrap.sh` without `REMCC_APP_SLUG` in the environment
- **THEN** the script prompts for the value (input visible — the slug is not secret), writes it as the repository variable, and exits zero

#### Scenario: Empty slug is rejected

- **WHEN** the operator runs `gh-bootstrap.sh` and responds to the slug prompt with empty input (or supplies an empty `REMCC_APP_SLUG` environment variable)
- **THEN** the script exits non-zero with a message identifying the empty slug, and no other bootstrap step that has not already run is executed

#### Scenario: Uninstall removes the variable

- **WHEN** the operator runs `gh-bootstrap.sh --uninstall` on a target where `REMCC_APP_SLUG` has been installed
- **THEN** the repository variable is deleted and the script exits zero

### Requirement: Bootstrap removes legacy WORKFLOW_PAT secret when the App secrets are installed

`gh-bootstrap.sh` SHALL delete any pre-existing `WORKFLOW_PAT` repository secret AFTER it has successfully written both `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY`. If either App secret fails to install, the legacy `WORKFLOW_PAT` SHALL NOT be deleted (so a failed migration leaves the legacy workflow in a working state). The removal step SHALL be idempotent: re-running bootstrap when `WORKFLOW_PAT` has already been removed SHALL be a no-op.

#### Scenario: Legacy PAT is removed during migration

- **WHEN** the operator runs `gh-bootstrap.sh` on a target that has the legacy `WORKFLOW_PAT` installed
- **AND** the operator supplies valid `REMCC_APP_ID`, `REMCC_APP_PRIVATE_KEY`, and `REMCC_APP_SLUG` values
- **THEN** the App secrets and slug variable are installed first
- **AND** the legacy `WORKFLOW_PAT` secret is then deleted from the repository
- **AND** the script exits zero

#### Scenario: App secret installation failure preserves legacy PAT

- **WHEN** the operator runs `gh-bootstrap.sh` on a target with legacy `WORKFLOW_PAT` installed
- **AND** the App private key supplied is empty or invalid (so secret install fails)
- **THEN** the script exits non-zero
- **AND** the legacy `WORKFLOW_PAT` secret is still present on the target

#### Scenario: Re-run when WORKFLOW_PAT already gone is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` on a target where `WORKFLOW_PAT` is already absent
- **THEN** the WORKFLOW_PAT-removal step prints a clear "already absent" message and exits zero, with no API calls that mutate state

### Requirement: Bootstrap configures main-branch approval ruleset

`gh-bootstrap.sh` SHALL configure a single repository **branch
ruleset** targeting the repository's default branch **only** —
via the GitHub ruleset condition `ref_name.include: ["~DEFAULT_BRANCH"]`
with `exclude: []` — whose rule set is **exactly** the
following, no more and no less:

- A `pull_request` rule with `required_approving_review_count: 1`
  (requires a pull request and at least one approval to merge
  into the default branch).
- A `non_fast_forward` rule (blocks force-push to the default
  branch).
- `bypass_actors`: the `RepositoryRole` admin (role id `5`) with
  `bypass_mode: always`, so the operator (admin) can still merge
  their own changes and perform emergency operations.

The ruleset SHALL NOT include a `deletion` rule, a
`creation` rule, status-check gating, signed-commit enforcement,
linear-history requirement, or any other rule beyond the two
listed above. Deletion of the default branch is intentionally
not blocked by this ruleset.

The ruleset SHALL be named `remcc: require approval on main` so
the new control is identifiable in the GitHub UI. The ruleset
SHALL apply uniformly to user-owned and organization-owned
repositories — no conditional branching on ownership type.

The bootstrap SHALL NOT modify, delete, or inspect any
pre-existing GitHub-side controls on the target repository,
including (but not limited to) branch protection on `main`
configured via the `branches/main/protection` endpoint and
rulesets named `remcc: restrict bot to change branches` or
`remcc: block bot edits under .github`. The new ruleset is
installed alongside whatever exists; legacy controls remain
untouched until the operator removes them by hand.

#### Scenario: Direct push to default branch is rejected after bootstrap on a new adopter

- **WHEN** the operator runs `gh-bootstrap.sh` on a fresh repo
  that has no pre-existing remcc-managed controls
- **AND** subsequently attempts `git push origin main` from a
  local checkout with new commits as a non-admin actor
- **THEN** GitHub rejects the push citing the ruleset

#### Scenario: PR merge to default branch requires an approval

- **WHEN** the workflow opens a PR targeting the default branch
  and no reviewer has approved it
- **THEN** the merge button is disabled / the merge API call is
  rejected citing the missing approval, regardless of repo
  ownership type

#### Scenario: Force-push to the default branch is rejected

- **WHEN** any actor (including admin via a token without bypass)
  attempts a force-push to the default branch on a repo
  configured by `gh-bootstrap.sh`
- **THEN** GitHub rejects the push citing the ruleset's
  `non_fast_forward` rule

#### Scenario: Deletion of the default branch is not blocked by this ruleset

- **WHEN** an actor with delete permission deletes the default
  branch on a repo whose only remcc-managed control is the new
  ruleset
- **THEN** the deletion succeeds (the ruleset does not include a
  `deletion` rule — out of scope for this change)

#### Scenario: Ruleset does not apply to non-default branches

- **WHEN** a non-admin actor pushes commits to any branch other
  than the default branch (e.g. `change/foo`, `feature/bar`) in a
  repo configured by `gh-bootstrap.sh`
- **THEN** the push is accepted; the approval ruleset does not
  block it (the ruleset's `ref_name.include` is `["~DEFAULT_BRANCH"]`,
  so only the default branch is gated)

#### Scenario: User-owned and org-owned new adopters get identical configuration

- **WHEN** the operator runs `gh-bootstrap.sh` against a
  user-owned repository with no pre-existing remcc-managed
  controls
- **AND** the operator runs `gh-bootstrap.sh` against an
  organization-owned repository with no pre-existing
  remcc-managed controls
- **THEN** both repositories end up with the same `remcc: require
  approval on main` ruleset and no other remcc-managed rulesets

#### Scenario: Re-running bootstrap on an already-bootstrapped new adopter is a no-op

- **WHEN** the operator runs `gh-bootstrap.sh` on a repo that
  already has the `remcc: require approval on main` ruleset
- **THEN** the idempotency smoke test passes with no diffs

#### Scenario: Bootstrap does not mutate legacy controls on an old adopter

- **WHEN** the operator runs the updated `gh-bootstrap.sh` on a
  repo that was bootstrapped under the prior three-layer model
  and still has branch protection on `main` plus the two legacy
  rulesets
- **THEN** the script creates the new `remcc: require approval
  on main` ruleset
- **AND** branch protection on `main` is left unchanged
- **AND** the ruleset `remcc: restrict bot to change branches`
  is left unchanged
- **AND** the ruleset `remcc: block bot edits under .github` is
  left unchanged

#### Scenario: Uninstall removes only what this version manages

- **WHEN** the operator runs `gh-bootstrap.sh --uninstall` on a
  repo that has the new ruleset and (optionally) leftover legacy
  controls from a prior bootstrap
- **THEN** the new ruleset `remcc: require approval on main` is
  removed
- **AND** any pre-existing branch protection on `main` or legacy
  rulesets are left in place (the script does not touch them)

