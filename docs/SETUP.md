# Setting up remcc on a target repository

remcc adds an unattended `/opsx:apply` GitHub Actions workflow to a
repository that already uses OpenSpec. The fastest adoption is the
one-liner under "Automated adoption" below; the manual checklist that
follows it is preserved as a fallback for operators who prefer not to
pipe a remote script to bash. This document is the complete reference;
if you find yourself reaching for context that isn't here, that is a
documentation bug — please record what you needed and update this file
before continuing.

## Prerequisites

remcc v1 is intentionally narrow. Confirm every box below before
proceeding.

| # | Requirement | Verification command |
|---|---|---|
| 1 | An existing GitHub repository you have admin on | `gh repo view --json viewerPermission --jq .viewerPermission` should print `ADMIN` |
| 2 | A `main` branch on the remote | `git ls-remote --heads origin main \| grep main` |
| 3 | OpenSpec initialised in the repo | `test -d openspec && echo ok` |
| 4 | `.claude/` directory committed (skills/commands available to the runner) | `test -d .claude && echo ok` |
| 5 | **pnpm- or bun-managed JavaScript project with the matching committed lockfile at the repo root** (`pnpm-lock.yaml`, or `bun.lock`/`bun.lockb`) | `test -f pnpm-lock.yaml -o -f bun.lock -o -f bun.lockb && echo ok` |
| 5b | `packageManager` field in root `package.json` — **required for pnpm** (`pnpm@<version>`: `pnpm/action-setup@v4` has no `version:` input and no default, so it resolves the version solely from this field), **optional for bun** (`bun@<version>` when present is authoritative; when absent the committed `bun.lock`/`bun.lockb` alone selects bun and `oven-sh/setup-bun@v2` installs the latest Bun) | `jq -r .packageManager package.json` — must print `pnpm@<version>` for a pnpm repo; for a bun repo it may print `bun@<version>` or be absent (`null`) provided a `bun.lock`/`bun.lockb` is committed and no `pnpm-lock.yaml` is present |
| 6 | Local tools installed: `gh`, `jq`, `git`, Node.js ≥ 20.19, and your package manager (`pnpm` **or** `bun`) | `gh --version && jq --version && node -v && { pnpm -v || bun -v; }` |
| 7 | An Anthropic API key with budget configured | (key is uploaded as a repo secret in step 3 below) |
| 8 | A **remcc GitHub App** you control (created once, reused across all your adopter repos) with `Contents: write`, `Pull requests: write`, `Workflows: write`, `Metadata: read`, installed on the target repo, with a downloaded private-key PEM | See "Create the remcc GitHub App" below. (App ID, private key, and slug are uploaded in step 3 below.) |

> **Supports pnpm- or bun-managed repos only.** The workflow resolves the
> package manager from `package.json#packageManager` (authoritative when
> present) or, when that field is absent, from a lone `bun.lock`/`bun.lockb`,
> then runs `<pm> install --frozen-lockfile`. If your repository uses npm,
> yarn, or no JavaScript at all, remcc will fail. Generalising to other
> package managers is deferred to a future change; until then, please
> open an issue on the remcc repository describing your setup rather
> than working around the constraint locally.

## Create the remcc GitHub App

The `opsx-apply` workflow authenticates as a dedicated GitHub App, so
the pull request it opens is authored by `<app-slug>[bot]` — a distinct
GitHub actor from you. This lets you code-review and merge the bot's
PR without colliding with the default-branch approval ruleset ("the
author cannot approve their own PR").

You create the App **once**, under your personal account (or your
organisation), then install it on every adopter repository and reuse
the same credentials across them.

1. Open <https://github.com/settings/apps/new> (or your organisation's
   App settings page).
2. Fill in the form:
   - **GitHub App name:** any unique name, e.g. `remcc-<yourname>`.
     The lower-cased slug appears in PR-author attribution as
     `<slug>[bot]`.
   - **Homepage URL:** anything valid — `https://github.com/<you>` is
     fine.
   - **Webhook:** **uncheck "Active"**. remcc does not need webhooks;
     a deactivated webhook avoids spurious delivery failures.
3. Set **Repository permissions**:
   - **Contents:** `Read and write`
   - **Pull requests:** `Read and write`
   - **Workflows:** `Read and write`
   - **Metadata:** `Read-only` (selected automatically)
4. Leave **Organization permissions** and **Account permissions** at
   `No access`.
5. Under **Where can this GitHub App be installed?** choose
   `Only on this account`.
