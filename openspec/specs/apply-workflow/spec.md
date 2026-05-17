# apply-workflow Specification

## Purpose

Defines the behaviour of the GitHub Actions workflow that runs
`/opsx:apply` unattended on an ephemeral runner, on push to a
`change/**` branch when the head commit subject opts in via the
`@change-apply` trigger convention. The contract covers: the trigger
surface, the opt-in trigger commit gate, the runner-side sandbox
(permissive inside, scoped GITHUB_TOKEN outside), the runtime
preparation steps, the apply + validate sequence, the commit/push
semantics, the PR open/update flow including draft-on-failure,
concurrency partitioning between trigger and noop runs, log-artifact
upload, run timeout, and ANTHROPIC_API_KEY plumbing. It does not
cover the GitHub-side configuration that bounds the bot — see
`repo-adoption`.

## Requirements

### Requirement: Trigger on change branch push

The workflow SHALL be triggered by a push event on any branch
matching the pattern `change/**`. Whether the job actually runs
apply depends on the head commit subject (see "Apply runs only on
opt-in trigger commits") — the workflow's listener fires on every
push to a `change/**` ref, but the job is gated so that only
opt-in trigger commits cause work.

#### Scenario: Push to a change branch starts the workflow listener

- **WHEN** a commit is pushed to a branch named `change/<name>`
- **THEN** the workflow's listener fires; whether the job runs
  depends on the head commit subject convention

#### Scenario: Push to a non-change branch does not start the workflow

- **WHEN** a commit is pushed to a branch not matching `change/**`
- **THEN** the workflow does not run, regardless of the commit
  subject

### Requirement: Apply runs only on opt-in trigger commits

The workflow SHALL run the apply job only when the head commit of
the pushed `change/**` ref has a subject (the first line of its
commit message) that starts with the byte sequence `@change-apply`
(case-sensitive, byte-exact, including the leading `@`). The
character that follows the magic word — colon, parenthesis,
space, exclamation mark, newline, or end-of-string — SHALL NOT be
validated; any continuation is treated as the author's free-form
description.

Pushes whose head commit does not match this convention SHALL be
a complete no-op: the job SHALL NOT start, SHALL NOT charge
runner time, SHALL NOT post any PR comment, SHALL NOT upload any
log artifact, and SHALL NOT call any Anthropic or GitHub API
beyond what GitHub Actions itself performs to evaluate the
trigger filter.

The match SHALL be implemented as a job-level `if:` expression
(e.g. `if: startsWith(github.event.head_commit.message,
'@change-apply')`) so that GitHub Actions skips the job before
any runner is provisioned.

The text after the magic word SHALL NOT be parsed by the workflow;
it is human context only.

#### Scenario: Trigger commit with colon-separator runs apply

- **WHEN** a commit is pushed to `change/foo` and its subject is
  `@change-apply: first pass`
- **THEN** the workflow runs the apply job against change `foo`

#### Scenario: Trigger commit with parens runs apply

- **WHEN** a commit is pushed to `change/foo` and its subject is
  `@change-apply(retry with opus)`
- **THEN** the workflow runs the apply job against change `foo`

#### Scenario: Trigger commit with space-separator runs apply

- **WHEN** a commit is pushed to `change/foo` and its subject is
  `@change-apply retry after task 3`
- **THEN** the workflow runs the apply job against change `foo`

#### Scenario: Bare trigger commit runs apply

- **WHEN** a commit is pushed to `change/foo` and its subject is
  exactly `@change-apply`
- **THEN** the workflow runs the apply job against change `foo`

#### Scenario: Non-trigger commit subject is a no-op

- **WHEN** a commit is pushed to `change/foo` and its subject is
  `tweak proposal wording`
- **THEN** the workflow job is skipped before any runner is
  provisioned, no PR comment is posted, no log artifact is
  uploaded, and no Anthropic API call is made

#### Scenario: Trigger token in body but not subject is a no-op

- **WHEN** a commit is pushed to `change/foo` whose subject is
  `wip refactor` and whose body contains the line
  `@change-apply: retry`
- **THEN** the workflow job is skipped (the trigger token only
  counts at the start of the subject line)

#### Scenario: Similar-looking subjects do not trigger an apply

- **WHEN** a commit is pushed to `change/foo` with any of the
  subjects `change-apply: retry` (no `@`),
  `@change_apply: retry` (underscore),
  ` @change-apply: retry` (leading space), or
  `[@change-apply] retry`
- **THEN** the job-level `if:` evaluates false and the workflow
  job is skipped (no runner provisioned, no Anthropic spend)

#### Scenario: Case-variant subjects are blocked at the guard step

- **WHEN** a commit is pushed to `change/foo` with a subject like
  `@Change-Apply: retry` or `@CHANGE-APPLY: retry`
- **THEN** the job-level `if:` lets the run start (GitHub Actions'
  `startsWith()` is case-insensitive), the case-sensitive shell
  guard step fails the run, and all subsequent steps including
  `Run /opsx:apply` are skipped — no Anthropic spend, no PR
  comment, no log artifact written by the agent

#### Scenario: Bot's own commit subject does not trigger

- **WHEN** the workflow's "Stage and commit agent output" step
  creates a commit whose subject is `/opsx:apply foo`
- **AND** that commit is pushed to `change/foo`
- **THEN** the workflow job is skipped (the bot's subject does
  not start with `@change-apply`), implicitly preventing
  self-loops

#### Scenario: Trigger commit on a non-change branch is a no-op

- **WHEN** a commit with subject `@change-apply: retry` is
  pushed to branch `main`
- **THEN** the workflow does not run (the push trigger's
  `change/**` branch filter still applies)

### Requirement: Change name resolution

The workflow SHALL resolve the change name from the pushed branch
ref by stripping the `change/` prefix. The workflow SHALL fail
early if the resolved change name does not correspond to an
existing directory under `openspec/changes/`.

#### Scenario: Resolution from branch ref

- **WHEN** the workflow runs on a push to `change/foo`
- **THEN** the resolved change name is `foo`

#### Scenario: Missing change directory fails the workflow early

- **WHEN** the resolved change name does not correspond to a
  directory at `openspec/changes/<name>/`
- **THEN** the workflow exits non-zero before invoking Claude Code

### Requirement: Minimal token scope

The workflow's `permissions:` block SHALL grant only `contents: write`
and `pull-requests: write` to the auto-provisioned `GITHUB_TOKEN`. No
other scopes (in particular: `actions`, `secrets`, `packages`,
`deployments`, `workflows`, admin) SHALL be granted.

#### Scenario: GITHUB_TOKEN cannot modify Actions secrets

- **WHEN** the agent attempts to call the GitHub API to read or
  modify repository secrets using the workflow's `GITHUB_TOKEN`
- **THEN** the call fails due to missing permissions

### Requirement: Permissive sandbox inside the runner

The workflow SHALL invoke Claude Code with
`--dangerously-skip-permissions`, granting it full shell access
inside the runner. The workflow SHALL NOT attempt to apply tool
restrictions inside the runner.

#### Scenario: Agent runs without confirmation prompts

- **WHEN** the workflow invokes `/opsx:apply`
- **THEN** Claude Code does not pause for any tool-use confirmation
  during the run

### Requirement: Workflow prepares runtime before apply

The workflow SHALL prepare the runner before invoking the apply step
by (a) installing a Node.js version that satisfies the OpenSpec
CLI's minimum requirement (`>= 20.19` at the time of this change),
(b) installing the Claude Code CLI and the OpenSpec CLI globally so
that both `claude` and `openspec` are resolvable on `PATH`, and
(c) installing the target repository's workspace dependencies using
the resolved package manager (pnpm or bun) so that scripts the
agent may execute during apply can resolve their imports.

The workflow SHALL derive the package manager on the runner with the
same precedence as `install.sh` (no adopter edits to the template
required): if `package.json#packageManager` is present, a value
beginning `pnpm@` selects pnpm and a value beginning `bun@` selects
bun. If `packageManager` is **absent**, the workflow SHALL fall back
to lockfile detection — a lone `bun.lock`/`bun.lockb` (and no
`pnpm-lock.yaml`) selects bun; a lone `pnpm-lock.yaml` SHALL fail
before invoking Claude Code with a pnpm-specific message stating
`packageManager: pnpm@<version>` is required; the presence of both a
bun and a pnpm lockfile SHALL fail as ambiguous; neither present
SHALL fail naming the supported managers. The workflow SHALL set up
the selected manager via its canonical setup action
(`pnpm/action-setup@v4` for pnpm, `oven-sh/setup-bun@v2` for bun);
when the manager was selected from a present `packageManager` field
the setup action resolves its version from that field, and when bun
was selected via the absent-field fallback `oven-sh/setup-bun@v2`
installs the latest Bun (it has no version source and does not
require one). The workflow SHALL install dependencies with
`<pm> install --frozen-lockfile`. Any unresolved or unsupported case
SHALL exit non-zero before invoking Claude Code.

#### Scenario: Apply step finds the agent and OpenSpec CLIs on PATH

- **WHEN** the apply step starts
- **THEN** invoking `claude --version` and `openspec --version`
  both succeed with non-zero output

#### Scenario: Workspace dependencies are installed before apply

- **WHEN** the apply step starts
- **THEN** the target repository's workspace dependencies are
  installed (e.g. `node_modules` populated from a deterministic
  install command), so scripts the agent runs during apply can
  resolve their dependencies

#### Scenario: pnpm-declared repo sets up pnpm

- **WHEN** the target repo declares `packageManager: pnpm@<version>`
- **THEN** the workflow runs `pnpm/action-setup@v4` and installs
  dependencies with `pnpm install --frozen-lockfile`, and does not
  set up bun

#### Scenario: bun-declared repo sets up bun

- **WHEN** the target repo declares `packageManager: bun@<version>`
- **THEN** the workflow runs `oven-sh/setup-bun@v2` and installs
  dependencies with `bun install --frozen-lockfile`, and does not
  set up pnpm

#### Scenario: bun repo without a packageManager field sets up bun at latest

- **WHEN** the target repo has no `packageManager` field, has a
  `bun.lock` (or `bun.lockb`) and no `pnpm-lock.yaml`
- **THEN** the workflow resolves bun, runs `oven-sh/setup-bun@v2`
  (which installs the latest Bun), installs dependencies with
  `bun install --frozen-lockfile`, and does not set up pnpm

#### Scenario: pnpm repo without a packageManager field fails before apply

- **WHEN** the target repo has `pnpm-lock.yaml`, no
  `bun.lock`/`bun.lockb`, and no `packageManager` field
- **THEN** the workflow exits non-zero before invoking Claude Code
  with a message stating that pnpm-managed repos must declare
  `packageManager: pnpm@<version>`

#### Scenario: Absent packageManager with both lockfiles fails before apply

- **WHEN** the target repo has no `packageManager` field and has
  **both** a bun lockfile and `pnpm-lock.yaml`
- **THEN** the workflow exits non-zero before invoking Claude Code
  with a message that the package manager is ambiguous

#### Scenario: Unsupported or unresolvable packageManager fails before apply

- **WHEN** the target repo's `package.json` declares a
  `packageManager` beginning with neither `pnpm@` nor `bun@`, or has
  no `packageManager` field and no lockfile of either manager
- **THEN** the workflow exits non-zero before invoking Claude Code,
  with a message identifying the supported package managers

#### Scenario: Workflow does not gate on type-check or test

- **WHEN** the workflow runs end to end
- **THEN** no step invokes a project-level type-check, lint, or
  test runner as a gate; only `openspec validate` is run as a
  structural gate (see "Validate change after apply")

### Requirement: Run /opsx:apply for the resolved change

The workflow SHALL invoke `claude -p "/opsx:apply <name>"` for the
resolved change name in non-interactive mode, passing `--model`
with the resolved model value and the Claude Code thinking-budget
flag corresponding to the resolved effort value. The exit code of
the Claude invocation SHALL be captured but SHALL NOT cause the
workflow to fail immediately.

#### Scenario: Apply step continues despite non-zero exit

- **WHEN** Claude Code exits non-zero from the apply invocation
- **THEN** the workflow continues to subsequent steps and records
  the exit code for later use in the PR body

#### Scenario: Apply invocation carries resolved model and effort

- **WHEN** the resolved model is `opus` and the resolved effort
  is `medium`
- **THEN** the `claude` invocation includes `--model opus` and the
  thinking-budget flag corresponding to `medium`

### Requirement: Default model and effort sourced from repository variables

The workflow SHALL read its default Claude model from the repository
variable `OPSX_APPLY_MODEL` and its default effort from the
repository variable `OPSX_APPLY_EFFORT`. When either variable is
unset or empty, the workflow SHALL fall back to baked-in defaults
of `sonnet` for model and `high` for effort.

#### Scenario: Both variables set

- **WHEN** the workflow runs with `vars.OPSX_APPLY_MODEL=opus` and
  `vars.OPSX_APPLY_EFFORT=medium`
- **AND** no overrides are present (no commit trailer)
- **THEN** the resolved model is `opus` and the resolved effort
  is `medium`

#### Scenario: Both variables unset

- **WHEN** neither `vars.OPSX_APPLY_MODEL` nor `vars.OPSX_APPLY_EFFORT`
  is set on the repository
- **AND** no overrides are present
- **THEN** the resolved model is `sonnet` and the resolved effort
  is `high`

#### Scenario: One variable set, the other unset

- **WHEN** `vars.OPSX_APPLY_MODEL=opus` and `vars.OPSX_APPLY_EFFORT`
  is unset
- **AND** no overrides are present
- **THEN** the resolved model is `opus` and the resolved effort
  is the baked-in default `high`

### Requirement: Commit trailer overrides defaults on push

The workflow SHALL parse the head commit message for trailers
`Opsx-Model:` and `Opsx-Effort:`. When a trailer is present, its
value SHALL override the variable-sourced or baked-in default for
that knob. Trailers SHALL be parsed by a strict trailer parser
(such as `git interpret-trailers`) rather than ad-hoc regex.

#### Scenario: Trailer overrides only the model

- **WHEN** the head commit message contains a trailer
  `Opsx-Model: opus`
- **AND** the workflow was triggered by push
- **AND** the repo variables are unset
- **THEN** the resolved model is `opus` and the resolved effort
  is the baked-in default `high`

#### Scenario: Trailer overrides both knobs

- **WHEN** the head commit message contains both
  `Opsx-Model: opus` and `Opsx-Effort: low` trailers
- **THEN** the resolved model is `opus` and the resolved effort
  is `low`

#### Scenario: No trailer means no override

- **WHEN** the head commit message contains no `Opsx-Model:` or
  `Opsx-Effort:` trailer
- **AND** the repo variables are set
- **THEN** the resolved values come from the repo variables

### Requirement: Override precedence

The workflow SHALL resolve each of `model` and `effort`
independently using this precedence, highest to lowest: commit
trailer on the head commit, repository variable, baked-in default.

#### Scenario: Commit trailer beats repository variable

- **WHEN** the head commit message contains `Opsx-Model: opus`
- **AND** `vars.OPSX_APPLY_MODEL=haiku` is set
- **THEN** the resolved model is `opus`

#### Scenario: Repository variable beats baked-in default

- **WHEN** no commit trailer overrides `model`
- **AND** `vars.OPSX_APPLY_MODEL=opus` is set
- **THEN** the resolved model is `opus`

#### Scenario: Baked-in default applies when nothing else does

- **WHEN** no commit trailer overrides `model` or `effort`
- **AND** neither `vars.OPSX_APPLY_MODEL` nor
  `vars.OPSX_APPLY_EFFORT` is set
- **THEN** the resolved model is `sonnet` and the resolved
  effort is `high`

### Requirement: Effort enum validation

The workflow SHALL accept only `low`, `medium`, or `high` as
resolved `effort` values. If the resolved value (from any source)
is anything else, the workflow SHALL exit non-zero before invoking
Claude Code with a message identifying the invalid value and its
source.

#### Scenario: Unknown effort fails fast

- **WHEN** the resolved effort value is `extreme`
- **THEN** the workflow exits non-zero before invoking Claude
  Code, with a message naming the invalid value and the source it
  came from (commit trailer, repository variable, or baked-in
  default)

#### Scenario: Valid effort proceeds

- **WHEN** the resolved effort value is `low`, `medium`, or `high`
- **THEN** the workflow proceeds to invoke Claude Code

### Requirement: Effort maps to Claude Code thinking budget

The workflow SHALL translate the resolved effort enum value into
the Claude Code CLI flag that controls thinking budget, passing
the result to the `claude` invocation. `low` SHALL correspond to a
smaller thinking budget than `medium`, which SHALL correspond to a
smaller budget than `high`. The exact flag name and budget values
SHALL be those supported by the installed Claude Code CLI version.

#### Scenario: High effort produces a larger budget than low effort

- **WHEN** two runs are compared, identical except that one
  resolves to `effort=high` and the other to `effort=low`
- **THEN** the high-effort run is invoked with a thinking-budget
  value strictly greater than the low-effort run

### Requirement: Resolved values reported in PR

The workflow SHALL include the resolved `model` and `effort`
values in the body of any PR it creates and in any comment it
adds to an existing PR for the change branch.

#### Scenario: First successful run reports resolved values

- **WHEN** the workflow opens a new PR for the change branch
- **THEN** the PR body contains the resolved `model` and the
  resolved `effort` values for that run

#### Scenario: Rerun comment reports resolved values

- **WHEN** the workflow comments on an existing PR for the change
  branch
- **THEN** the comment contains the resolved `model` and `effort`
  values for that run

### Requirement: Validate change after apply

The workflow SHALL run `openspec validate <change>` after the apply
step. The exit code of the validate step SHALL be captured.

#### Scenario: Validate runs regardless of apply outcome

- **WHEN** the apply step has completed (with any exit code)
- **THEN** the validate step runs and its exit code is recorded

### Requirement: Commit any uncommitted agent output

The workflow SHALL stage all working-tree changes and create a single commit if any uncommitted changes exist after the apply step. If the working tree is clean after apply, the workflow SHALL NOT create an empty commit. Commits created by this step SHALL be authored by the GitHub App's bot identity (see "Bot git identity matches the GitHub App").

#### Scenario: Agent left changes unstaged

- **WHEN** apply completes with modified files in the working tree
- **AND** the changes are not yet committed
- **THEN** the workflow creates a commit containing those changes
  with author `<slug>[bot]` (the GitHub App identity)

#### Scenario: Agent already committed everything

- **WHEN** apply completes with a clean working tree
- **THEN** the workflow does not create an additional commit

### Requirement: Push the change branch

The workflow SHALL push commits to the change branch using the GitHub App installation token (see "GitHub App installation token minted before any git or PR operation") whenever the local branch is ahead of `origin`. The workflow SHALL NOT push when no commits are ahead of `origin`. The workflow SHALL NOT use `secrets.GITHUB_TOKEN` or any operator PAT for this push.

#### Scenario: New commits are pushed to the branch

- **WHEN** the local branch is ahead of its remote tracking branch
- **THEN** the workflow pushes the new commits to `origin` using the App installation token persisted by the `actions/checkout` step

#### Scenario: Push attempts under `.github/workflows/` succeed for the App

- **WHEN** the agent's apply step modifies a file under `.github/workflows/`
- **AND** the workflow attempts to push that change
- **THEN** the push succeeds (the App's installation token has `Workflows: write`, which `secrets.GITHUB_TOKEN` lacks)

### Requirement: GitHub App installation token minted before any git or PR operation

The workflow SHALL mint a short-lived GitHub App installation token as the first job step after the preflight gates (secret presence, trigger subject case-sensitivity, change-name resolution). The token SHALL be obtained by exchanging the App ID and PEM-encoded private key for an installation token via the canonical `actions/create-github-app-token` action (or an equivalent action that produces a single-installation token bound to the running repository). The App ID SHALL be read from `secrets.REMCC_APP_ID` and the private key from `secrets.REMCC_APP_PRIVATE_KEY`. The minted token's value SHALL be redacted from workflow logs.

All subsequent steps that interact with the git remote or the GitHub API on behalf of remcc — `actions/checkout`, `git push`, and `gh pr create` / `gh pr comment` — SHALL use the minted installation token, not `secrets.GITHUB_TOKEN` and not any operator personal access token.

#### Scenario: Missing App ID secret fails fast

- **WHEN** `REMCC_APP_ID` is not set in repository secrets
- **THEN** the workflow exits non-zero before minting a token or invoking Claude Code, with a message identifying the missing secret and pointing the operator at `install.sh reconfigure`

#### Scenario: Missing App private key secret fails fast

- **WHEN** `REMCC_APP_PRIVATE_KEY` is not set in repository secrets
- **THEN** the workflow exits non-zero before minting a token or invoking Claude Code, with a message identifying the missing secret and pointing the operator at `install.sh reconfigure`

#### Scenario: App not installed on the target repo surfaces clear error

- **WHEN** the App credentials are present but the App has not been installed on the running repository
- **THEN** the token-mint step fails with a non-zero exit, the workflow surfaces a `::error::` annotation that names the App slug and links to the App's settings page, and no Claude Code invocation has been made

#### Scenario: Minted token is used for checkout

- **WHEN** the token-mint step completes successfully
- **THEN** the `actions/checkout` step that follows uses the minted token (passed via the action's `token:` input) so the remote URL is persisted with the App's credentials for subsequent `git push`

#### Scenario: Minted token is used for PR creation

- **WHEN** the workflow reaches the PR-open-or-update step
- **THEN** `gh pr create` and `gh pr comment` run with `GH_TOKEN` set to the minted installation token, not `secrets.GITHUB_TOKEN`

### Requirement: Bot git identity matches the GitHub App

The workflow SHALL configure `git user.name` and `git user.email` so that commits the workflow creates are attributed to the GitHub App's bot identity. `user.name` SHALL be `<slug>[bot]` where `<slug>` is the App's GitHub slug, read from the repository variable `REMCC_APP_SLUG`. `user.email` SHALL be `<numeric-id>+<slug>[bot]@users.noreply.github.com`, where `<numeric-id>` is the numeric ID of the bot user backing the App. The workflow SHALL look up the numeric ID at runtime by querying the GitHub API (`GET /users/<slug>[bot]`) using the minted installation token; the value SHALL NOT be hardcoded in the workflow template.

#### Scenario: Commits land with the App's identity

- **WHEN** the workflow creates a commit on a `change/**` branch
- **THEN** the commit's author and committer fields show `<slug>[bot] <numeric-id>+<slug>[bot]@users.noreply.github.com`

#### Scenario: Missing slug variable fails fast

- **WHEN** the repository variable `REMCC_APP_SLUG` is unset or empty
- **THEN** the workflow exits non-zero before invoking Claude Code, with a message identifying the missing variable and pointing the operator at `install.sh reconfigure`

### Requirement: PR author is the GitHub App identity

Any pull request the workflow creates SHALL be authored by the GitHub App's bot identity (`<slug>[bot]`), not by `github-actions[bot]` and not by the operator. This is a direct consequence of using the minted installation token for `gh pr create`, but it is called out as a normative requirement so that future workflow refactors do not silently regress to `secrets.GITHUB_TOKEN`-backed PR creation.

#### Scenario: First successful run opens a PR as the App

- **WHEN** the workflow opens a new PR for the change branch
- **THEN** the PR's "author" field as returned by `gh pr view --json author --jq .author.login` is `<slug>[bot]`

#### Scenario: PR comments on subsequent runs come from the App

- **WHEN** the workflow comments on an existing PR for the change branch
- **THEN** the comment's "author" field is `<slug>[bot]`

### Requirement: Open or update the change PR

If the change branch has commits ahead of `main`, the workflow SHALL
ensure a PR exists from the change branch to `main`. If no PR exists,
the workflow SHALL create one with the title format
`Change: <change-name>` (the literal string `Change: ` followed by
the resolved change name as the entire title). If a PR already
exists, the workflow SHALL post a comment summarising the run and
SHALL NOT modify the existing PR's title.

The run-summary PR body (on PR creation) and the run-summary rerun
comment (on subsequent runs) SHALL include separate lines for the
`apply`, `validate`, and `verify` exit codes. The verification
report itself SHALL NOT be embedded in the run-summary body or
comment — it lives only in the dedicated verify comment (see
"Verify report posted as dedicated PR comment").

#### Scenario: First successful run opens a PR

- **WHEN** the workflow completes successfully and no PR exists
  for the change branch `change/foo`
- **THEN** the workflow creates a PR with the title `Change: foo`
  and the apply, validate, and verify exit codes each on their own
  line in the body

#### Scenario: Subsequent run on existing PR adds a comment

- **WHEN** the workflow completes and a PR already exists for the
  change branch
- **THEN** the workflow adds a run-summary comment to the PR with
  the latest apply, validate, and verify exit codes
- **AND** the existing PR's title is not changed

#### Scenario: Run-summary does not embed the verify report

- **WHEN** the workflow opens a new PR or posts a run-summary
  comment
- **THEN** the body/comment contains the verify exit code but does
  not contain the scorecard table or CRITICAL/WARNING/SUGGESTION
  sections from `verify.md`

### Requirement: Surface failures as draft PR

Any PR the workflow creates SHALL be opened as a draft whenever
either the apply or validate step exited non-zero. The workflow
SHALL NOT silently switch existing PRs between draft and ready.

#### Scenario: Apply failure produces a draft PR

- **WHEN** apply exited non-zero and no PR exists yet
- **THEN** the workflow creates the PR with `--draft`

#### Scenario: Validate failure produces a draft PR

- **WHEN** apply exited zero but validate exited non-zero, and no
  PR exists yet
- **THEN** the workflow creates the PR with `--draft`

### Requirement: Concurrency cancels in-flight runs

The workflow SHALL declare a concurrency group keyed on the branch
ref with `cancel-in-progress: true`, so that pushing a new commit
to a change branch cancels any in-flight run for the same branch.

#### Scenario: New push cancels prior run

- **WHEN** a workflow run is in progress for branch `change/foo`
- **AND** a new commit is pushed to `change/foo`
- **THEN** the prior run is cancelled and a new run begins

### Requirement: Concurrency group is partitioned by trigger-vs-noop

The workflow's concurrency group key SHALL include a partition
suffix that is `apply` when the head commit subject opts into the
apply trigger and `noop` otherwise, so that `cancel-in-progress:
true` only cancels runs within the `apply` slot. Non-trigger
pushes (the bot's own output push, WIP commits, near-miss
subjects) SHALL NOT cancel an in-flight apply run.

#### Scenario: Bot's output push does not cancel the parent apply

- **WHEN** an apply run on `change/foo` completes its `Push branch`
  step (pushing the bot's `/opsx:apply foo` commit)
- **AND** the resulting push fires a new workflow listener
- **THEN** the new listener's run is placed in the `noop` partition
  of the concurrency group, separate from the parent run's
  `apply` partition
- **AND** the parent run finishes with overall conclusion `success`
  (not `cancelled`)

#### Scenario: WIP push during in-flight apply does not cancel it

- **WHEN** an apply run on `change/foo` is in flight
- **AND** an author pushes a draft commit (subject not starting
  with `@change-apply`) to the same branch
- **THEN** the WIP push's run is placed in the `noop` partition
- **AND** the in-flight apply continues to completion uninterrupted

#### Scenario: Fresh trigger push during in-flight apply cancels it

- **WHEN** an apply run on `change/foo` is in flight
- **AND** an author pushes another commit whose subject starts
  with `@change-apply` to the same branch
- **THEN** both runs share the `apply` partition of the
  concurrency group
- **AND** `cancel-in-progress: true` cancels the in-flight run so
  the new trigger commit applies against the latest branch state

### Requirement: Upload apply and validate logs

The workflow SHALL upload `apply.log`, `apply.jsonl`, `validate.log`,
`verify.md`, and `verify.jsonl` as a single workflow artifact named
`agent-logs-<change>` with a retention of 14 days, regardless of
whether earlier steps succeeded or failed. Missing files SHALL be
ignored by the upload step (so a crashed verify that produced no
`verify.md` does not fail the upload).

#### Scenario: Logs are retrievable after a failed run

- **WHEN** the workflow run has completed (success or failure)
- **THEN** an artifact `agent-logs-<change>` is available for
  download from the run summary

#### Scenario: Artifact contains verify outputs alongside apply and validate

- **WHEN** the workflow run has completed and the verify step
  produced a `verify.md` and `verify.jsonl`
- **THEN** the `agent-logs-<change>` artifact includes
  `verify.md` and `verify.jsonl` alongside `apply.log`,
  `apply.jsonl`, and `validate.log`

#### Scenario: Missing verify outputs do not fail the artifact upload

- **WHEN** the verify step crashed before writing `verify.md`
- **THEN** the upload step still completes and the artifact contains
  whichever of the expected files exist on disk

### Requirement: Run /opsx:verify after validate

The workflow SHALL invoke `claude -p "/opsx:verify <name>"` for the
resolved change name in non-interactive mode immediately after the
validate step. The invocation SHALL pass `--model` with the same
resolved model value used by the apply step and the Claude Code
thinking-budget flag corresponding to the same resolved effort value
used by the apply step (i.e. verify reuses apply's already-resolved
values from the existing trailer → repository-variable →
baked-in-default precedence; no separate verify config surface is
introduced). The invocation SHALL pass `--dangerously-skip-permissions`,
matching the apply step's sandbox posture.

The verify step SHALL run regardless of the apply or validate exit
codes. The exit code of the Claude invocation SHALL be captured into a
step output named `exit_code` but SHALL NOT cause the workflow to fail
immediately (`continue-on-error: true`).

#### Scenario: Verify runs after a successful apply and validate

- **WHEN** apply has exited zero and validate has exited zero
- **THEN** the workflow invokes `claude -p "/opsx:verify <name>"` next
- **AND** the verify step's exit code is captured into its step output

#### Scenario: Verify runs even when apply exited non-zero

- **WHEN** apply has exited non-zero
- **THEN** validate runs (per existing contract) and verify runs after
  it
- **AND** verify's exit code is captured into its step output

#### Scenario: Verify runs even when validate exited non-zero

- **WHEN** apply exited zero but validate exited non-zero
- **THEN** verify runs after validate
- **AND** verify's exit code is captured into its step output

#### Scenario: Verify reuses apply's resolved model and effort

- **WHEN** the workflow's `config` step resolved `model=opus` and
  `effort=medium` for this run
- **THEN** the verify step's `claude` invocation is passed
  `--model opus` and the thinking-budget flag corresponding to
  `medium`, with no other source of model or effort consulted

#### Scenario: Verify non-zero does not fail the workflow step that follows

- **WHEN** Claude Code exits non-zero from the verify invocation
- **THEN** the workflow continues to subsequent steps (stage, push,
  PR open/update, post verify report) and records the verify exit code
  for later use

#### Scenario: Verify completes before any PR-side communication

- **WHEN** the workflow runs end-to-end for a single trigger commit
- **THEN** the verify step finishes before any of: the
  `open or update the change PR` step, the run-summary rerun comment,
  or the dedicated verify comment are produced
- **AND** the run-summary body or rerun comment posted by this run
  reflects the verify exit code captured in this run, not a prior one

#### Scenario: Every trigger commit on the same branch gets its own verify

- **WHEN** apply has already been run once on `change/foo` (PR exists)
- **AND** the author pushes a second `@change-apply` trigger commit
  to `change/foo`
- **THEN** the second workflow job runs apply, then validate, then
  verify in order
- **AND** the second job posts both a fresh run-summary rerun comment
  (with the second run's verify exit code) and a fresh dedicated
  verify comment (with the second run's `verify.md`)

### Requirement: Verify report captured as markdown

The workflow SHALL capture the markdown verification report produced
by the `/opsx:verify` skill — the final assistant text message of the
Claude invocation — into a file named `verify.md` at the runner's
working directory. The workflow SHALL capture the raw NDJSON stream
of the verify invocation into a file named `verify.jsonl` in the same
directory.

#### Scenario: Successful verify writes a non-empty verify.md

- **WHEN** the verify invocation completes and the skill emitted its
  markdown report as its final assistant message
- **THEN** the workflow has written that markdown report to
  `verify.md`
- **AND** `verify.jsonl` contains the raw NDJSON stream of the
  invocation

#### Scenario: Verify crash produces an empty or missing verify.md

- **WHEN** the verify invocation exits non-zero before emitting a
  final assistant text message
- **THEN** `verify.md` may be empty or absent at the runner's working
  directory
- **AND** `verify.jsonl` still contains whatever partial NDJSON the
  stream captured before the crash

### Requirement: Verify report posted as dedicated PR comment

The workflow SHALL post the contents of `verify.md` as a dedicated
pull-request comment on the change PR using `gh pr comment`
authenticated with the GitHub App installation token (see "GitHub App
installation token minted before any git or PR operation"). The post
step SHALL run after the existing "open or update the change PR" step
and only when a pull request exists for the change branch (i.e. the
branch is ahead of `main`).

The verify comment SHALL be distinct from the run-summary body or
run-summary rerun comment created by the "open or update the change
PR" step. The workflow SHALL NOT replace, edit, or fold previous
verify comments; each run SHALL produce a fresh dedicated verify
comment on the PR.

If no pull request exists for the change branch (e.g. the branch has
no commits ahead of `main`), the workflow SHALL NOT post a verify
comment.

If `verify.md` is missing or empty, the workflow SHALL post a
fallback comment naming the captured verify exit code and pointing
the reader at the `agent-logs-<change>` artifact, rather than skip
posting entirely.

If `verify.md` exceeds GitHub's PR-comment body size limit, the
workflow SHALL post a truncated body that retains the top of the
report and ends with a footer indicating the report was truncated
and naming the `agent-logs-<change>` artifact as the source of the
full report.

#### Scenario: First successful run posts a dedicated verify comment

- **WHEN** the workflow has opened a new PR for the change branch
- **AND** `verify.md` is non-empty
- **THEN** the workflow posts a second PR comment whose body is the
  contents of `verify.md`, distinct from the PR body itself

#### Scenario: Rerun on existing PR posts another dedicated verify comment

- **WHEN** the workflow completes and a PR already exists for the
  change branch
- **AND** `verify.md` is non-empty
- **THEN** the workflow posts a fresh dedicated verify comment whose
  body is the contents of `verify.md`, separate from the run-summary
  rerun comment

#### Scenario: Verify comment author is the GitHub App identity

- **WHEN** the workflow posts a dedicated verify comment
- **THEN** the comment's author field as returned by the GitHub API
  is `<slug>[bot]` (the GitHub App's bot identity), matching the PR
  author

#### Scenario: No PR means no verify comment

- **WHEN** the change branch has no commits ahead of `main` and no
  PR is opened
- **THEN** the workflow does not post a verify comment

#### Scenario: Missing or empty verify.md produces a fallback comment

- **WHEN** the verify step crashed and `verify.md` is missing or
  empty
- **AND** a PR exists for the change branch
- **THEN** the workflow posts a fallback comment naming the captured
  verify exit code and the `agent-logs-<change>` artifact, rather
  than skipping the post step

#### Scenario: Oversized verify.md is posted truncated with a pointer

- **WHEN** `verify.md` exceeds GitHub's PR-comment body size cap
- **AND** a PR exists for the change branch
- **THEN** the workflow posts a truncated body that retains the head
  of the report and ends with a footer pointing at the
  `agent-logs-<change>` artifact

### Requirement: Verify is informational and does not gate draft status

The workflow's draft-on-failure logic SHALL consider only the apply
and validate exit codes when deciding whether to open a new PR with
`--draft` (see "Surface failures as draft PR"). The verify exit
code, the contents of `verify.md`, and the presence of CRITICAL,
WARNING, or SUGGESTION findings in the verify report SHALL NOT
affect the `--draft` flag on PR open. The workflow SHALL NOT toggle
an existing PR between draft and ready based on verify outcome.

#### Scenario: Apply clean and validate clean but verify reports CRITICAL — PR opens ready

- **WHEN** apply exited zero, validate exited zero, no PR exists
  yet, and `verify.md` contains CRITICAL findings
- **THEN** the workflow creates the PR without `--draft` (ready for
  review)

#### Scenario: Apply clean and validate clean and verify exited non-zero — PR opens ready

- **WHEN** apply exited zero, validate exited zero, no PR exists
  yet, and the verify step exited non-zero (e.g. skill crashed)
- **THEN** the workflow creates the PR without `--draft`

#### Scenario: Validate non-zero still drafts the PR regardless of verify

- **WHEN** apply exited zero, validate exited non-zero, and verify
  reports no CRITICAL findings
- **AND** no PR exists yet
- **THEN** the workflow creates the PR with `--draft` (validate
  failure remains the trigger)

#### Scenario: Apply non-zero still drafts the PR regardless of verify

- **WHEN** apply exited non-zero, validate exited zero, and verify
  reports no CRITICAL findings
- **AND** no PR exists yet
- **THEN** the workflow creates the PR with `--draft` (apply failure
  remains the trigger)

### Requirement: Bounded run duration

The workflow's `apply` job SHALL declare `timeout-minutes: 180` as
a hard ceiling on wall-clock duration.

#### Scenario: Runaway apply is killed by timeout

- **WHEN** the apply job has been running for 180 minutes
- **THEN** the runner cancels the job

### Requirement: ANTHROPIC_API_KEY supplied via secret

The workflow SHALL read `ANTHROPIC_API_KEY` from
`secrets.ANTHROPIC_API_KEY` and expose it to the apply step via
environment variable. The workflow SHALL NOT echo or log the key.

#### Scenario: Missing secret fails fast

- **WHEN** `ANTHROPIC_API_KEY` is not set in repository secrets
- **THEN** the workflow exits non-zero before invoking Claude Code,
  with a message identifying the missing secret
