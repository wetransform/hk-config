# Pkl Package Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distribute hk-config as a Pkl package attached to each GitHub Release so consumers can use a `package://` URI instead of rate-limited `raw.githubusercontent.com` URLs.

**Architecture:** Add a `PklProject` package definition (direct GitHub-release URI form, version injected via the `VERSION` env var). Adopt the wetransform managed mise release/publish workflows: `ci:verify-release` builds the package before tagging, `ci:publish` builds it on the pushed tag and uploads the archive to the release. PR checks stay on the existing multi-OS `test-steps.yml`.

**Tech Stack:** Pkl 0.32.1, hk 1.53.0, mise, GitHub Actions (wetransform `gha-workflows` managed mise workflows), semantic-release, `gh` CLI.

## Global Constraints

- Pkl version: `0.32.1`; hk version: `1.53.0` (both pinned in `mise.toml`) — one line, do not change.
- Package name: `hk-config`. Consumer URI form (verbatim): `package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/<path>`.
- Package version comes from `read?("env:VERSION")` with fallback `"0.0.1-SNAPSHOT"`.
- License: `MIT`. Author (verbatim, must be email-shaped): `wetransform GmbH <113353961+wetransformer@users.noreply.github.com>`.
- Managed `tf-*.yml` workflows are regenerated from `.wetf-repo.yml` presets by wetransform's central tooling — never hand-edit them.
- `test-steps.yml` (ubuntu/macOS/Windows step tests) stays untouched.
- Only tagged releases carry a package archive; branches/commits do not.
- Every commit message ends with the trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

- Create `PklProject` — package definition (name, version, URIs, license, `exclude`).
- Create `scripts/publish-pkl-package.sh` — builds the package and uploads assets to the release; guards to semver tag builds; retries until the release exists.
- Modify `mise.toml` — add `ci:check`, `ci:verify-release`, `ci:set-version`, `ci:publish` tasks.
- Modify `.gitignore` — ignore `.out/`.
- Modify `.wetf-repo.yml` — switch presets to the mise set; update `required_checks`.
- Modify `README.md` — recommend `package://`, keep raw URLs for branches.
- Modify `CLAUDE.md` — fix stale `pkg.pkl-lang.org/…wetransform-os…` reference.

---

### Task 1: Add the `PklProject` package definition

**Files:**

- Create: `PklProject`
- Modify: `.gitignore`

**Interfaces:**

- Consumes: nothing.
- Produces: a buildable Pkl project. `mise x -- pkl project package` writes `.out/hk-config@<version>/` containing four files: `hk-config@<version>` (metadata JSON), `hk-config@<version>.sha256`, `hk-config@<version>.zip`, `hk-config@<version>.zip.sha256`. The archive contains exactly: `Config.pkl`, `Builtins.pkl`, `Functions.pkl`, `Model.pkl`, `Shared.pkl`, `configs/**`, `steps/**` (16 modules).

- [ ] **Step 1: Create `PklProject`**

```pkl
amends "pkl:Project"

package {
  name = "hk-config"
  authors { "wetransform GmbH <113353961+wetransformer@users.noreply.github.com>" }
  version = read?("env:VERSION")?.replaceFirst("\(name)@", "") ?? "0.0.1-SNAPSHOT"
  baseUri = "package://github.com/wetransform/hk-config/releases/download/v\(version)/hk-config"
  packageZipUrl = "https://github.com/wetransform/hk-config/releases/download/v\(version)/\(name)@\(version).zip"
  sourceCode = "https://github.com/wetransform/hk-config"
  license = "MIT"
  description = "Shared hk (git hooks) configuration for wetransform repositories"
  exclude {
    // dot-prefixed files (.github, .idea, .wetf-*.yml, .gitleaks.toml, …) are
    // excluded by pkl's defaults; these are the non-dot files to keep out.
    "hk.pkl"
    "hk-test-all.pkl"
    "test*.sh"
    "scripts/**"
    "docs/**"
    "mise.toml"
    "*.md"
    "LICENSE"
  }
}
```

- [ ] **Step 2: Ignore the build output directory**

Add `.out/` to `.gitignore` (which currently contains only `.idea/`):

```gitignore
.idea/
.out/
```

- [ ] **Step 3: Build with a snapshot version and verify the output layout**

Run:

```bash
rm -rf .out && mise x -- pkl project package && find .out -type f | sort
```

Expected (exactly these four files):