6. Click **Create GitHub App**.
7. On the resulting App settings page, note three values you'll need
   later:
   - The numeric **App ID** at the top of the page (`REMCC_APP_ID`).
   - The slug visible in the App URL `https://github.com/apps/<slug>`
     (`REMCC_APP_SLUG`).
8. Scroll to **Private keys** → **Generate a private key**. A `.pem`
   file downloads. Keep it secret — anyone with this file can act as
   the App on every repo it's installed on. (`REMCC_APP_PRIVATE_KEY`
   is the contents of this file.)
9. In the left sidebar, click **Install App**, then **Install** next
   to your account/organisation. Choose **Only select repositories**
   and select the adopter repo (you can add more later). Click
   **Install**.

That's the one-time setup. From now on, the same `REMCC_APP_ID`,
`REMCC_APP_PRIVATE_KEY`, and `REMCC_APP_SLUG` work for every adopter
repo you install the App on.

### Rotating the App private key

If a private key is lost or potentially exposed, regenerate it from
the App settings page (**Private keys → Generate a private key**),
re-run `install.sh reconfigure` against each affected adopter repo
to upload the new key, then **delete** the old key from the App
settings page. The App's installation tokens are short-lived (1 hour)
so the impact window is bounded even before rotation.

## Automated adoption (recommended)

From a clean clone of the target repository on `main`:

```sh
cd <target-repo-clone>
bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) init
```

The one-liner:

1. Re-verifies the prerequisites listed above and exits non-zero with a
   clear message on the first unmet check (no GitHub config is touched
   and no files are written before all checks pass).
2. Resolves a remcc ref — by default the latest release tag on
   `premeq/remcc`, overridable with `--ref <tag-or-sha>` — and
   shallow-clones the repo at that ref into a tempdir (auto-cleaned
   on exit).
3. Runs the cloned `templates/gh-bootstrap.sh` against the target
   (same idempotent GitHub-side configuration as Step 3 of the manual
   fallback below). Re-running `install.sh init` produces no diff.
4. Writes four template-managed files into the working tree,
   overwriting any pre-existing copies:
   - `.github/workflows/opsx-apply.yml`
   - `.claude/settings.json`
   - `openspec/config.yaml`
   - `.remcc/version` *(new — see schema below)*
5. Creates branch `remcc-init` from `main`, commits the four paths,
   pushes to `origin`, and opens a pull request titled
   `Adopt remcc via install.sh init`. The PR body lists every file
   written, explicitly flags any path that existed before the run
   ("you may have customizations here — verify the diff"), and includes
   a copy-pasteable smoke-test one-liner to run after merging.

If the resolved templates exactly match the current tree (a re-install
with no upstream changes), `install.sh init` prints `already up to
date` and exits zero without creating a branch or PR.

`install.sh init` does **not** trigger an `opsx-apply` run. The
operator's smoke test (from the PR body, after merging) is the
end-to-end verification.

### Inspect before running

The `bash <(curl …)` form executes the downloaded script directly. If
you prefer to read it first:

```sh
curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh -o install.sh
less install.sh
bash install.sh init
```

Both shapes work. The `curl … | bash -s -- init` shape also works —
interactive prompts inside the script read from `/dev/tty` so the
piped form does not hang.

### The `.remcc/version` marker

`install.sh init` writes `.remcc/version` recording the resolved
source ref. The file is JSON:

```json
{
  "source_ref": "v0.2.0",
  "source_sha": "abc123…",
  "installed_at": "2026-05-13T10:30:00Z"
}
```

- `source_ref` — the remcc tag or sha the templates were fetched
  from (default: the latest release tag, or `main` if no releases
  exist).
- `source_sha` — the commit `git clone --depth 1` landed on, used by
  the `upgrade` subcommand to compute the diff between installed and
  desired refs.
- `installed_at` — ISO 8601 UTC timestamp recording the date the
  operator first adopted remcc. **Preserved across upgrades**:
  `install.sh upgrade` reads the previous marker from
  `origin/main:.remcc/version` (or `origin/remcc-upgrade:.remcc/version`
  on re-run) and re-uses its `installed_at` value so the field always
  reflects first adoption, not most-recent refresh.

The marker is committed by `install.sh init` as part of the adoption
PR. Don't hand-edit it; treat it as the installer's bookmark.

## Upgrading remcc

