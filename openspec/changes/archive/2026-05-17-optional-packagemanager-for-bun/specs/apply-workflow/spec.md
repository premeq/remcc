## MODIFIED Requirements

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