```
.out/hk-config@0.0.1-SNAPSHOT/hk-config@0.0.1-SNAPSHOT
.out/hk-config@0.0.1-SNAPSHOT/hk-config@0.0.1-SNAPSHOT.sha256
.out/hk-config@0.0.1-SNAPSHOT/hk-config@0.0.1-SNAPSHOT.zip
.out/hk-config@0.0.1-SNAPSHOT/hk-config@0.0.1-SNAPSHOT.zip.sha256
```

- [ ] **Step 4: Verify the archive ships only the consumable modules**

Run:

```bash
unzip -l .out/hk-config@0.0.1-SNAPSHOT/hk-config@0.0.1-SNAPSHOT.zip | awk '{print $4}' | grep -v '^$' | sort
```

Expected (16 modules; no `hk.pkl`, `hk-test-all.pkl`, `PklProject`, `mise.toml`, `*.md`, `LICENSE`, `docs/`, `scripts/`):

```
Builtins.pkl
Config.pkl
Functions.pkl
Model.pkl
Shared.pkl
configs/Default.pkl
configs/Gradle.pkl
configs/Tofu.pkl
configs/autofix/Default.pkl
configs/autofix/Gradle.pkl
configs/autofix/Tofu.pkl
steps/All.pkl
steps/Core.pkl
steps/Default.pkl
steps/Gradle.pkl
steps/Tofu.pkl
```

- [ ] **Step 5: Verify version injection produces the correct package URI**

Run:

```bash
rm -rf .out && VERSION=2.4.0 mise x -- pkl project package >/dev/null && \
  grep -E '"packageUri"|"packageZipUrl"|"version"' .out/hk-config@2.4.0/hk-config@2.4.0
```

Expected:

```
"packageUri": "package://github.com/wetransform/hk-config/releases/download/v2.4.0/hk-config@2.4.0",
"version": "2.4.0",
"packageZipUrl": "https://github.com/wetransform/hk-config/releases/download/v2.4.0/hk-config@2.4.0.zip",
```

- [ ] **Step 6: Clean the build output**

Run:

```bash
rm -rf .out
```

- [ ] **Step 7: Commit**

```bash
git add PklProject .gitignore
git commit -m "feat: add PklProject for package distribution

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add the `ci:*` mise tasks and the publish script

**Files:**

- Create: `scripts/publish-pkl-package.sh`
- Modify: `mise.toml`

**Interfaces:**

- Consumes: the `PklProject` from Task 1 (`pkl project package` builds `.out/hk-config@<version>/`).
- Produces: mise tasks `ci:check`, `ci:verify-release`, `ci:set-version`, `ci:publish` — the names the managed mise workflows call. `ci:publish` runs `scripts/publish-pkl-package.sh`, which reads `PUBLISH_VERSION`, no-ops unless it is a semver, and uploads the four `.out` assets to release `v<version>`.

- [ ] **Step 1: Create `scripts/publish-pkl-package.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Build the distributable Pkl package and upload it to the matching GitHub
# release. Intended to be run by the managed mise-publish workflow (mise task
# ci:publish), which sets PUBLISH_VERSION.
#
# The publish workflow also fires on branch pushes (with PUBLISH_VERSION=latest
# or a branch name); this script only acts on real release builds, i.e. when
# PUBLISH_VERSION is a semantic version coming from a pushed vX.Y.Z tag.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${PUBLISH_VERSION:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "PUBLISH_VERSION='$VERSION' is not a release version; skipping package publish."
  exit 0
fi

# gh needs a token with 'contents: write' to upload release assets.
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_PAT:-}}}"

export VERSION
rm -rf .out
pkl project package

out_dir=".out/hk-config@${VERSION}"
assets=(
  "${out_dir}/hk-config@${VERSION}"
  "${out_dir}/hk-config@${VERSION}.sha256"
  "${out_dir}/hk-config@${VERSION}.zip"
  "${out_dir}/hk-config@${VERSION}.zip.sha256"
)

tag="v${VERSION}"

# The tag push can trigger this workflow a few seconds before semantic-release
# finishes creating the GitHub release; wait for it to appear.
for attempt in 1 2 3 4 5 6; do
  if gh release view "$tag" >/dev/null 2>&1; then
    break
  fi
  echo "Release $tag not present yet (attempt ${attempt}/6); waiting 10s..."
  sleep 10
done

