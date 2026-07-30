# Pkl Package Release-Asset Publishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attach the hk-config Pkl package to its GitHub Release at creation time via `@semantic-release/github`'s `assets` option, replacing the tag-triggered `gh release upload` path — enabling immutable releases and reusing the release App token.

**Architecture:** Extend the shared `gha-workflows/mise-release.yml` so the generated `.releaserc.yml` gives `@semantic-release/github` an `assets` block sourced from the consuming repo's `.wetf-ci.yml` (`release.assets`). hk-config builds the versioned package during `prepareCmd` (`ci:set-version`) and declares the asset glob in `.wetf-ci.yml`; the old tag-triggered publish script is removed.

**Tech Stack:** GitHub Actions (wetransform `gha-workflows` reusable workflows), semantic-release + `@semantic-release/github`/`exec`, mise, Pkl 0.32.1, `yq` (mikefarah, preinstalled on ubuntu-latest), `gh`.

**Two repositories are touched:**

- `../gha-workflows` (checkout at `/home/simon/repos/wetf/gha-workflows`) — Task 1.
- `hk-config` (`/home/simon/repos/wetf/hk-config`) — Tasks 2–3.

## Global Constraints

- **Backward compatibility (template):** a repo with no `.wetf-ci.yml` `release.assets` MUST get a byte-identical `.releaserc.yml` to today. Only when `release.assets` is non-empty does the `@semantic-release/github` entry gain an `assets` block.
- **The template stays generic** — no pkl/hk-config-specific knowledge. Building assets is the consuming repo's job via its existing `prepareCmd` hook.
- **Asset glob (hk-config):** `.out/hk-config@*/hk-config@*` (matches all four built files: metadata `hk-config@<v>`, `.sha256`, `.zip`, `.zip.sha256`).
- **`ci:set-version`** receives `--version <v>` (space or `=` form) and builds `VERSION=<v> pkl project package`; with no version it must fall back to pkl's snapshot (do NOT export an empty `VERSION`).
- **Unchanged:** `PklProject`, the `package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/<path>` consumer URI, and the multi-OS `test-steps.yml`.
- **Never hand-edit** managed `tf-*.yml` in any consuming repo.
- **Injected plugin entry uses flow-style YAML** on a single line, interpolated into the existing `cat <<EOF` heredoc like the current `${ASSETS}`/`${PREPARE_CMD}` variables.
- Every commit message ends with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

- `../gha-workflows/.github/workflows/mise-release.yml` — Modify: add `GITHUB_PLUGIN` computation before the heredoc; swap the bare github-plugin line for `${GITHUB_PLUGIN}`.
- `hk-config/scripts/ci-set-version.sh` — Create: parses `--version`, builds the versioned package.
- `hk-config/scripts/publish-pkl-package.sh` — Delete.
- `hk-config/mise.toml` — Modify: `ci:set-version` runs the new script; `ci:publish` becomes a no-op.
- `hk-config/.wetf-ci.yml` — Create: `release.assets` glob.

---

### Task 1: Extend `mise-release.yml` to inject GitHub release assets from `.wetf-ci.yml`

**Working directory:** `/home/simon/repos/wetf/gha-workflows` (create a branch, e.g. `feat/release-assets`, off its default branch first).

**Files:**

- Modify: `.github/workflows/mise-release.yml` (the "Create release configuration file" step, ~lines 80–142)

**Interfaces:**

- Consumes: an optional `.wetf-ci.yml` in the consuming repo with `release.assets` = a list of `{path: <glob>}`.
- Produces: a generated `.releaserc.yml` whose final plugin is either bare `- "@semantic-release/github"` (no assets declared) or `- ["@semantic-release/github", {assets: [{path: "<glob>"}, …]}]` (assets declared).

- [ ] **Step 1: Add the `GITHUB_PLUGIN` computation before the heredoc**

In `.github/workflows/mise-release.yml`, immediately **after** the `if/else` block that sets `PREPARE_CMD`/`ASSETS` (the line `          fi` that closes it, currently line 103) and **before** `          cat <<EOF > .releaserc.yml` (currently line 105), insert (keep the 10-space indentation of the surrounding `run:` body):

