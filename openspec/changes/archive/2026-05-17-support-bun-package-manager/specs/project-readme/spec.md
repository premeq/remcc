## MODIFIED Requirements

### Requirement: README declares limitations honestly

The README SHALL contain a brief "Limitations" section enumerating the v1 scope constraints: Claude Code only, GitHub Actions only, OpenSpec `/opsx:apply` only, pnpm- or bun-managed JavaScript repos only (npm/yarn unsupported), one invocation per change. The section SHALL be present near (not at) the top so visitors can self-disqualify quickly, but SHALL NOT dominate the page (≤ ~10 lines including the heading).

#### Scenario: Reader can self-disqualify quickly

- **WHEN** a reader using npm or yarn opens the README
- **THEN** they encounter the package-manager limitation (pnpm or bun only) within the first three top-level sections and can stop reading
