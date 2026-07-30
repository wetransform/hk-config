# Design: Publish the Pkl package as a release asset via semantic-release

**Date:** 2026-07-30
**Status:** Approved (design)
**Supersedes:** the tag-triggered publish path from
`2026-07-30-pkl-package-distribution-design.md` (the `PklProject`, the
`package://` consumer URI, and the multi-OS test setup from that design all
remain in force — only the _how the archive reaches the release_ part changes).

## Problem

hk-config currently attaches its Pkl package to a GitHub Release from a
**tag-triggered** `mise-publish` job (`ci:publish` →
`scripts/publish-pkl-package.sh` → `gh release upload`). Two structural
weaknesses surfaced on the first real release (`v2.4.0`):

1. **Incompatible with immutable releases.** GitHub immutable releases (GA
   2025-10) forbid adding assets to an already-published release; assets must
   be present when the release is published. A separate post-publish upload
   job cannot produce an immutable release with the package attached.
2. **Token fragility.** The `mise-publish` job only exposes `GH_PAT` to the
   task; when that secret is absent the script exports an empty `GH_TOKEN`,
   which makes `gh` fail auth. On `v2.4.0` this aborted the upload (the release
   was created with zero assets; it has since been backfilled manually).

## Goal

Attach the package archive to the release **at creation time**, via
`@semantic-release/github`'s `assets` option, inside the managed
`gha-workflows/mise-release.yml`. This yields immutable-release compatibility
and reuses the release job's existing GitHub App token (`WE_RELEASE_GITHUB_APP_ID`,
already `contents: write`) — no separate token plumbing.

Why this is compatible with immutable releases: `@semantic-release/github`'s
publish step, when `assets` are configured, already does exactly GitHub's
recommended immutable-release sequence — **create the release as a draft →
upload assets → PATCH `draft: false`** (confirmed in the plugin's
`lib/publish.js`). So all assets are present at the moment of publication.

## Non-goals

- Not changing the `PklProject`, the `package://` consumer URI form, or the
  multi-OS `test-steps.yml` — those stay as designed.
- Not enabling immutable releases itself — that is a repo/org admin setting
  (see "Enabling immutability" below), separate from this workflow change.
- Not making the template pkl-aware — the template extension is generic.

## Design

### 1. Shared template change — `gha-workflows/mise-release.yml`

The single template change: the generated `.releaserc.yml` gives
`@semantic-release/github` an `assets` block, sourced from the consuming repo's
`.wetf-ci.yml`, mirroring the existing `test.report-paths` extraction pattern.

- Read the globs (empty if the file or key is absent):
  ```bash
  RELEASE_ASSETS=""
  if [ -f .wetf-ci.yml ]; then
    RELEASE_ASSETS=$(yq e '.release.assets // [] | .[].path' .wetf-ci.yml)
  fi
  ```
- When non-empty, the final plugin entry changes from the bare
  `- "@semantic-release/github"` to the object form:
  ```yaml
  - - "@semantic-release/github"
    - assets:
        - path: <glob 1>
        - path: <glob 2>
  ```
- When empty, the entry stays byte-for-byte as today.

Properties:

- **Backward compatible.** A repo with no `release.assets` sees no change.
- **Variant-agnostic.** Works for both the `npm` and default variants; the
  `assets` come from `.wetf-ci.yml` regardless of variant.
- **No build logic in the template.** Building the assets is the repo's
  responsibility, via the `prepareCmd` hook the template already runs
  (`ci:set-version` for the default variant).
- Honors the existing "only generate `.releaserc.yml` if none present" guard —
  the injection happens inside that generation, so a repo that commits its own
  `.releaserc.yml` still overrides everything.

### 2. hk-config changes

- **`ci:set-version` becomes the build** (was a no-op). It receives
  `--version <v>` (the template passes `${nextRelease.version}`) and runs
  `VERSION=<v> pkl project package`. For pkl this is the natural meaning of
  "set the version": there is no version field in a file to bump — the version
  only materializes as the stamped archive under `.out/hk-config@<v>/`.
- **`.wetf-ci.yml`** gains:
  ```yaml
  release:
    assets:
      - path: .out/hk-config@*/hk-config@*
  ```
  This one glob matches all four produced files: the metadata
  `hk-config@<v>`, `hk-config@<v>.sha256`, `hk-config@<v>.zip`, and
  `hk-config@<v>.zip.sha256`.
- **Retire the tag-triggered path:** delete `scripts/publish-pkl-package.sh`
  and make `ci:publish` a no-op. The `workflows-default` preset still generates
  a `tf-publish` that invokes `ci:publish`, but there is nothing to publish on
  tag push anymore, so the task simply reports and exits 0.
- **`ci:verify-release` stays** as the pre-tag build sanity check
  (`pkl project package` with the snapshot version), so a broken package fails
  the release before a tag is cut.

### 3. Ordering & data flow (correctness)

semantic-release lifecycle: `verifyRelease` (→ `ci:verify-release` build check)
→ `prepare` → `publish`.

In `prepare`, plugin order is: changelog → exec → git. So
`exec.prepareCmd` (`ci:set-version` → `pkl project package`) writes
`.out/hk-config@<v>/…` **before** `git` commits — and `git` commits only
`CHANGELOG.md`, while `.out/` is git-ignored, so build output is never
committed.

In `publish`, `@semantic-release/github` globs
`.out/hk-config@*/hk-config@*`, creates the draft release, uploads the four
assets, and patches it to published. Assets therefore exist before upload, and
the release is published with them present (immutable-safe).

### 4. Enabling immutability (ops)

This workflow change makes immutable releases _possible_; realizing them
requires enabling **immutable releases** in the repo/org settings — an admin
toggle, not something the workflow performs. Recommended: enable it, then
verify on the first release that the release is marked immutable and carries a
signed attestation. Until enabled, releases publish normally (mutable) with the
assets attached — so the change is safe to ship before the toggle is flipped.

### 5. Testing / rollout

- **Template:** validate by generating `.releaserc.yml` both with and without a
  `.wetf-ci.yml release.assets` present, and confirming the `assets:` block
  appears / is absent accordingly and the YAML is valid.
- **hk-config (local):** `mise run ci:set-version --version 2.4.1` produces the
  four `.out/hk-config@2.4.1/…` files; `mise run ci:verify-release` still
  builds; `mise run ci:publish` is a clean no-op.
- **End-to-end:** the first real release after the change (e.g. `v2.4.1`) is the
  proof — the release carries the four assets, was created via
  draft→upload→publish, and (if immutability is enabled) is immutable with an
  attestation. A clean-cache `pkl eval` of a consumer amending
  `package://…/v2.4.1/hk-config@2.4.1#/configs/Default.pkl` resolves.
- `v2.4.0` is already backfilled, so consumers are unbroken during rollout.

## Risks / open items

- **`gha-workflows` delivery.** That repo is not part of this checkout; the
  template change ships as a separate PR against it. Both changes should land
  close together, but the template change is backward compatible, and hk-config
  can merge first (its `ci:set-version`/`.wetf-ci.yml` are inert until the
  template reads them, and `v2.4.0` already works), so ordering is not fragile.
- **Immutable-release finalization on the plugin's PATCH.** GitHub's
  recommended flow is draft→attach→publish, which the plugin does; confirm on
  the first release that the `PATCH draft:false` finalizes immutability +
  attestation as expected.
- **`tf-publish` vestige.** `ci:publish` no-op leaves a `tf-publish` job that
  does nothing for hk-config; acceptable. If the preset system later allows
  opting out of the publish workflow for this repo, that is a tidy-up, not a
  requirement.