```bash
          # Optional GitHub-release assets, declared by the consuming repo in
          # .wetf-ci.yml as:
          #   release:
          #     assets:
          #       - path: <glob>
          # These files must be produced during prepareCmd (see PREPARE_CMD).
          # yq (mikefarah) is preinstalled on ubuntu-latest, as already relied
          # on by mise.yml for test.report-paths.
          GITHUB_PLUGIN='- "@semantic-release/github"'
          if [ -f .wetf-ci.yml ]; then
            asset_flow=$(yq e '.release.assets // [] | .[].path' .wetf-ci.yml \
              | while IFS= read -r p; do [ -n "$p" ] && printf '{path: "%s"}, ' "$p"; done)
            asset_flow="${asset_flow%, }"
            if [ -n "$asset_flow" ]; then
              GITHUB_PLUGIN="- [\"@semantic-release/github\", {assets: [${asset_flow}]}]"
            fi
          fi
```

- [ ] **Step 2: Swap the bare github-plugin line for the variable**

Replace the final plugin line (currently line 141):

```yaml
- "@semantic-release/github"
```

with (same 12-space indentation, so it de-indents to the 2-space plugins-list level and the variable expands to a `- …` entry):

```yaml
${GITHUB_PLUGIN}
```

- [ ] **Step 3: Write a local test harness driving the real generation logic**