Once a repository has been adopted via `install.sh init`, the
companion `install.sh upgrade` subcommand refreshes the same four
template-managed files at a newer remcc ref and opens a single PR
for review. From a clean clone of the target repository on `main`:

```sh
cd <target-repo-clone>
bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) upgrade
```

The one-liner:

1. Verifies `.remcc/version` exists on `origin/main`. If it does not,
   the command exits non-zero and points you at `install.sh init` —
   `upgrade` refuses to run on a never-adopted target.
2. Re-runs the same prerequisite checks as `init` (admin on target,
   OpenSpec initialised, pnpm- or bun-managed repo with a matching
   lockfile present, local tools).
3. Resolves a remcc ref — by default the latest release tag on
   `premeq/remcc`, overridable with `--ref <tag-or-sha>` — and
   shallow-clones the repo at that ref into a tempdir.
4. Overwrites the four template-managed files in the working tree
   with the new templates. `.remcc/version`'s `installed_at` field
   is preserved from the previously committed marker.
5. If the new templates exactly match what is already on
   `origin/main`, prints `already up to date` and exits zero
   without creating a branch or PR.
6. Otherwise, creates branch `remcc-upgrade` from `main`, commits
   the template diff, pushes (force-with-lease), and opens a PR
   titled `Upgrade remcc to <ref> via install.sh upgrade`. The PR
   body shows both endpoints (`<old_ref> (<old_sha>) → <new_ref>
   (<new_sha>)`), lists the files written, and flags any path whose
   pre-upgrade working-tree content diverged from the previous
   template (potential customization collision).

`install.sh upgrade` does **not** re-run `gh-bootstrap.sh`. Branch
protection, rulesets, secrets, and repository variables are one-time
`init` work. It also does not trigger an `opsx-apply` run — the
upgraded workflow takes effect on your next `change/**` push after
the upgrade PR merges.

Re-running `install.sh upgrade` while the upgrade PR is still open
updates the existing PR's branch tip via force-with-lease rather than
opening a duplicate.

### Upgrading from a remcc release before v0.3.0

remcc v0.3.0 replaced the per-operator `WORKFLOW_PAT` with a dedicated
GitHub App. The migration is a one-time, two-step process per
adopter repo. Before starting, complete the "Create the remcc GitHub
App" section above — you'll need the resulting App ID, private-key
PEM, and slug.

1. **Refresh the templates.** From a clean clone of the adopter on
   `main`:
   ```sh
   bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) upgrade --ref v0.3.0
   ```
   Review and merge the resulting `remcc-upgrade` PR. At this point
   the new workflow file is on `main` but it references App secrets
   that aren't installed yet — the next apply run would fail with a
   clear preflight error.
2. **Install the new App credentials.** From the same clone on `main`:
   ```sh
   REMCC_APP_ID=12345 \
   REMCC_APP_PRIVATE_KEY="$(cat path/to/remcc-app.private-key.pem)" \
   REMCC_APP_SLUG=remcc-yourname \
     bash <(curl -fsSL https://raw.githubusercontent.com/premeq/remcc/main/install.sh) reconfigure --ref v0.3.0
   ```
   `reconfigure` runs only the GitHub-side bootstrap — no working-tree
   writes, no branch, no PR. The bootstrap installs the three new
   config items and deletes the legacy `WORKFLOW_PAT` secret in the
   same run.
3. **Verify.** Push a `@change-apply` trigger commit on a `change/**`
   branch and watch the resulting `opsx-apply` PR open. Its
   `author.login` (visible in the GitHub UI and via
   `gh pr view --json author --jq .author.login`) should be
   `<your-app-slug>[bot]`. If it shows `github-actions[bot]` or your
   personal username, the migration didn't complete — re-run
   `install.sh reconfigure --ref v0.3.0`.
4. **Revoke the old PAT.** Open
   <https://github.com/settings/personal-access-tokens>, find the
   fine-grained token you previously used as `WORKFLOW_PAT`, and
   **Revoke** it. The new workflow no longer reads `WORKFLOW_PAT`
   from anywhere, and bootstrap has already removed the repository
   secret.

## Manual fallback

The remaining sections (Step 1 — Step 4) are the manual checklist that
`install.sh init` replaces. Use them if you cannot or will not pipe a
remote script to bash. The end-state is identical to the automated
path, with one exception: the manual path does not write a
`.remcc/version` marker, so a future `upgrade` won't know which
remcc ref you adopted.

## Step 1 — copy the template files

From a clone of the target repository, with this remcc repo also
cloned alongside, on a fresh feature branch:

```sh
# Adjust REMCC if your remcc clone is elsewhere.
REMCC=../remcc

git checkout main
git pull --ff-only
git checkout -b setup-remcc

mkdir -p .github/workflows
cp "${REMCC}/templates/workflows/opsx-apply.yml" .github/workflows/opsx-apply.yml
```

The `setup-remcc` branch is a regular feature branch — *not* a
`change/**` branch. The `change/**` namespace is the workflow's
trigger pattern (see "How to trigger a run" below); using it for
unrelated setup work would either spam apply runs (if your commit
subject accidentally matches `@change-apply`) or just be confusing.

### `.claude/settings.json` — merge, don't overwrite

The template at `templates/claude/settings.json` is intentionally
minimal: it carries no permissive `permissions.allow` entries. The
runner ignores `.claude/settings.json` because Claude Code is invoked
with `--dangerously-skip-permissions`; the file's only effect is on
local development.

- **No existing `.claude/settings.json` in the target repo:** copy
  the template directly:
  ```sh
  cp "${REMCC}/templates/claude/settings.json" .claude/settings.json
  ```
- **Existing `.claude/settings.json`:** keep your existing file. The
  remcc template adds no fields that your file does not already
  cover (an empty `permissions.allow`). If you want a record that
  remcc ran, leave the file untouched.

### `openspec/config.yaml` — runner-aware drafting hints (optional)

The template at `templates/openspec/config.yaml` carries a
commented-out "remcc baseline" block: a `context:` paragraph and a
`rules.tasks:` list that tell the OpenSpec drafting agents
(proposal / design / tasks) that the change will likely be applied
unattended on a GitHub Actions runner. The intent is to catch
runner-incompatible task shapes (manual browser checks, lingering
background processes, undeclared tool dependencies) at *drafting*
time rather than discovering them mid-apply on the runner.

This is opt-in. Adopters who sometimes apply changes locally may
want to prune individual rules; adopters who always apply via the
runner will likely want the whole block.

- **No existing `openspec/config.yaml` (you need to initialise
  OpenSpec anyway):** copy the template directly:
  ```sh
  cp "${REMCC}/templates/openspec/config.yaml" openspec/config.yaml
  ```
  Then open the file and uncomment the `context:` and `rules:`
  blocks under "remcc baseline".
- **Existing `openspec/config.yaml`:** open both files side-by-side
  and merge the `context:` paragraph and the `rules.tasks:` entries
  from the template's "remcc baseline" block into your existing
  keys (do not introduce duplicate top-level keys). If you already
  have project-specific entries under `rules.tasks:`, append the
  remcc rules below them.

The "Runner profile" section near the bottom of this document
enumerates the tooling the rules assume is preinstalled.

Commit and push the `setup-remcc` branch, then open a PR and merge
it to `main`:

```sh
git add .github/workflows/opsx-apply.yml .claude/settings.json openspec/config.yaml
git commit -m "Adopt remcc: workflow + Claude settings + drafting hints"
git push -u origin setup-remcc
gh pr create --base main --head setup-remcc --fill
gh pr merge --merge --delete-branch
```

The merge must happen *before* the smoke test, because the workflow
file needs to be on `main` for `change/**` branches forked from `main`
to inherit it.

## Step 2 — verify the workflow file at a glance

Open `.github/workflows/opsx-apply.yml` and confirm:

- It triggers on `push` to `change/**` only (no `workflow_dispatch`
  trigger surface).
- The job-level `if:` gates on the head-commit subject starting with
  `@change-apply`.
- `permissions:` block contains only `contents: write` and
  `pull-requests: write`.
- `timeout-minutes: 180`.
- `claude --dangerously-skip-permissions` is invoked.

You should not need to edit anything for a default adoption.

## Step 3 — configure GitHub-side controls

Run the bootstrap script from the root of the target repository:

```sh
bash "${REMCC}/templates/gh-bootstrap.sh"
```

The script:

1. Verifies `gh` is authenticated and you are inside a git repo.
2. Creates a single **branch ruleset** on the repository's
   **default branch only** that requires a pull request and at
   least one approval to merge and blocks force-push. Deletion of
   the default branch is not blocked by this ruleset. Admin
   bypasses, so you can still perform emergency merges. The
   ruleset is named `remcc: require approval on main` and applies
   identically to user-owned and organization-owned repos. The
   script installs no other ref-level or path-level controls —
   your PR review is the single gate keeping agent output off the
   default branch.
