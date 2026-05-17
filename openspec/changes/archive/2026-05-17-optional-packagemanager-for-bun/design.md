## Context

The archived change `support-bun-package-manager` made remcc pnpm-or-bun
aware via one `resolve_package_manager` helper in `install.sh` (echoes
`pnpm|bun`, errs on absent/`npm@`/`yarn@`) plus a separate
`verify_package_manager_lockfile` corroboration step, mirrored by the
workflow's "Resolve package manager" step. Its D1 made
`package.json#packageManager` the single source of truth and **errored
when absent**, justified by "the setup action errors at runtime without
it". That justification is true for `pnpm/action-setup@v4` (no `version:`
input in our template, no built-in default) but false for
`oven-sh/setup-bun@v2`, which installs the latest Bun when no version
source exists. bun repos commonly omit `packageManager` (no Corepack), so
the constraint rejects valid adopters for a reason that does not apply to
the bun toolchain.

Constraints: zero behaviour change when `packageManager` is present;
verifier and runner must stay in lockstep; the workflow template stays
adopter-edit-free; failures stay closed and pre-mutation.

## Goals / Non-Goals

**Goals:**
- `packageManager` optional for an unambiguously-bun repo (lone
  `bun.lock`/`bun.lockb`, no `pnpm-lock.yaml`, no `packageManager`).
- pnpm still requires `packageManager`, with a pnpm-specific message
  stating the real reason.
- Fail closed on ambiguity (no field + both lockfiles) and keep
  rejecting `npm@`/`yarn@`/unparseable/no-package.json.
- Byte-for-byte unchanged behaviour whenever `packageManager` is present.
- Correct the inaccurate setup-bun rationale in spec + docs.

**Non-Goals:**
- npm/yarn support (still rejected, same message surface).
- Inferring a *pnpm* version from `pnpm-lock.yaml` so pnpm could also
  omit the field — `pnpm/action-setup@v4` genuinely needs the version;
  out of scope.
- Honouring `engines.bun` or `.bun-version` as additional signals.
- Auto-writing `packageManager` into an adopter's `package.json`.
- Any change when `packageManager` is present.

## Decisions

### D1: Precedence — declaration wins; lockfile fallback only when the field is absent

Resolution order:
1. `package.json#packageManager` present and `pnpm@`/`bun@` → use it,
   unchanged. The existing `verify_package_manager_lockfile` corroboration
   still runs (declared manager must have its matching lockfile).
2. `packageManager` present but `npm@`/`yarn@`/other → error (unchanged).
3. `packageManager` absent → lockfile-derived:
   - exactly `bun.lock` and/or `bun.lockb`, no `pnpm-lock.yaml` → **bun**
   - exactly `pnpm-lock.yaml`, no bun lockfile → **pnpm-needs-field
     error** (D2), not silent pnpm
   - both a bun and a pnpm lockfile → **ambiguous error**
   - neither → existing "missing field / package.json not found" error

Rationale: a *declared* manager is still authoritative, so a stale
foreign lockfile next to a declaration cannot mask it (case 1/2 never
consult lockfiles). The fallback is bun-only and triggers **only** on an
absent field, and the both-lockfiles case is rejected — so the only way a
lockfile decides anything is when there is exactly one and no
declaration, which is unambiguous by construction. This is the narrowest
relaxation of the prior D1 that unblocks real bun adopters.

### D2: pnpm without `packageManager` stays an error — but a pnpm-specific one

Even though `pnpm-lock.yaml` alone would let us *detect* pnpm, our
workflow runs `pnpm/action-setup@v4` with no `version:` input; it
resolves the version solely from `packageManager` and fails on the runner
without it. So detection without the field is useless for pnpm. The
message changes from the generic "missing the 'packageManager' field" to
a pnpm-specific one: pnpm-managed repos must declare
`packageManager: pnpm@<version>` because `pnpm/action-setup` has no
version default; bun repos may omit it. Alternative considered: add a
`version:` input or pin pnpm in the template — rejected as scope creep
that reintroduces the lockfile-vs-action version drift the prior change
deliberately avoided.

### D3: bun default version = whatever `oven-sh/setup-bun@v2` picks

When `packageManager` is absent we inject **no** bun version; the runner
lets `oven-sh/setup-bun@v2` default to latest. Rationale: mirrors the
action's native behaviour, keeps the template adopter-edit-free, and is
symmetric with an adopter who explicitly writes `bun@latest` (already
allowed). An adopter who wants a pinned bun simply declares the field —
the existing path.

### D4: One helper, internal fallback branch — not a resolver/detector split

`resolve_package_manager` keeps its `pnpm|bun`-on-stdout contract but,
on the absent-field branch, consults lockfile presence to decide.
`verify_package_manager_lockfile` still runs afterward; when resolution
came from the fallback it is trivially satisfied (we resolved *because*
the bun lockfile exists), which keeps the two functions consistent
without special-casing. Splitting into separate resolve/detect functions
was rejected: more surface, and `scripts/test-resolve-pm.sh` stays
simplest with one entry point.

### D5: Workflow mirrors `install.sh` byte-for-byte

The "Resolve package manager" step's shell gains the identical
precedence and the identical error strings (jq the field → on empty,
`test -f` the three lockfiles → same ambiguity / pnpm-needs-field
messages). No composite action (consistent with the prior change's D4);
the step stays copy-pasteable and diff-reviewable. Keeping the messages
identical to `install.sh` is a hard requirement so an adopter sees the
same text locally and in CI.

### D6: The false rationale must be removed, not just supplemented

`repo-adoption` and `docs/SETUP.md` currently assert
`oven-sh/setup-bun@v2` "errors at runtime" without `packageManager`.
That sentence is replaced (required-for-pnpm, optional-for-bun), not
merely appended to — leaving it would make the spec self-contradictory.

## Risks / Trade-offs

- **Reopens prior D1 (single source of truth)** → declaration always
  wins and never consults lockfiles; the fallback is bun-only +
  absent-field-only; both-lockfiles is rejected. Net: a lockfile can
  only ever decide when there is exactly one and zero declaration.
- **"latest bun" is non-deterministic across runs (D3)** → symmetric
  with the already-permitted `bun@latest`/`pnpm@latest`; adopters
  wanting determinism declare the field. No new failure mode versus
  today's explicit-`@latest`.
- **pnpm "detected but refused" may surprise (D2)** → the pnpm-specific
  message names the real reason (action has no version default) and the
  one-line fix (add the field), so it is actionable, not opaque.
- **Truth-table grows; risk of an untested branch** →
  `scripts/test-resolve-pm.sh` gains explicit cases for every new
  branch (bun-no-field ok, pnpm-no-field fails with the new message,
  both-lockfiles-no-field ambiguous); pure-local, no network.
- **Verifier/runner drift** → D5 mandates identical precedence and
  identical strings; the message text is asserted by the unit harness.

## Migration Plan

Additive and backward-compatible. Every repo that declares
`packageManager` resolves byte-for-byte as before. The only newly-
accepted shape is a bun repo with a lone bun lockfile and no
`packageManager`. No data, marker, or template-input migration. Rollback
is reverting the change; the only affected repos are those that adopted
purely via the new fallback (they would need to add
`packageManager: bun@<version>` back to keep working on the reverted
template) — a one-line fix, surfaced by the reverted error message.

## Open Questions

None. Honouring `engines.bun`/`.bun-version` as tertiary signals was
considered and deferred (Non-Goal): the two-level precedence
(declaration → lone bun lockfile) already removes the reported blocker
with the least ambiguity surface.