Create a scratch test (do NOT commit it) at `/tmp/claude-1000/-home-simon-repos-wetf-hk-config/8ef98205-8819-48ca-a00b-58c00b5e0abb/scratchpad/relrc-test.sh`. It extracts the generation into a function by inlining the edited script (a structurally faithful, abbreviated copy of the heredoc) with the GitHub-Actions expressions hardcoded to the default (non-npm) variant, runs it in a temp dir with and without a `.wetf-ci.yml`, and inspects the result. Backward compatibility (the no-assets case producing today's output) holds **by construction**: `GITHUB_PLUGIN` defaults to the exact original literal `- "@semantic-release/github"` and the only file edit is substituting that one line with `${GITHUB_PLUGIN}` — the test's no-assets assertion confirms this:

```bash
#!/usr/bin/env bash
set -euo pipefail
work=$(mktemp -d)
gen() {  # $1 = dir to run in
  cd "$1"
  VERIFY_CMD="mise run ci:verify-release"
  PREPARE_CMD="mise run ci:set-version --version \${nextRelease.version}"
  ASSETS="[CHANGELOG.md]"
  GITHUB_REF_NAME="master"
  # --- BEGIN copy of the inserted GITHUB_PLUGIN block from Step 1 ---
  GITHUB_PLUGIN='- "@semantic-release/github"'
  if [ -f .wetf-ci.yml ]; then
    asset_flow=$(yq e '.release.assets // [] | .[].path' .wetf-ci.yml \
      | while IFS= read -r p; do [ -n "$p" ] && printf '{path: "%s"}, ' "$p"; done)
    asset_flow="${asset_flow%, }"
    if [ -n "$asset_flow" ]; then
      GITHUB_PLUGIN="- [\"@semantic-release/github\", {assets: [${asset_flow}]}]"
    fi
  fi
  # --- END copy ---
  cat <<EOF > .releaserc.yml
---
branches: ${GITHUB_REF_NAME}

plugins:
  - - "@semantic-release/commit-analyzer"
    - preset: conventionalcommits
  - - "@semantic-release/release-notes-generator"
    - preset: conventionalcommits
  - "@semantic-release/changelog"
  - - "@semantic-release/exec"
    - verifyReleaseCmd: ${VERIFY_CMD}
      prepareCmd: ${PREPARE_CMD}
  - - "@semantic-release/git"
    - assets: ${ASSETS}
  ${GITHUB_PLUGIN}
EOF
}

# Case A: with release.assets
mkdir -p "$work/withassets" && cd "$work/withassets"
cat > .wetf-ci.yml <<'YML'
release:
  assets:
    - path: .out/hk-config@*/hk-config@*
YML
gen "$work/withassets"
echo "=== WITH assets ==="; cat .releaserc.yml
python3 -c "import yaml;d=yaml.safe_load(open('.releaserc.yml'));p=d['plugins'][-1];assert p[0]=='@semantic-release/github' and p[1]['assets']==[{'path':'.out/hk-config@*/hk-config@*'}], p;print('OK: github plugin has assets')"

# Case B: no .wetf-ci.yml
mkdir -p "$work/noassets" && gen "$work/noassets"
cd "$work/noassets"
echo "=== WITHOUT assets ==="; cat .releaserc.yml
python3 -c "import yaml;d=yaml.safe_load(open('.releaserc.yml'));p=d['plugins'][-1];assert p=='@semantic-release/github', p;print('OK: github plugin is bare')"
echo "ALL TESTS PASSED"
rm -rf "$work"
```

Run:

```bash
mise x yq -- bash /tmp/claude-1000/-home-simon-repos-wetf-hk-config/8ef98205-8819-48ca-a00b-58c00b5e0abb/scratchpad/relrc-test.sh
```

Expected: both `OK:` lines and `ALL TESTS PASSED`. (`mise x yq --` provides `yq` if it isn't already on PATH.)

- [ ] **Step 4: Validate the edited workflow file is well-formed YAML**

Run (in the gha-workflows checkout):

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/mise-release.yml')); print('workflow yaml ok')"
```

Expected: `workflow yaml ok`

- [ ] **Step 5: Commit**

```bash
cd /home/simon/repos/wetf/gha-workflows
git add .github/workflows/mise-release.yml
git commit -m "feat(mise-release): attach release assets from .wetf-ci.yml

Let consuming repos declare release.assets in .wetf-ci.yml; the generated
.releaserc.yml then gives @semantic-release/github an assets block so the
files are attached at release creation (immutable-release compatible).
No change for repos without release.assets.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: hk-config — build the versioned package in `ci:set-version`

**Working directory:** `/home/simon/repos/wetf/hk-config` (branch `feat/release-asset-publishing`, already checked out).

**Files:**

- Create: `scripts/ci-set-version.sh`
- Modify: `mise.toml` (`ci:set-version` task)

**Interfaces:**

- Consumes: `PklProject` (already present) — `VERSION=<v> pkl project package` writes `.out/hk-config@<v>/` (four files).
- Produces: `ci:set-version` builds the versioned package; the template's `prepareCmd` (`mise run ci:set-version --version ${nextRelease.version}`) drives it.

- [ ] **Step 1: Create `scripts/ci-set-version.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Build the distributable Pkl package, stamped with the release version.
# Invoked by the managed mise-release prepareCmd as:
#   mise run ci:set-version --version <version>
# For a Pkl package there is no version field to bump in a file — the version
# only materializes as the built archive under .out/hk-config@<version>/, so
# "setting the version" means building the package with VERSION set.
# With no --version (e.g. a local run), fall back to PklProject's snapshot
# version by leaving VERSION unset (an empty VERSION would defeat that fallback).

version=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --version=*) version="${1#--version=}"; shift ;;
    *) shift ;;
  esac
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rm -rf .out

if [ -n "$version" ]; then
  VERSION="$version" pkl project package
else
  pkl project package
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/ci-set-version.sh
```

- [ ] **Step 3: Point `ci:set-version` at the script in `mise.toml`**

Replace the current `ci:set-version` task:

```toml
[tasks."ci:set-version"]
description = "No-op: package version is injected via the VERSION env var at build time"
run = "echo 'ci:set-version: no-op (version comes from the VERSION env var)'"
```

with:

```toml
[tasks."ci:set-version"]
description = "Build the distributable Pkl package, stamped with the release version (--version <v>)"
usage = 'flag "--version <version>"'
run = './scripts/ci-set-version.sh --version "{{option(name="version")}}"'
```

The `--version` flag is declared explicitly in `usage` and forwarded via the
`{{option}}` template, rather than relying on mise's implicit trailing-arg
append. When the flag is absent (local run), the template renders an empty
value (`--version ""`) and the script falls back to the snapshot build.

- [ ] **Step 4: Syntax-check the script**

```bash
bash -n scripts/ci-set-version.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 5: Verify a versioned build via the task**

```bash
mise run ci:set-version --version 2.4.1
grep -E '"packageUri"|"version"' ".out/hk-config@2.4.1/hk-config@2.4.1"
```

Expected includes:

```
"packageUri": "package://github.com/wetransform/hk-config/releases/download/v2.4.1/hk-config@2.4.1",
"version": "2.4.1",
```

- [ ] **Step 6: Verify the no-version fallback builds the snapshot**

```bash
mise run ci:set-version
test -f ".out/hk-config@0.0.1-SNAPSHOT/hk-config@0.0.1-SNAPSHOT.zip" && echo "snapshot fallback ok"
```

Expected: `snapshot fallback ok`

- [ ] **Step 7: Clean and commit**

```bash
rm -rf .out
git add scripts/ci-set-version.sh mise.toml
git commit -m "feat: build versioned pkl package in ci:set-version

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: hk-config — declare release assets and retire the tag-triggered publish path

**Working directory:** `/home/simon/repos/wetf/hk-config` (same branch).

**Files:**

- Create: `.wetf-ci.yml`
- Delete: `scripts/publish-pkl-package.sh`
- Modify: `mise.toml` (`ci:publish` task)

**Interfaces:**

- Consumes: the Task 1 template extension (reads `.wetf-ci.yml release.assets`) and the Task 2 build (produces `.out/hk-config@<v>/…`).
- Produces: `.wetf-ci.yml` declaring the asset glob; `ci:publish` as a no-op.

- [ ] **Step 1: Create `.wetf-ci.yml`**

```yaml
# Repository CI configuration for wetransform managed workflows.
release:
  # Files attached to the GitHub release by @semantic-release/github.
  # Built during the release prepareCmd (mise task ci:set-version).
  # The glob matches all four package files: the metadata (hk-config@<v>),
  # its .sha256, the .zip, and the .zip.sha256.
  assets:
    - path: .out/hk-config@*/hk-config@*
```

- [ ] **Step 2: Delete the obsolete publish script**

```bash
git rm scripts/publish-pkl-package.sh
```

- [ ] **Step 3: Make `ci:publish` a no-op in `mise.toml`**

Replace the current `ci:publish` task:

```toml
[tasks."ci:publish"]
description = "Build the Pkl package and upload it to the matching GitHub release (semver tag builds only)"
run = "./scripts/publish-pkl-package.sh"
```

with:

```toml
[tasks."ci:publish"]
description = "No-op: the Pkl package is attached to the release at creation time by mise-release (@semantic-release/github assets)"
run = "echo 'ci:publish: nothing to publish (package is attached during release)'"
```

- [ ] **Step 4: Verify `release.assets` extraction matches what the template will read**

Reproduce the template's extraction against the new file:

```bash
mise x yq -- yq e '.release.assets // [] | .[].path' .wetf-ci.yml
```

Expected (single line):

```
.out/hk-config@*/hk-config@*
```

- [ ] **Step 5: Verify the glob matches a real build's four files**

```bash
mise run ci:set-version --version 2.4.1 >/dev/null
ls -1 .out/hk-config@2.4.1/hk-config@2.4.1* | wc -l
rm -rf .out
```

Expected: `4`

- [ ] **Step 6: Confirm the package still builds and `ci:publish` no-ops; repo checks pass**

```bash
mise run ci:publish
mise x -- hk check --all && echo "hk check: exit 0"
```

Expected: a `ci:publish: nothing to publish …` line, then `hk check: exit 0`.

- [ ] **Step 7: Commit**

```bash
git add .wetf-ci.yml mise.toml
git commit -m "feat: publish pkl package as release asset; retire tag-upload path

Declare release.assets in .wetf-ci.yml so mise-release attaches the package
to the release at creation time. Remove scripts/publish-pkl-package.sh and
make ci:publish a no-op.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation verification (first release after rollout)

Cannot be exercised locally; confirm on the first real release once **both** the gha-workflows change is released **and** hk-config's managed `tf-release.yml` pins the new `mise-release.yml` version (via Renovate / managed-workflow regeneration):

- [ ] The release job logs show the generated `.releaserc.yml` with the `@semantic-release/github` `assets` block (the step prints it).
- [ ] The new release (e.g. `v2.4.1`) carries the four assets: `hk-config@<v>`, `hk-config@<v>.sha256`, `hk-config@<v>.zip`, `hk-config@<v>.zip.sha256`.
- [ ] A clean-cache consumer resolves it:
  ```bash
  printf 'amends "package://github.com/wetransform/hk-config/releases/download/v<v>/hk-config@<v>#/configs/Default.pkl"\n' > /tmp/hk.pkl
  XDG_CACHE_HOME=$(mktemp -d) pkl eval /tmp/hk.pkl >/dev/null && echo resolves
  ```
- [ ] If immutable releases are enabled (out-of-band): the release is marked immutable and has a signed attestation.

## Notes / carry-forwards

- **Sequencing:** hk-config (Tasks 2–3) is inert until the gha-workflows template (Task 1) is released and its pin picked up; `v2.4.0` already carries assets (backfilled), so nothing breaks in the interim. hk-config may merge first.
- **`tf-publish` vestige:** `ci:publish` is now a no-op; the generated `tf-publish` job still runs on tags but does nothing for this repo. Acceptable.
- **Immutability enablement** is handled out-of-band (repo/org admin), not by this plan.