3. Enables **secret scanning + secret push protection**, **if the
   feature is available** for the target repo. Public repos get it
   for free; private repos require GitHub Advanced Security. On
   private repos without GHAS, the script prints a warning and
   continues. The remaining secret-leak protection is GitHub
   Actions log redaction (built into Actions, no setup required).
4. Prompts for `ANTHROPIC_API_KEY` (input hidden) and uploads it as
   the repository secret. If the variable is already set in your
   shell, the script picks it up and does not prompt.
5. Prompts for `REMCC_APP_ID` and `REMCC_APP_PRIVATE_KEY` (input
   hidden) and uploads each as a repository secret. The workflow
   exchanges these for a short-lived GitHub App installation token
   at the start of every run, and uses that token for checkout,
   push, and PR creation — so the bot's PR author is the App,
   not you. See "Create the remcc GitHub App" above for how to
   produce these values. If both variables are already set in
   your shell (PEM via `REMCC_APP_PRIVATE_KEY="$(cat key.pem)"`),
   the script picks them up and does not prompt.
6. Prompts for `REMCC_APP_SLUG` (input visible — the slug is not
   secret) and writes it as a repository **variable** (not a
   secret). The workflow constructs the bot's commit identity
   from this slug. Empty input is a hard error. If the variable
   is already set in your shell, the script picks it up.
7. If a legacy `WORKFLOW_PAT` secret is present (from a previous
   remcc release), it is deleted now that the App credentials are
   in place. Re-running the script when `WORKFLOW_PAT` is already
   gone is a no-op.
8. Prompts for `OPSX_APPLY_MODEL` and `OPSX_APPLY_EFFORT` — the
   per-repo defaults for the `/opsx:apply` step. Empty input
   leaves the variable unset, in which case the workflow's
   baked-in defaults (`sonnet` / `high`) apply. The script reads
   `OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT` from the environment
   if set, so the prompts can be skipped in scripted runs. See
   "Configuring the apply model" below for what these knobs do.
9. Runs an idempotency smoke test: re-applies every change and
   diffs the resulting state. A diff is a bug — please report it.

Re-running the script later is a no-op.

> **What this means for private-without-GHAS targets.** The model
> loses one outside-the-runner control on these targets (secret
> scanning). Secret-shaped commits are not blocked at push time,
> only redacted from logs — documented in `SECURITY.md`. The
> default-branch approval ruleset still applies; the bot still
> cannot land on the default branch without your review.

### Opting in from a prior-version adopter

If your repo was bootstrapped under a previous remcc release, it
carries legacy GitHub-side controls that this version of
`gh-bootstrap.sh` **does not modify or remove**: branch protection
on `main` (legacy `branches/main/protection` endpoint), a ruleset
named `remcc: restrict bot to change branches`, and (on org-owned
repos) a ruleset named `remcc: block bot edits under .github`.

Re-running the updated bootstrap on such a repo adds the new
`remcc: require approval on main` ruleset alongside the legacy
items — the resulting state is strictly more restrictive than the
new default, but untidy. To converge to the new single-ruleset
model:

1. Open GitHub → Settings → Rules → Rulesets and delete
   `remcc: restrict bot to change branches` and (if present)
   `remcc: block bot edits under .github`.
2. Open GitHub → Settings → Branches and remove protection on the
   `main` branch.
3. Re-run `gh-bootstrap.sh`. It reconciles the new ruleset and
   the idempotency smoke test passes with no diff.

This is a one-time manual opt-in. Skipping it leaves your repo
with both old and new controls in place; that's a supported state
(strictly safer), just not the new default.

### If a step fails

- **"gh is not authenticated"**: run `gh auth login` and retry.
- **403 errors from `gh api`**: you are not admin on the target repo.
  Ask the owner to grant admin or run the script themselves.
- **422 errors not handled by the script's warnings**: GitHub
  occasionally adds new constraints. Capture the full error and
  open an issue on the remcc repo before working around it locally.

## How to trigger a run

A push to a `change/**` branch on its own does **not** run apply.
The workflow's listener fires on every such push, but the job is
gated by a single rule: it runs only when the head commit's
subject (the first line of its message) starts with the byte
sequence `@change-apply`. Pushes that don't match are a silent
no-op — no runner is provisioned, no Anthropic tokens are spent,
no PR comment is posted.

This is the opt-in trigger. Authors can freely push WIP scaffolding,
proposal edits, and co-author collaboration commits to a `change/**`
branch without burning apply runs; the agent only goes when the
author explicitly asks.