gh release upload "$tag" "${assets[@]}" --clobber
echo "Uploaded Pkl package assets to release $tag."
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x scripts/publish-pkl-package.sh
```

- [ ] **Step 3: Add the `ci:*` tasks to `mise.toml`**

Append to `mise.toml`:

```toml
[tasks."ci:check"]
description = "Validate that the distributable Pkl package builds"
run = "rm -rf .out && pkl project package"

[tasks."ci:verify-release"]
description = "Verify the package builds before a release is tagged"
depends = ["ci:check"]

[tasks."ci:set-version"]
description = "No-op: package version is injected via the VERSION env var at build time"
run = "echo 'ci:set-version: no-op (version comes from the VERSION env var)'"

[tasks."ci:publish"]
description = "Build the Pkl package and upload it to the matching GitHub release (semver tag builds only)"
run = "./scripts/publish-pkl-package.sh"
```

- [ ] **Step 4: Syntax-check the script**

Run:

```bash
bash -n scripts/publish-pkl-package.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 5: Verify `ci:check` builds the package**

Run:

```bash
mise run ci:check && test -f ".out/hk-config@0.0.1-SNAPSHOT/hk-config@0.0.1-SNAPSHOT.zip" && echo "built"
```

Expected: ends with `built`

- [ ] **Step 6: Verify the publish guard skips non-release versions**

Run:

```bash
PUBLISH_VERSION=latest ./scripts/publish-pkl-package.sh
```

Expected (exit 0, no build, no `gh` call):

```
PUBLISH_VERSION='latest' is not a release version; skipping package publish.
```

- [ ] **Step 7: Verify `ci:set-version` is a no-op that tolerates `--version`**

Run:

```bash
mise run ci:set-version --version 2.4.0
```

Expected (exit 0): a line containing `ci:set-version: no-op`.

- [ ] **Step 8: Clean and commit**

```bash
rm -rf .out
git add scripts/publish-pkl-package.sh mise.toml
git commit -m "feat: add ci mise tasks and pkl package publish script

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Switch to the managed mise release/publish workflows

**Files:**

- Modify: `.wetf-repo.yml`

**Interfaces:**

- Consumes: the `ci:*` tasks from Task 2 (the generated `tf-release`/`tf-publish` call `ci:verify-release`, `ci:set-version`, `ci:publish`).
- Produces: `.wetf-repo.yml` presets that make wetransform's central tooling regenerate `tf-release`/`tf-publish` as the mise variants.

**Reference:** `feature-explorer/.wetf-repo.yml` uses presets `mise`, `renovate`, `workflows-default` with `workflows.presets: [npm]`. hk-config is **not** an npm project, so use the **default variant** (omit `workflows.presets`).

- [ ] **Step 1: Update presets in `.wetf-repo.yml`**

Replace the `presets` list (currently `renovate`, `repo-release`) so `repo-release` becomes the mise set:

```yaml
presets:
  - mise
  - renovate
  - workflows-default
```

Leave the `required_checks` list as-is for now (updated in Step 3).

- [ ] **Step 2: Confirm the file is valid YAML**

Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('.wetf-repo.yml')); print('yaml ok')"
```

Expected: `yaml ok`

- [ ] **Step 3: Update `required_checks` to match the new workflows**

The old `repo-release` custom `tf-release` is replaced by the managed mise `tf-release` (manual dispatch) + `tf-publish` (on tags). The multi-OS `test-steps` checks stay. Set `required_checks` to the checks that gate PRs — keep the existing `test-steps (…)` and `test-docker` entries. If the `workflows-default` preset also generates a `tf-check` job (see Step 4), add its job name (`check`) here.

```yaml
required_checks:
  - test-steps (ubuntu-latest)
  - test-steps (macos-latest)
  - test-steps (windows-latest)
  - test-docker
```

- [ ] **Step 4: Document / verify the regeneration and tf-check question**

This is a verification step (no code change):

- Trigger or wait for wetransform's central tooling to regenerate the managed workflows from the new presets (the same mechanism that produced the current `tf-*.yml`).
- After regeneration, confirm `tf-release.yml` and `tf-publish.yml` now reference `wetransform/gha-workflows/.github/workflows/mise-release.yml` and `mise-publish.yml` (as in `feature-explorer`).
- Check whether a `tf-check.yml` (mise-check, ubuntu-only) was also generated. If it was: it runs `ci:check` (package build) — harmless and complementary to `test-steps.yml`; keep it and add `check` to `required_checks`. If strictly "release + publish only" is desired, opt it out via the tooling. Record the decision in the PR description.

- [ ] **Step 5: Commit**

