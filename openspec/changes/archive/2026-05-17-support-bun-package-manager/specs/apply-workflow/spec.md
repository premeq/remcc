## MODIFIED Requirements

### Requirement: Workflow prepares runtime before apply

The workflow SHALL prepare the runner before invoking the apply step
by (a) installing a Node.js version that satisfies the OpenSpec
CLI's minimum requirement (`>= 20.19` at the time of this change),
(b) installing the Claude Code CLI and the OpenSpec CLI globally so
that both `claude` and `openspec` are resolvable on `PATH`, and
(c) installing the target repository's workspace dependencies using
the package manager the target repository declares in
`package.json#packageManager` — pnpm or bun — so that scripts the
agent may execute during apply can resolve their imports.

The workflow SHALL derive the package manager on the runner from
`package.json#packageManager` (no adopter edits to the template
required): a value beginning `pnpm@` selects pnpm and a value
beginning `bun@` selects bun. The workflow SHALL set up the selected
manager via its canonical setup action (`pnpm/action-setup@v4` for
pnpm, `oven-sh/setup-bun@v2` for bun), each resolving its version
from the same `packageManager` field, and SHALL install dependencies
with `<pm> install --frozen-lockfile`. If `packageManager` is absent
or names a manager other than pnpm or bun, the workflow SHALL exit
non-zero before invoking Claude Code with a message naming the
supported managers.

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

#### Scenario: Unsupported or missing packageManager fails before apply

- **WHEN** the target repo's `package.json` has no `packageManager`
  field, or one beginning with neither `pnpm@` nor `bun@`
- **THEN** the workflow exits non-zero before invoking Claude Code,
  with a message identifying the supported package managers

#### Scenario: Workflow does not gate on type-check or test

- **WHEN** the workflow runs end to end
- **THEN** no step invokes a project-level type-check, lint, or
  test runner as a gate; only `openspec validate` is run as a
  structural gate (see "Validate change after apply")
