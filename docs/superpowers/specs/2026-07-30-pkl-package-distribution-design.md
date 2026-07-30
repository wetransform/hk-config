# Design: Distribute hk-config as a Pkl package

**Date:** 2026-07-30
**Status:** Approved (design)

## Problem

Consumers of hk-config reference its Pkl files via raw GitHub URLs, e.g.:

```pkl
amends "https://raw.githubusercontent.com/wetransform/hk-config/refs/tags/<tag>/configs/Default.pkl"
```

`raw.githubusercontent.com` applies aggressive rate limiting to unauthenticated
requests. Because `pkl` resolves each imported module over the network, repos
with several imports — or CI runners sharing an IP — hit the limit and hook
setup fails intermittently.

## Goal

Publish hk-config as a **Pkl package** attached to each GitHub Release, so
consumers reference it via a `package://` URI whose archive is downloaded from
GitHub's release CDN (not the rate-limited raw API):

```pkl
amends "package://github.com/wetransform/hk-config/releases/download/v2.4.0/hk-config@2.4.0#/configs/Default.pkl"
```

This is the exact mechanism this repo already uses to consume hk (see
`Config.pkl`, `Builtins.pkl`), and mirrors how the hk project publishes itself.

## Non-goals

- **Not** migrating PR checks to the managed mise workflow. `test-steps.yml`
  stays as-is to preserve multi-OS (ubuntu/macOS/Windows) step-test coverage,
  which is central to a repo about cross-platform tool behaviour.
- **Not** backfilling packages for already-released tags. Only releases from
  this change onward carry an archive; older tags keep working via raw URLs.
- **Not** registering on `pkg.pkl-lang.org`. The direct GitHub-release URL form
  is self-contained and adds no third-party service to the resolution path.

## Design

### 1. `PklProject` (new file)

A package definition modelled on hk's, using the direct GitHub-release URI form:

```pkl
amends "pkl:Project"

package {
  name = "hk-config"
  authors { "wetransform GmbH" }
  version = read?("env:VERSION")?.replaceFirst("\(name)@", "") ?? "0.0.1-SNAPSHOT"
  baseUri = "package://github.com/wetransform/hk-config/releases/download/v\(version)/hk-config"
  packageZipUrl = "https://github.com/wetransform/hk-config/releases/download/v\(version)/\(name)@\(version).zip"
  sourceCode = "https://github.com/wetransform/hk-config"
  license = "MIT"
  description = "Shared hk (git hooks) configuration for wetransform repositories"
  exclude { /* dev-only files — see below */ }
}
```

- **Version** comes from the `VERSION` environment variable at build time, with a
  `0.0.1-SNAPSHOT` fallback so `pkl project package` runs locally without a tag.
- **Archive contents (shipped to consumers):** `Config.pkl`, `Builtins.pkl`,
  `Shared.pkl`, `Model.pkl`, `Functions.pkl`, `configs/**`, `steps/**`.
- **Excluded (dev-only):** `hk.pkl`, `hk-test-all.pkl`, `test*.sh`,
  `.github/**`, `mise.toml`, `.wetf-*.yml`, `.idea/**`, `docs/**`, dotfiles,
  `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `LICENSE` (already implied by pkl's
  defaults, but stated explicitly). The exact glob list is finalised in
  implementation to produce exactly the shipped set above.
- **hk dependency:** `Config.pkl`/`Builtins.pkl` reference hk by a full absolute
  `package://…jdx/hk…` URI, which resolves without a `dependencies {}` block.
  Verify `pkl project package` resolves it cleanly during implementation.

The internal import graph is already fully relative (verified), so all shipped
modules resolve within the archive; only the hk reference is external.

### 2. `mise.toml` — `ci:*` tasks

The managed mise release/publish workflows call three tasks by convention:

- **`ci:verify-release`** — run by `mise-release` before tagging
  (`verifyReleaseCmd`). Runs `pkl project package` with the snapshot version to
  prove the archive builds before a tag is cut. (The template does not pass the
  next version to this command, so it builds `0.0.1-SNAPSHOT` — sufficient as a
  build check.)
