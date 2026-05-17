<div align="center">

<img src="assets/logo.png" width="180" alt="remcc logo">

# remcc: Remote Claude Code

Run Claude Code unattended — push a change branch, get a PR.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Powered by Claude Code](https://img.shields.io/badge/powered%20by-Claude%20Code-6f42c1.svg)](https://claude.com/claude-code)
[![OpenSpec](https://img.shields.io/badge/spec-OpenSpec-2ea44f.svg)](https://github.com/Fission-AI/OpenSpec)
[![Last commit](https://img.shields.io/github/last-commit/premeq/remcc.svg)](https://github.com/premeq/remcc/commits/main)

</div>

Push a `change/<name>` branch carrying an [OpenSpec](https://github.com/Fission-AI/OpenSpec) proposal and an `@change-apply` opt-in commit; remcc runs `/opsx:apply` with [Claude Code](https://claude.com/claude-code) on a GitHub-hosted runner and opens a pull request for your review.

## Why remcc

- **No laptop tether.** Claude Code loop runs on a GitHub-hosted runner, while you do something else.
- **Normal PR review.** Output lands as a branch + PR; the usual review, CI, and branch-protection apply.
- **Tight safety boundary.** Claude Code runs in an ephemeral Ubuntu VM, destroyed after coding is completed.

## Full walkthrough in 3 minutes

> Three phases: [author locally] -> [apply on a runner] -> [review and merge locally]

### `01` · Prerequisites

- An [OpenSpec](https://github.com/Fission-AI/OpenSpec)-initialised, pnpm-managed repo with `.claude/` committed
- A `remcc` GitHub App installed on the target repo
- An Anthropic API key with budget

Full checklist: [docs/SETUP.md#prerequisites](docs/SETUP.md#prerequisites).

### `02` · Installation

From a clean clone of the target repository on `main`:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/foster-systems/remcc/main/install.sh) init
```

Verifies prerequisites, configures GitHub-side controls (default-branch approval ruleset, secret scanning, secrets, `opsx:apply` defaults), writes the workflow and template files, and opens a `remcc-init` PR for you to merge. See [docs/SETUP.md](docs/SETUP.md).

### `03` · Propose a change locally

On a fresh `change/<name>` branch, draft the OpenSpec change with Claude:

```sh
claude /opsx:propose
```

Generates `openspec/changes/<name>/` with `proposal.md`, `design.md`, `specs/`, and `tasks.md`. Iterate freely — WIP pushes don't fire the runner.

### `04` · Push the `@change-apply` trigger commit

```sh
git commit --allow-empty -m "@change-apply: first pass"
git push
```

Only commit subjects starting with `@change-apply` trigger apply. Trailers (`Opsx-Model:`, `Opsx-Effort:`) override model and thinking budget per run — see [docs/SETUP.md#configuring-the-apply-model](docs/SETUP.md#configuring-the-apply-model).

---

#### :robot: **Runner takes over.**

### `05` · `/opsx:apply` runs on a GitHub-hosted Ubuntu VM

The `opsx-apply` workflow spins up an ephemeral `ubuntu-latest` runner, executes `/opsx:apply <name>` against the branch state, validates the change, then destroys the VM. Logs upload as a workflow artifact.

### `06` · PR opened by the remcc GitHub App

The App pushes the apply output and opens a PR to `main` as `<app-slug>[bot]` — a distinct actor from you, so the default-branch approval ruleset lets you review and approve it (the bot can't approve its own PR). Apply errors land as a draft PR with logs attached.

---

#### :computer: **Back to local.**

### `07` · Verify and archive locally

Pull the PR branch, finalise the change, push back:

```sh
git fetch && git checkout change/<name> && git pull
claude /opsx:verify
claude /opsx:archive
git add . && git commit -m "Archive change/<name>"
git push
```

`/opsx:verify` checks the implementation against the artifacts. `/opsx:archive` moves the change folder under `openspec/changes/archive/` and syncs delta specs into the main specs. Any subject that doesn't start with `@change-apply` is safe — the archive push won't re-trigger the runner.

### `08` · Approve and merge

Approve the PR and merge into `main`. The change branch is deleted on merge.

## Limitations

remcc v1 is intentionally narrow:

- **Claude Code only.** No other AI coding agents.
- **GitHub Actions only.** No GitLab, Bitbucket, CircleCI.
- **OpenSpec `/opsx:apply` only.** No arbitrary prompts.
- **pnpm-managed JavaScript repos only.** The workflow runs `pnpm install --frozen-lockfile`.
- **One invocation per change.** Push or `workflow_dispatch`, then watch the PR.

Deeper hardening caveats (org-vs-user-owned repo, GHAS-gated controls) live in [docs/SECURITY.md](docs/SECURITY.md).

## Upgrade

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/foster-systems/remcc/main/install.sh) upgrade
```

Opens a `remcc-upgrade` PR with the template diff — see [docs/SETUP.md#upgrading-remcc](docs/SETUP.md#upgrading-remcc).

## Docs

- [docs/SETUP.md](docs/SETUP.md) — prerequisites, App setup, automated and manual adoption, configuration knobs.
- [docs/SECURITY.md](docs/SECURITY.md) — threat model, identity boundary, hardening caveats by repo ownership.
- [docs/COSTS.md](docs/COSTS.md) — Anthropic API and GitHub Actions cost guidance.

## Status

remcc v1 targets monorepo adoption and is stable enough for trial use.
