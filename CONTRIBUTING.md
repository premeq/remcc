# Contributing to remcc

Thanks for your interest. remcc is a small docs-and-templates kit;
contributions land via fork + pull request.

## Before opening a PR

- For non-trivial changes (new features, behavior changes), please
  open an issue first so we can discuss scope before you write code.
- Typo fixes, doc improvements, and obvious bugs can go straight to
  a PR — describe what changes and why in the PR body.

## Workflow

- Fork the repo, branch from `main`, push, open a PR against
  `premeq/remcc:main`.
- Keep PRs focused — one concern per PR.
- The maintainer is solo and best-effort. Expect a few days'
  turnaround; ping the PR if it goes quiet for over a week.

## Local checks

There is no CI; run these before opening a PR:

- `shellcheck -S warning install.sh scripts/*.sh` — shell lint.
- `scripts/test-resolve-pm.sh` — fast, offline truth-table for the
  package-manager resolver (no network, no GitHub). Run this whenever
  you touch `install.sh`'s prerequisite logic or the workflow's
  package-manager handling.
- The `scripts/smoke-*.sh` end-to-end checks require live GitHub +
  credentials and create throwaway repos — run them only when changing
  adoption/upgrade behavior. Set `SMOKE_PM=bun` (default `pnpm`) to
  exercise the bun adoption path.

## Scope

remcc v1 is intentionally narrow: Claude Code, GitHub Actions,
OpenSpec `/opsx:apply`, pnpm- or bun-managed JavaScript repos
(see [README.md](README.md#limitations)). Generalising any of those
is in scope but warrants an issue first so we don't duplicate effort.