### The canonical trigger commit

```sh
git commit --allow-empty -m "@change-apply: first pass"
git push
```

An empty commit carries the "go" signal without bundling a noise
edit. The agent picks up the current state of the branch (your
prior WIP commits) and applies it. The workflow doesn't parse what
follows `@change-apply` — that text is free-form context for
humans reading `git log`.

### Acceptable subject shapes

All of these trigger apply:

- `@change-apply: first pass` — conventional-commits shape
  (recommended).
- `@change-apply(retry with opus)` — parens shape.
- `@change-apply retry after task 3` — space-separator shape.
- `@change-apply` — bare, no description.

Near-miss subjects do **not** trigger an apply:

- `change-apply: retry` — missing `@`. Skipped at the job-level
  `if:`; no runner provisioned.
- `@change_apply: retry` — underscore instead of hyphen. Skipped
  at the job-level `if:`.
- ` @change-apply: retry` — leading whitespace. Skipped at the
  job-level `if:`.
- `@Change-Apply: retry` — capitalised. The job-level `if:`
  evaluates true (GitHub Actions' `startsWith()` is
  case-insensitive), but a case-sensitive shell guard step
  immediately fails the run and skips the apply step. Cost: ~20s
  of runner time, no Anthropic spend, no PR comment.

The match is case-sensitive and byte-exact at position 0 of the
subject. The `@`-prefix makes accidental triggers effectively
impossible — natural commit subjects don't start with `@` — and
pairs visually with the `change/<name>` branch convention (both
refer to "the change").

### Iterating on a change

The typical loop:

1. Push a `change/<name>` branch with a draft proposal. No apply
   runs yet.
2. Push more WIP commits — collaborator edits, task refinements,
   spec polish. Still no apply runs.
3. When ready, write the trigger commit: `git commit --allow-empty
   -m "@change-apply: first pass"` and push. The agent runs; a PR
   is opened.
4. Review the PR. If you want another pass, push more WIP if
   needed, then write another trigger commit (e.g.
   `@change-apply: retry with feedback`) and push.

Every apply run requires its own trigger commit. There is no
"re-apply on every commit until done" mode by design — the
author owns the moment.

### Trigger commit without a terminal

The workflow doesn't care how the commit was authored. If you're
locked out of your terminal, you can author a trigger commit
through the GitHub web UI's file-edit flow: make a tiny edit
(adding or removing a blank line is enough), and set the commit
subject to `@change-apply: <reason>`.

### Wrong branch is a no-op

Pushing a `@change-apply...` commit to a branch that doesn't match
`change/**` does nothing. The push trigger's branch filter still
applies — the workflow's listener doesn't fire at all on `main` or
other branches.

### Self-loop prevention

After a successful apply run, the bot pushes its output commit
with subject `/opsx:apply <name>`. That subject does not start
with `@change-apply`, so the bot's own push does not re-trigger
the workflow. This is implicit — no separate self-loop guard.

The bot's push and any WIP push the author makes during an
in-flight apply land in a separate `noop` partition of the
workflow's concurrency group, so they never cancel a real apply
run. `cancel-in-progress: true` still applies within the `apply`
partition, so a fresh `@change-apply: retry` pushed while a prior
apply is in flight correctly cancels the stale run.

## Configuring the apply model