- **`ci:set-version`** — required by the non-npm release variant
  (`prepareCmd: mise run ci:set-version --version <v>`). **No-op:** pkl reads its
  version from `env:VERSION` at build time, so there is no file to bump. The task
  accepts and ignores `--version`.
- **`ci:publish`** — run by `mise-publish`. Builds
  `VERSION=$PUBLISH_VERSION pkl project package`, then uploads the three
  resulting assets (`hk-config@<v>`, `hk-config@<v>.zip`,
  `hk-config@<v>.zip.sha256`) to release `v$PUBLISH_VERSION` via
  `gh release upload … --clobber`.

**`ci:publish` details:**

- **Tag-only guard.** `mise-publish` also fires on the master push (with
  `PUBLISH_VERSION=latest`). `ci:publish` must **no-op unless `PUBLISH_VERSION`
  is a real semver** (`^[0-9]+\.[0-9]+\.[0-9]+`), so packages are published only
  on tag builds.
- **Release-creation race.** The tag push can trigger `mise-publish` a few
  seconds before semantic-release's github plugin finishes creating the release.
  Wrap the upload in a short retry / "view-or-create" so it tolerates the
  release not yet existing.
- **Token scope.** `gh release upload` needs a token with `contents: write`.
  Confirm the token inherited by `mise-publish` (`GITHUB_TOKEN` / `GH_PAT`) has
  write scope; if not, arrange one (flag during implementation).

### 3. Wiring the managed workflows

Update `.wetf-repo.yml` presets from `renovate` + `repo-release` to the
mise-based set (`mise` + `workflows-default`, **default variant — not `npm`**).
The central repo-management tooling regenerates the `tf-*.yml` managed workflows
from these presets (confirmed mechanism). This replaces the old `repo-release`
`tf-release` with the mise `tf-release` + `tf-publish`.

`test-steps.yml` is a custom (non-managed) workflow and stays untouched.

**To confirm during implementation:** whether `workflows-default` also
generates a `tf-check` (mise-check, ubuntu-only). If it does, decide what
`ci:check` should do (e.g. a lightweight `pkl project package` + config eval) or
whether to opt out, since multi-OS checks remain in `test-steps.yml`. Update
`required_checks` in `.wetf-repo.yml` to match the resulting check job names.

### 4. Docs

- **README:** present the `package://…releases/download/…` form as the
  recommended way to pin a **released version**. Keep the raw-URL form,
  documented as the option for referencing a **branch or specific commit** (e.g.
  testing changes before a release) — only tagged releases carry a package
  archive.
- **CLAUDE.md:** fix the stale
  `package://pkg.pkl-lang.org/github.com/wetransform-os/hk-config@2.2.0#/…` line
  to the actual direct-GitHub form with the correct org (`wetransform`).

## Release flow (end to end)

1. Maintainer dispatches the managed **Release** workflow (`mise-release`).
2. semantic-release runs `ci:verify-release` (package builds), computes the next
   version, runs `ci:set-version` (no-op), commits `CHANGELOG.md`, pushes tag
   `vX.Y.Z`, and creates the GitHub Release.
3. The tag push triggers the managed **Publish** workflow (`mise-publish`), which
   runs `ci:publish`: builds the package with `VERSION=X.Y.Z` and uploads the
   archive + metadata + checksum to release `vX.Y.Z`.
4. Consumers reference
   `package://github.com/wetransform/hk-config/releases/download/vX.Y.Z/hk-config@X.Y.Z#/configs/Default.pkl`.

## Risks / open items

- **Token scope** for `ci:publish` uploads (`contents: write`) — confirm.
- **Release-creation race** in `ci:publish` — mitigated by retry/view-or-create.
- **`tf-check` generation** by `workflows-default` — confirm and decide
  `ci:check` behaviour or opt-out.
- **hk absolute-URI resolution** during `pkl project package` — verify no
  `dependencies {}` block is required.
