# project-readme Specification

## Purpose

Defines the contract for the repository's root `README.md` as the
project's public landing page on GitHub: what content it must present
(hero, value proposition, install one-liner, doc links, limitations),
in what order, and how it relates to the deeper documentation set in
`docs/`. Also pins the canonical path of the project logo asset that
the README references.

## Requirements

### Requirement: README serves as the project's landing page

The repository SHALL ship a `README.md` at its root that functions as the project's landing page. The page SHALL communicate, in this order: (a) the project identity (logo + name + tagline), (b) the value proposition in one short paragraph, (c) the install one-liner, and (d) link-outs to the in-repo documentation set. The hero (identity + tagline + badges) and value-proposition paragraph SHALL fit within the first ~50 lines so they are visible without scrolling on a standard GitHub viewport.

#### Scenario: First-time visitor sees value prop above the fold

- **WHEN** a visitor who has never seen remcc opens `README.md` on github.com at a standard viewport
- **THEN** the logo, project name, tagline, and one-paragraph value proposition are visible without scrolling

#### Scenario: Returning visitor sees the install one-liner near the top

- **WHEN** a returning visitor scans the README for the install command
- **THEN** the `install.sh init` one-liner is rendered in a fenced code block within the first two sections after the hero, not buried below limitations or upgrade flow

### Requirement: README contains a centered hero with logo, name, tagline, and badges

The README's hero SHALL be a centered block (rendered via `<div align="center">` or equivalent GitHub-supported HTML) containing: the project logo image referenced from `assets/logo.png`, the project name as an H1 heading, a single-line tagline, and a row of decorative badges. The badge row SHALL include at minimum a license badge and a "powered by Claude Code" link badge, both sourced from public shield endpoints with no build-time generation.

#### Scenario: Logo renders inline on github.com

- **WHEN** the README is viewed on github.com
- **THEN** the logo image at `assets/logo.png` renders inside the centered hero block, scaled to a width that leaves the page readable on a 1280px viewport

#### Scenario: Hero badges are decorative, not load-bearing

- **WHEN** a badge image fails to load (e.g. shields.io temporarily unreachable)
- **THEN** the remainder of the README still renders and remains readable, with no broken sections or missing required content beyond the badge image itself

### Requirement: README documents current functionality, not legacy

The README SHALL accurately describe remcc's current behaviour. It SHALL reference: `install.sh init` as the primary adoption flow, `install.sh upgrade` as the update flow, the GitHub App identity model (not the legacy `WORKFLOW_PAT`), the `@change-apply` opt-in commit-subject trigger convention, and the existence of per-run `model` / `effort` configuration knobs (without re-documenting their full override precedence — that lives in `docs/SETUP.md`). The README SHALL NOT reference removed or replaced mechanisms (e.g. `WORKFLOW_PAT`, an always-on push trigger).

#### Scenario: README mentions the opt-in trigger

- **WHEN** a reader reaches the section describing how a push triggers an apply run
- **THEN** the text names the `@change-apply` opt-in convention (or equivalent phrasing identifying that pushing alone is insufficient without the commit-subject opt-in)

#### Scenario: README mentions the GitHub App identity

- **WHEN** a reader reaches the section describing the bot or how PRs are authored
- **THEN** the text identifies the bot as authenticating via a GitHub App (not a personal access token)

#### Scenario: README references install.sh upgrade

- **WHEN** a reader looks for how to refresh an adopted repo's templates
- **THEN** they find the `install.sh upgrade` one-liner and a link to `docs/SETUP.md#upgrading-remcc`

### Requirement: README links to the canonical docs

The README SHALL contain a "Docs" link block that points to `docs/SETUP.md`, `docs/SECURITY.md`, and `docs/COSTS.md`, each with a one-line description of what the reader will find there. The README SHALL NOT duplicate substantive content from those documents; for any topic covered in depth in `docs/`, the README SHALL summarise in at most two sentences and link onward.

#### Scenario: Reader navigates from README to deeper docs

- **WHEN** a reader wants to understand the security model
- **THEN** they find a one-sentence summary in the README and a link to `docs/SECURITY.md`

#### Scenario: README does not duplicate SETUP.md prerequisites

- **WHEN** a reader looks for the full prerequisites checklist
- **THEN** the README directs them to `docs/SETUP.md` rather than reproducing the checklist inline

### Requirement: README declares limitations honestly

The README SHALL contain a brief "Limitations" section enumerating the v1 scope constraints: Claude Code only, GitHub Actions only, OpenSpec `/opsx:apply` only, pnpm- or bun-managed JavaScript repos only (npm/yarn unsupported), one invocation per change. The section SHALL be present near (not at) the top so visitors can self-disqualify quickly, but SHALL NOT dominate the page (≤ ~10 lines including the heading).

#### Scenario: Reader can self-disqualify quickly

- **WHEN** a reader using npm or yarn opens the README
- **THEN** they encounter the package-manager limitation (pnpm or bun only) within the first three top-level sections and can stop reading

### Requirement: Project logo asset lives at assets/logo.png

The repository SHALL contain a project logo at `assets/logo.png`, committed to `main`, and the README SHALL reference it via the relative path `assets/logo.png`. The asset MAY be replaced or supplemented later (e.g. with a dark-mode variant) without changing the canonical path used by the README hero.

#### Scenario: Logo path resolves on github.com and in clones

- **WHEN** the README is rendered on github.com OR a clone is opened locally in a markdown viewer that supports relative paths
- **THEN** the image at `assets/logo.png` resolves and renders inside the README hero

#### Scenario: Logo file is committed to the repository

- **WHEN** a fresh clone of the repository is inspected
- **THEN** the file `assets/logo.png` exists on the `main` branch as a tracked binary asset