The `/opsx:apply` step is invoked with an explicit `--model` and
`--effort` (Claude Code's thinking-budget level). Both are
configurable per repo and per run.

### Repository-variable defaults

| Variable | Purpose | Accepted values | Default if unset |
|---|---|---|---|
| `OPSX_APPLY_MODEL` | Claude model alias passed to `claude --model` | `opus`, `sonnet`, `haiku`, or any full model id the CLI accepts | `sonnet` |
| `OPSX_APPLY_EFFORT` | Claude Code thinking-budget level | `low`, `medium`, `high` | `high` |

`gh-bootstrap.sh` prompts for these during install. To change them
later without re-running the script:

```sh
gh variable set OPSX_APPLY_MODEL --body opus
gh variable set OPSX_APPLY_EFFORT --body medium
```

To revert to the baked-in default, delete the variable:

```sh
gh variable delete OPSX_APPLY_MODEL
```

The two variables resolve independently — leaving `OPSX_APPLY_EFFORT`
unset while setting `OPSX_APPLY_MODEL` is fine.

### Per-run override precedence

The workflow resolves `model` and `effort` independently for every
run with this precedence (highest first):

1. Commit trailer on the head commit (`Opsx-Model:` / `Opsx-Effort:`)
2. Repository variable (`OPSX_APPLY_MODEL` / `OPSX_APPLY_EFFORT`)
3. Baked-in default (`sonnet` for model, `high` for effort)

#### Commit-trailer override

Add a trailer to the trigger commit on the change branch. The
canonical idiom uses an empty commit with the `@change-apply`
subject (see "How to trigger a run" below) plus a trailer block:

```sh
git commit --allow-empty -m "$(cat <<'EOF'
@change-apply: retry with opus

Opsx-Model: opus
Opsx-Effort: low
EOF
)"
git push
```

Trailer parsing uses `git interpret-trailers`, so standard Git
trailer rules apply: a blank line before the trailer block,
`Token: value` per line, token matching is case-insensitive.

### Resolved values are reported in the PR

The workflow records the resolved `model` and `effort` (and the
source each came from) in the body of any PR it opens and in any
comment it posts on a re-run. That PR body is the source of truth
for "what did this run actually use?" — there is no need to dig
through the Actions logs.

### Forked PRs

Repository variables are not exposed to workflow runs originating
from forked PRs. The `opsx-apply` workflow only triggers on `push`
to `change/**`, which is a privileged event on the main repo, so
the fork-PR exposure path does not apply to remcc in practice.

## Runner profile

The `opsx-apply` workflow runs on GitHub-hosted `ubuntu-latest`.
The drafting hints in `templates/openspec/config.yaml` tell the
OpenSpec agents to assume the tooling listed here is available
without further setup; anything else must be installed by the
task itself.

### Provided by the workflow

| Tool | Source | Notes |
|---|---|---|
| Node.js 20 | `actions/setup-node@v4` | Pinned by the workflow; do not assume the ubuntu-latest default Node version |
| Package manager (pnpm or bun) | `pnpm/action-setup@v4` or `oven-sh/setup-bun@v2` | A "Resolve package manager" step applies the same precedence as `install.sh`: a declared `package.json#packageManager` (e.g. `pnpm@9.12.3` or `bun@1.1.34`) is authoritative; if it is absent, a lone `bun.lock`/`bun.lockb` selects bun. It then runs only the matching setup action, then `<pm> install --frozen-lockfile`. `pnpm/action-setup@v4` has no version default, so pnpm repos **must** declare the field (prereq 5b); `oven-sh/setup-bun@v2` needs no version source and installs the latest Bun, so the field is optional for bun |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` | Invoked with `--dangerously-skip-permissions` |
| OpenSpec CLI | `npm install -g @fission-ai/openspec@latest` | Used for the post-apply validate step |
| `ANTHROPIC_API_KEY` | Repo secret, exposed as env | Set by `gh-bootstrap.sh`; redacted from logs by GitHub |
| `REMCC_APP_ID` | Repo secret, consumed by `actions/create-github-app-token` | Numeric GitHub App ID; set by `gh-bootstrap.sh` |
| `REMCC_APP_PRIVATE_KEY` | Repo secret, consumed by `actions/create-github-app-token` | PEM-encoded private key of the remcc GitHub App; set by `gh-bootstrap.sh` |
| `REMCC_APP_SLUG` | Repo **variable**, used to construct the bot's git identity | App slug (the `<slug>` in `github.com/apps/<slug>`); set by `gh-bootstrap.sh` |

### Provided by the `ubuntu-latest` image

The drafting hints assume the standard tools that GitHub bundles
into `ubuntu-latest`. The ones most likely to come up in tasks:

| Tool | Notes |
|---|---|
| Docker Engine + Compose v2 | `docker`, `docker compose` (no separate `docker-compose` v1) |
| `git`, `gh` | `gh` is pre-authenticated to the run's `GITHUB_TOKEN` for the same repo |
| `curl`, `wget`, `jq` | Use these for headless verification |
| `bash`, `sh` | Default shell for `run:` steps is `bash -e` |
| Postgres / MySQL clients | `psql`, `mysql` are present; the *servers* are not running by default |
| Python 3, build tools (`gcc`, `make`) | Useful for one-off scripts and native deps |

The full image manifest changes over time; the canonical reference
is GitHub's
[`runner-images`](https://github.com/actions/runner-images)
repository (`images/ubuntu/Ubuntu2404-Readme.md` for `ubuntu-latest`).
If you find yourself relying on something not listed in either
table above, install it explicitly in the relevant task — do not
assume future-you (or future-runner) will have it.

### What the runner does *not* provide

Worth calling out because tasks frequently assume them:

- No GUI / browser. Verification must use HTTP, exec, or log inspection.
- No long-lived state across runs. Every apply starts from a fresh checkout
  with cold Docker / package-manager caches unless the workflow opts into caching.
- No cloud credentials beyond what you've explicitly added as repo secrets.
- No interactive TTY. Commands that read from stdin or block on a prompt
  will hang the run until the 180-minute job timeout.

## Step 4 — smoke test

Push a trivial change branch to verify the full path runs end to end.

1. Create an OpenSpec change directory at `openspec/changes/test-apply/`
   with at minimum: `proposal.md`, `tasks.md`, and any specs/design
   that `openspec validate test-apply` requires for your project's
   schema. The trivial-task pattern works well — one task that
   creates a single small file is enough to exercise the path. Land
   this on `main` via the same feature-branch + PR flow you used in
   step 1, or as admin via direct push (you will see a
   `remote: Bypassed rule violations for refs/heads/main` message
   in the output — that is GitHub recording your admin bypass and
   is expected).
2. Create and push the change branch (no apply run yet — the
   branch push does not carry a trigger subject):
   ```sh
   git checkout main
   git pull --ff-only
   git checkout -b change/test-apply
   git push -u origin change/test-apply
   ```
   Open the Actions tab and confirm **no** workflow run was started.
3. Push the trigger commit to ask the agent to run:
   ```sh
   git commit --allow-empty -m "@change-apply: smoke test"
   git push
   ```
4. Within a few seconds, the `opsx-apply` workflow run should appear
   under the repo's Actions tab. Watch the run and confirm:
   - The workflow trigger fires and the job is not skipped.
   - Claude Code runs to completion (apply step exits, exit code is
     captured to a step output).
   - `openspec validate test-apply` runs and passes.
   - A pull request to `main` is opened from `change/test-apply`.
   - Workflow logs are uploaded as artifact `agent-logs-test-apply`.
   - The bot's output push (subject `/opsx:apply test-apply`) does
     **not** re-trigger the workflow — confirm by refreshing the
     Actions tab and seeing no second run start.
5. Close the PR without merging and delete the `change/test-apply`
   branch. The smoke test is over.

If any step is observed to require manual intervention, that is a
documentation bug. Capture what you had to do and patch SETUP.md.

## Removing remcc

remcc is reversible. To remove it from a target repository:

1. **GitHub-side configuration** — run the bootstrap script with
   `--uninstall`:
   ```sh
   bash "${REMCC}/templates/gh-bootstrap.sh" --uninstall
   ```
   This deletes the `remcc: require approval on main` ruleset,
   disables secret scanning + push protection (where applicable),
   and deletes the `ANTHROPIC_API_KEY`, `REMCC_APP_ID`, and
   `REMCC_APP_PRIVATE_KEY` repository secrets and the
   `REMCC_APP_SLUG` repository variable.
   (Any pre-existing legacy `WORKFLOW_PAT` secret is also removed.)
   It does not touch any files in your repository, and it does not
   delete the GitHub App itself or revoke its private key — manage
   those at <https://github.com/settings/apps>.

   **Note for prior-version adopters:** `--uninstall` removes only
   what this version of the script manages. If your repo still
   carries legacy GitHub-side controls from an earlier remcc
   release — branch protection on `main`, a ruleset named
   `remcc: restrict bot to change branches`, or a ruleset named
   `remcc: block bot edits under .github` — those are **not**
   removed. Delete them manually in GitHub → Settings → Branches
   and Settings → Rules → Rulesets.
2. **Workflow file** — delete it from the repository:
   ```sh
   git rm .github/workflows/opsx-apply.yml
   ```
3. **Claude settings template** — if you copied
   `templates/claude/settings.json`, leave it; it is harmless and
   contains no remcc-specific configuration. If you did not have
   one before, you can delete it: `git rm .claude/settings.json`.
4. **OpenSpec drafting hints** — if you merged the "remcc baseline"
   block into `openspec/config.yaml`, delete those lines (the
   `context:` paragraph and `rules.tasks:` entries that reference
   the GitHub Actions runner). The rest of the file is your own
   project configuration; leave it alone.
5. Commit and push the workflow removal on a regular feature
   branch and merge via PR.

After these steps, no remcc-specific configuration remains on the
target repository.