```bash
git add .wetf-repo.yml
git commit -m "ci: switch to managed mise release and publish workflows

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Update documentation

**Files:**

- Modify: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:**

- Consumes: the consumer URI form produced by Task 1.
- Produces: docs recommending `package://` for releases and keeping raw URLs for branches/commits.

- [ ] **Step 1: Rewrite the "Using a pre-defined shared configuration" example in `README.md`**

Replace the raw-URL `amends` block (currently lines ~98–104) with the package form as primary, plus a raw-URL note for branches. Use this content:

````markdown
#### Using a pre-defined shared configuration

Reference a released version as a Pkl package (recommended). Package archives
are served from the GitHub release CDN, avoiding the rate limiting that applies
to raw GitHub URLs:

```pkl
amends "package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/configs/Default.pkl"
```

Replace `<version>` with the desired release version, e.g. `2.4.0` (note: the
`v` prefix appears in the path segment but not in the `hk-config@<version>`
package coordinate). Package archives are attached to every release from the
one that introduced packaging onward; earlier tags have no archive (use the
raw-URL form below for those).

To reference a **branch or specific commit** (for example, to test changes
before a release), use a raw GitHub URL instead — branches have no package
archive:

```pkl
amends "https://raw.githubusercontent.com/wetransform/hk-config/refs/heads/<branch>/configs/Default.pkl"
```
````

- [ ] **Step 2: Update the "Reusing shared linter configurations" examples in `README.md`**

The two later examples (currently using `raw.githubusercontent.com/.../refs/tags/<tag>/...`) should show the package form as primary. Replace each `amends`/`import` raw-tag URL with the package equivalent, keeping the surrounding Pkl unchanged. For the first example:

```pkl
amends "package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/Config.pkl"
import "package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/Builtins.pkl"
import "package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/Shared.pkl"
```

For the second example:

```pkl
amends "package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/Config.pkl"
import "package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/Shared.pkl"
import "package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/Model.pkl"
import "package://github.com/wetransform/hk-config/releases/download/v<version>/hk-config@<version>#/Functions.pkl"
```

Add one sentence after these examples: "To pin a branch or commit instead of a
release, use the `https://raw.githubusercontent.com/wetransform/hk-config/refs/heads/<branch>/…`
form shown above."

- [ ] **Step 3: Fix the stale reference in `CLAUDE.md`**

In `CLAUDE.md`, the "How consumers use this repo" section currently shows:

```pkl
amends "package://pkg.pkl-lang.org/github.com/wetransform-os/hk-config@2.2.0#/configs/Default.pkl"
```

Replace it with the actual direct-GitHub form and correct org:

```pkl
amends "package://github.com/wetransform/hk-config/releases/download/v2.4.0/hk-config@2.4.0#/configs/Default.pkl"
```

- [ ] **Step 4: Verify docs pass the repo's own linters**

Run:

```bash
mise x -- hk fix --all && git diff --stat
```

Expected: prettier makes no further changes to the edited Markdown (or only its own formatting), and `hk check` passes:

```bash
mise x -- hk check --all
```

Expected: exits 0.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document package:// usage and fix stale references

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation verification (first real release)

After the first release cut with these changes lands (e.g. `v2.4.0`), confirm the end-to-end flow:

- [ ] The GitHub release `v2.4.0` has four assets: `hk-config@2.4.0`, `hk-config@2.4.0.sha256`, `hk-config@2.4.0.zip`, `hk-config@2.4.0.zip.sha256`.
- [ ] In a scratch dir, a consumer resolves the package:
  ```bash
  printf 'amends "package://github.com/wetransform/hk-config/releases/download/v2.4.0/hk-config@2.4.0#/configs/Default.pkl"\n' > hk.pkl
  mise x -- pkl eval hk.pkl >/dev/null && echo "resolves"
  ```
  Expected: `resolves`.
- [ ] Confirm the `ci:publish` step in the `tf-publish` run for the tag succeeded (and that the master-push run of `tf-publish` skipped publishing with the "not a release version" message).

## Open items to resolve during implementation (from the spec)

- **Publish token scope:** `gh release upload` needs `contents: write`. Verify the token the managed `mise-publish` provides (`GITHUB_TOKEN` / `GH_PAT`) has it; if not, arrange a write-scoped token. The script already prefers `GH_TOKEN` → `GITHUB_TOKEN` → `GH_PAT`.
- **`tf-check` generation:** decided in Task 3, Step 4.
