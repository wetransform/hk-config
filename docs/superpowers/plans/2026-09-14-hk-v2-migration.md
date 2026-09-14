# hk 2 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hk-config evaluate identically under hk 2's built-in Pkl evaluator (pklr) and the reference pkl CLI, bump the base to hk 2.0.0, and guard the equivalence with a CI parity check, released as a new major.

**Architecture:** Three pklr defects are worked around in pure Pkl without changing the consumer API: `Functions.defaultHooks` filters via a `Dynamic` normalisation instead of `is` type tests; step modules compose mappings with spread (`...X.steps`) instead of amending imported mappings; `hk.pkl` no longer declares a local named `steps`. A shell script compares, per hook, the step names the pkl CLI produces against the step names hk plans, for every entry point and distributable config, and runs locally (`test.sh`) and in CI.

**Tech Stack:** Pkl 0.32.1 (pkl CLI), hk 2.0.0 (pklr 2.0.1), mise, bash, jq, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-14-hk-v2-migration-design.md`

## Global Constraints

- **hk base version:** `package://github.com/jdx/hk/releases/download/v2.0.0/hk@2.0.0#/Config.pkl` and `.../hk@2.0.0#/Builtins.pkl`. mise pins `hk = "2.0.0"`, `pkl = "0.32.1"`.
- **No `HK_PKL_BACKEND` anywhere** after Task 3 (mise.toml, README).
- **Consumer API unchanged:** `Functions.defaultHooks(autofix: Boolean, useSteps: Mapping<String, Model.Step>): Mapping<String, Config.Hook>`, `Model.ExtendedStep { step; disable_pre_commit; disable_pre_push; disable_check; disable_fix }`, `Model.Step`, every export of `Shared.pkl`, all `configs/**/*.pkl` paths.
- **Forbidden Pkl constructs** (pklr mis-evaluates them; see spec "Problem"): `x is SomeClass`; `(Imported.mapping) { ["k"] = Other.member }`; a `local steps` property in a module that amends `Config.pkl`; `hasProperty`, `getPropertyOrNull`, `Map.getOrNull`; spreading an object with `hidden` properties.
- **Spread needs `toDynamic()`:** the pkl CLI rejects `{ ...typedValue }`; always spread `typedValue.toDynamic()`.
- **`hk run <hook> --plan` must get stdin closed** (`</dev/null`), otherwise `pre-push` blocks waiting for ref input.
- **Commits:** Conventional Commits, no JIRA reference (branch `feat/hk-v2-migration` has none), **no `Co-Authored-By` trailer** (global CLAUDE.md). Work on branch `feat/hk-v2-migration`.
- **Pre-commit hook in the sandbox:** the `hktest` step may fail because the proxy blocks python.org downloads. If, and only if, that is the failure, commit with `HK_SKIP_STEPS=hktest git commit ...`. Any other hook failure must be fixed.
- **Never hand-edit** managed `.github/workflows/tf-*.yml`. `.wetf-repo.yml` is ours and is edited in Task 4.
- **CHANGELOG.md is generated**; do not edit it.
- Scratch files go to the session scratchpad directory (`$SCRATCH` below), never into the repo.

## File Structure

- `Functions.pkl` — Modify: `defaultHooks` filters with a Dynamic normalisation (Task 1).
- `steps/Default.pkl`, `steps/Tofu.pkl`, `steps/Gradle.pkl`, `steps/All.pkl` — Modify: spread instead of amend (Task 2).
- `hk.pkl` — Modify: rename local, spread (Task 2).
- `Config.pkl`, `Builtins.pkl`, `mise.toml` — Modify: hk 2.0.0 base, env var removed (Task 3).
- `scripts/check-evaluator-parity.sh` — Create: the parity check (Task 4).
- `mise.toml` — Modify: task `test:parity` (Task 4).
- `test.sh` — Modify: run the parity check before `hk test` (Task 4).
- `.github/workflows/test-steps.yml` — Modify: job `evaluator-parity` (Task 4).
- `.wetf-repo.yml` — Modify: required check `evaluator-parity` (Task 4).
- `README.md`, `CLAUDE.md` — Modify: hk 2 requirements, pitfalls, stale text (Task 5).

Set once per shell before starting:

```bash
cd /home/simon/repos/wetf/hk-config
git checkout feat/hk-v2-migration
SCRATCH=/tmp/claude-1000/-home-simon-repos-wetf-hk-config/4c3be4c3-1abd-4c8d-a6bc-481f257b99ee/scratchpad/plan
mkdir -p "$SCRATCH"
```

---

### Task 0: Record the hk 1 baseline

Tasks 1 and 2 are pure refactors under the *current* base (hk 1.58.1). Their test is "the pkl CLI produces byte-identical JSON before and after". Record the before-state first.

**Files:** none modified.

- [ ] **Step 1: Confirm clean state and tool versions**

Run:
```bash
git status --short
mise x -- hk --version
mise x -- pkl --version
```
Expected: no modified tracked files; `hk 1.58.1`; `Pkl 0.32.1`.

- [ ] **Step 2: Render every entry point and config with the pkl CLI**

Run:
```bash
for f in hk.pkl hk-test-all.pkl configs/Default.pkl configs/Gradle.pkl configs/Tofu.pkl configs/autofix/Default.pkl configs/autofix/Gradle.pkl configs/autofix/Tofu.pkl; do
  mise x -- pkl eval -f json "$f" > "$SCRATCH/baseline-${f//\//_}.json"
done
ls -la "$SCRATCH"/baseline-*.json
jq -r '.hooks | to_entries[] | "\(.key): \(.value.steps | keys | join(","))"' "$SCRATCH/baseline-hk.pkl.json"
```
Expected: eight non-empty files. The last command prints four lines; `check` must list `actionlint,gitleaks,gitleaks_ci,hktest,pkl,pklformat,prettier,renovate,terraform,yaml-schema` and `pre-commit` must **not** contain `gitleaks` or `gitleaks_ci`.

- [ ] **Step 3: Record the hk 1 plans for hk.pkl**

Run:
```bash
for h in check fix pre-commit pre-push; do
  mise x -- hk run "$h" --all --plan -n </dev/null 2>&1 | grep -E '[✓○]' | sed 's/  (.*//' | sort > "$SCRATCH/baseline-plan-$h.txt"
done
cat "$SCRATCH/baseline-plan-pre-commit.txt"
```
Expected: `pre-commit` lists actionlint, hktest, pkl, pklformat, prettier, renovate, terraform (marked ○, no files), yaml-schema, and no gitleaks entries.

No commit for this task.

---

### Task 1: `Functions.pkl` without type tests

**Files:**
- Modify: `Functions.pkl`

**Interfaces:**
- Produces: `Functions.defaultHooks(autofix: Boolean, useSteps: Mapping<String, Model.Step>): Mapping<String, Config.Hook>` — unchanged signature and semantics: a `Model.ExtendedStep` entry is dropped from the hook whose `disable_*` flag is `true` and otherwise contributes its `.step`; a plain `Config.Step` is included in all four hooks.

- [ ] **Step 1: Write the regression check (fails before the change only if semantics differ, so first confirm it passes on the untouched file)**

Create `$SCRATCH/compare-baseline.sh`:
```bash
#!/usr/bin/env bash
# Compare current pkl CLI output with the Task 0 baseline for every target.
set -euo pipefail
cd /home/simon/repos/wetf/hk-config
SCRATCH=/tmp/claude-1000/-home-simon-repos-wetf-hk-config/4c3be4c3-1abd-4c8d-a6bc-481f257b99ee/scratchpad/plan
rc=0
for f in hk.pkl hk-test-all.pkl configs/Default.pkl configs/Gradle.pkl configs/Tofu.pkl configs/autofix/Default.pkl configs/autofix/Gradle.pkl configs/autofix/Tofu.pkl; do
  if diff <(jq -S . "$SCRATCH/baseline-${f//\//_}.json") <(mise x -- pkl eval -f json "$f" | jq -S .) >/dev/null; then
    echo "same  $f"
  else
    echo "DIFF  $f"; rc=1
  fi
done
exit $rc
```
Run: `chmod +x "$SCRATCH/compare-baseline.sh" && "$SCRATCH/compare-baseline.sh"`
Expected: eight `same` lines, exit 0.

- [ ] **Step 2: Replace the body of `Functions.pkl`**

Replace the whole file with:
```pkl
import "./Config.pkl"
import "./Model.pkl"

// Normalise a step mapping entry to a Dynamic that always carries the
// ExtendedStep flags (with defaults) and the wrapped step (or null).
//
// Why not `v is Model.ExtendedStep`? hk >= 2 evaluates configuration with its
// built-in pklr evaluator, and pklr (2.0.1) evaluates `is` type tests against
// classes as always true. Filtering with `is` therefore drops every step or
// fails with "field not found". Spreading `v.toDynamic()` over a template with
// defaults works identically in pklr and in the pkl CLI.
// See docs/superpowers/specs/2026-09-14-hk-v2-migration-design.md
local normalize = (v) ->
  (new Dynamic {
    step = null
    disable_pre_commit = false
    disable_pre_push = false
    disable_check = false
    disable_fix = false
  }) { ...v.toDynamic() }

function defaultHooks(
  autofix: Boolean,
  useSteps: Mapping<String, Model.Step>,
): Mapping<String, Config.Hook> = new Mapping<String, Config.Hook> {
  local normalized = useSteps.toMap().mapValues((k, v) -> normalize.apply(v))

  // hand the original typed step back to hk, never the Dynamic
  local extract = (k, v) -> v.step ?? useSteps[k]

  local precommitSteps = normalized.filter((k, v) -> !v.disable_pre_commit).mapValues(extract).toMapping()

  local prepushSteps = normalized.filter((k, v) -> !v.disable_pre_push).mapValues(extract).toMapping()

  local checkSteps = normalized.filter((k, v) -> !v.disable_check).mapValues(extract).toMapping()

  local fixSteps = normalized.filter((k, v) -> !v.disable_fix).mapValues(extract).toMapping()

  ["pre-commit"] {
    fix = autofix
    stash = "git"
    steps = precommitSteps
  }
  ["pre-push"] {
    steps = prepushSteps
  }
  ["fix"] {
    fix = true
    steps = fixSteps
  }
  ["check"] {
    steps = checkSteps
  }
}
```

- [ ] **Step 3: Run the regression check and the linters**

Run:
```bash
"$SCRATCH/compare-baseline.sh"
mise x -- pkl eval hk.pkl >/dev/null && echo "pkl ok"
mise x -- hk check --all --step pkl --step pklformat
```
Expected: eight `same` lines (the rendered JSON is identical, so behaviour is unchanged), `pkl ok`, and both linter steps pass. If `pklformat` reports a formatting difference, run `mise x -- hk fix --all --step pklformat` and re-run the check.

- [ ] **Step 4: Commit**

```bash
git add Functions.pkl
git commit -m "refactor: filter hook steps without Pkl type tests

hk 2's built-in evaluator (pklr) treats \`is\` class checks as always true,
which makes defaultHooks drop every step. Normalise entries via a Dynamic
spread instead; output is byte-identical under the pkl CLI."
```

---

### Task 2: Compose step mappings with spread; rename the local in `hk.pkl`

**Files:**
- Modify: `steps/Default.pkl`
- Modify: `steps/Tofu.pkl`
- Modify: `steps/Gradle.pkl`
- Modify: `steps/All.pkl`
- Modify: `hk.pkl`

**Interfaces:**
- Produces: `steps` of each `steps/*.pkl` remains `Mapping<String, Model.Step>` with the same keys as before; `hk.pkl` still results in `hooks = Functions.defaultHooks(true, <Default steps + hktest>)`.

- [ ] **Step 1: Rewrite `steps/Default.pkl`**

Replace the whole file with:
```pkl
/*
  Default configuration with tools that work for most repos.
*/
import "../Builtins.pkl"
import "../Model.pkl"
import "./Core.pkl"

// Note: composed with spread instead of amending `Core.steps` — hk's built-in
// evaluator (pklr) fails on amending an imported mapping while adding entries
// that reference another imported module.
steps = new Mapping<String, Model.Step> {
  ...Core.steps
  // terraform formatting - assumes correct terraform is available, e.g. via mise or similar
  ["terraform"] = Builtins.terraform
}
```

- [ ] **Step 2: Rewrite `steps/Tofu.pkl`**

Replace the whole file with:
```pkl
/*
  Default configuration but assumes OpenTofu is used instead of Terraform in case there are Terraform related files.
*/
import "../Builtins.pkl"
import "../Model.pkl"
import "./Core.pkl"

// Note: composed with spread instead of amending `Core.steps` — see steps/Default.pkl
steps = new Mapping<String, Model.Step> {
  ...Core.steps
  // tofu formatting - assumes correct tofu is available, e.g. via mise or similar
  ["tofu"] = Builtins.tofu
}
```

- [ ] **Step 3: Rewrite `steps/Gradle.pkl`**

Replace the whole file with:
```pkl
import "../Model.pkl"
import "../Shared.pkl"
import "./Default.pkl"

// Note: composed with spread instead of amending `Default.steps` — see steps/Default.pkl
steps = new Mapping<String, Model.Step> {
  ...Default.steps
  // add Spotless code formatter
  ["spotlessGradle"] = Shared.spotlessGradle
}
```

- [ ] **Step 4: Rewrite `steps/All.pkl`**

Replace the whole file with:
```pkl
import "../Model.pkl"
import "../Shared.pkl"
import "./Default.pkl"

// Note: This file is used to test all steps in one go, should not be used in other projects.
// Composed with spread instead of amending `Default.steps` — see steps/Default.pkl

steps = new Mapping<String, Model.Step> {
  ...Default.steps
  ["detectsecrets"] = Shared.detectsecrets
  ["ripsecrets"] = Shared.ripsecrets
  // exclude trufflehog because there are inconsistent results testing locally and in CI
  // ["trufflehog"] = Shared.trufflehog
  ["trivysecrets"] = Shared.trivysecrets
}
```

- [ ] **Step 5: Rewrite `hk.pkl`**

Replace the whole file with:
```pkl
amends "./Config.pkl"

import "./Functions.pkl"
import "./Model.pkl"
import "./steps/Default.pkl" as Steps

// Note: deliberately not named `steps`: hk 2 has a top-level `steps` property
// and its built-in evaluator (pklr) lets a `local steps` shadow it, which
// silently empties all hooks.
local allSteps = new Mapping<String, Model.Step> {
  ...Steps.steps
  // in addition to the default steps, run hk test
  ["hktest"] = new Step {
    check = "hk test"
    exclusive = true // avoid problems conflicting with other steps (e.g. installation of prettier via mise)
  }
}

hooks = Functions.defaultHooks(true, allSteps)
```

- [ ] **Step 6: Run the regression check and linters**

Run:
```bash
"$SCRATCH/compare-baseline.sh"
mise x -- hk check --all --step pkl --step pklformat
```
Expected: eight `same` lines; linters pass (fix formatting with `mise x -- hk fix --all --step pklformat` if needed and re-run).

- [ ] **Step 7: Commit**

```bash
git add steps/Default.pkl steps/Tofu.pkl steps/Gradle.pkl steps/All.pkl hk.pkl
git commit -m "refactor: compose step mappings with spread instead of amend

hk 2's built-in evaluator (pklr) fails on amending an imported mapping
while adding entries that reference another module, and lets a
\`local steps\` in hk.pkl shadow the new top-level steps property.
Rendered output under the pkl CLI is unchanged."
```

---

### Task 3: Bump the base to hk 2.0.0

**Files:**
- Modify: `Config.pkl`
- Modify: `Builtins.pkl`
- Modify: `mise.toml`

**Interfaces:**
- Produces: `Config.pkl` amends hk@2.0.0 `Config.pkl`; `Builtins.pkl` amends hk@2.0.0 `Builtins.pkl`; `hk` on PATH is 2.0.0 and no `HK_PKL_BACKEND` is set by mise.

- [ ] **Step 1: Show that hk 2 rejects the current setup (the "red" state)**

Run:
```bash
mise x hk@2.0.0 -- hk validate 2>&1 | grep -m1 'HK_PKL_BACKEND'
```
Expected: the line `HK_PKL_BACKEND no longer selects an evaluator in hk v2; remove it or set it to \`pklr\`. ...`.

- [ ] **Step 2: Edit `Config.pkl` and `Builtins.pkl`**

`Config.pkl` becomes exactly:
```pkl
amends "package://github.com/jdx/hk/releases/download/v2.0.0/hk@2.0.0#/Config.pkl"
```
`Builtins.pkl` becomes exactly:
```pkl
amends "package://github.com/jdx/hk/releases/download/v2.0.0/hk@2.0.0#/Builtins.pkl"
```

- [ ] **Step 3: Edit `mise.toml`**

Change the `[tools]` line `hk = "1.58.1"` to `hk = "2.0.0"` and delete the whole `[env]` block (the two comment/assignment lines `# explicitly use pkl CLI instead of pklr library ...` and `HK_PKL_BACKEND = "pkl"`, plus the `[env]` header and its preceding blank line). The top of the file must read:
```toml
[tools]
# for git hooks
hk = "2.0.0"
pkl = "0.32.1"

[hooks]
enter = "mise x -- hk install --mise"
postinstall = "mise x -- hk install --mise"
```
Everything from `[tasks."ci:check"]` on stays unchanged.

- [ ] **Step 4: Install hk 2 and reinstall the git hooks**

Run:
```bash
mise install
mise x -- hk --version
mise x -- hk install --mise
env | grep HK_PKL_BACKEND || echo "env var gone"
```
Expected: `hk 2.0.0`; two `Installed hk hook` lines; `env var gone`. (If your shell still exports `HK_PKL_BACKEND` from a previous `mise activate`, run `eval "$(mise env)"` or open a new shell.)

- [ ] **Step 5: Validate and plan under hk 2**

Run:
```bash
mise x -- hk validate
for h in check fix pre-commit pre-push; do
  echo "== $h"
  diff "$SCRATCH/baseline-plan-$h.txt" <(mise x -- hk run "$h" --all --plan -n </dev/null 2>&1 | grep -E '[✓○]' | sed 's/  (.*//' | sort) && echo "same as hk 1 baseline"
done
```
Expected: `hk.pkl is valid`, and `same as hk 1 baseline` for all four hooks. Any empty plan or missing step means one of the three pklr workarounds was not applied correctly — re-check Tasks 1–2 against the spec; do not proceed.

- [ ] **Step 6: Run the linters and step tests**

Run:
```bash
mise x -- hk check --all
./test.sh
```
Expected: all steps pass. `./test.sh` runs `hk test` for every step in `hk-test-all.pkl`; the only acceptable failures are tool installs blocked by the sandbox proxy (a `403` from python.org or similar). Record any such skipped test in the commit body.

- [ ] **Step 7: Verify packaging still works**

Run:
```bash
rm -rf .out && mise x -- pkl project package && ls .out
rm -rf .out
```
Expected: a directory `hk-config@0.0.1-SNAPSHOT` (network warnings from `pkl` about GitHub are tolerable as long as the directory is produced).

- [ ] **Step 8: Commit (breaking change)**

```bash
git add Config.pkl Builtins.pkl mise.toml
git commit -m "feat!: migrate to hk 2 (built-in pklr evaluator)

hk 2 removed the pkl CLI backend, so the configuration is now evaluated
by hk's built-in evaluator. The base configuration amends hk@2.0.0.

BREAKING CHANGE: requires hk >= 2.0.0. Remove the HK_PKL_BACKEND entry
from the [env] section of mise.toml in consuming repositories."
```

---

### Task 4: Evaluator parity check (script, mise task, test.sh, CI, required check)

**Files:**
- Create: `scripts/check-evaluator-parity.sh`
- Modify: `mise.toml` (add task `test:parity`)
- Modify: `test.sh`
- Modify: `.github/workflows/test-steps.yml`
- Modify: `.wetf-repo.yml`

**Interfaces:**
- Produces: `scripts/check-evaluator-parity.sh` — exit 0 when, for every target and hook, the sorted step names from `pkl eval -f json` equal the sorted step names from `hk run <hook> --all --plan --json`; exit 1 otherwise, printing both lists. Mise task `test:parity` runs it.

- [ ] **Step 1: Create the script**

Create `scripts/check-evaluator-parity.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Evaluator parity check.
#
# hk >= 2 evaluates hk.pkl with its built-in Rust evaluator (pklr). pklr has
# been observed to silently drop steps or whole hooks for constructs that the
# reference pkl CLI evaluates correctly (see
# docs/superpowers/specs/2026-09-14-hk-v2-migration-design.md). This script
# compares, for every entry point and distributable config, the step names hk
# plans per hook with the step names the pkl CLI renders.
#
# Requires hk (>= 2), pkl, jq and git on PATH — run it via `mise run test:parity`.

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

hooks=(check fix pre-commit pre-push)
targets=(
  hk.pkl
  hk-test-all.pkl
  configs/Default.pkl
  configs/Gradle.pkl
  configs/Tofu.pkl
  configs/autofix/Default.pkl
  configs/autofix/Gradle.pkl
  configs/autofix/Tofu.pkl
)

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0
for target in "${targets[@]}"; do
  dir="$work/${target//\//_}"
  # a full copy (including .git) so relative imports resolve and `hk --all` can list files;
  # mise.toml is dropped so the copy is never picked up as a mise config
  cp -R "$repo/." "$dir"
  rm -f "$dir/mise.toml"
  case "$target" in
    configs/*) printf 'amends "./%s"\n' "$target" > "$dir/hk.pkl" ;;
    *) cp "$repo/$target" "$dir/hk.pkl" ;;
  esac

  for hook in "${hooks[@]}"; do
    expected="$(pkl eval -f json "$dir/hk.pkl" | jq -r --arg h "$hook" '(.hooks[$h].steps // {}) | keys[]' | sort)"
    # stdin must be closed: `pre-push` otherwise waits for ref input
    actual="$(hk --cd "$dir" run "$hook" --all --plan --json -n -q </dev/null | sed -n '/^{/,$p' | jq -r '.steps[].name' | sort)"

    if [ -z "$expected" ]; then
      echo "FAIL  $target [$hook]: pkl CLI rendered no steps for this hook"
      failed=1
    elif [ "$expected" != "$actual" ]; then
      echo "FAIL  $target [$hook]: hk plans different steps than the pkl CLI renders"
      diff <(echo "$expected") <(echo "$actual") | sed 's/^/        /' || true
      failed=1
    else
      echo "ok    $target [$hook] ($(echo "$expected" | wc -l | tr -d ' ') steps)"
    fi
  done
done

if [ "$failed" -ne 0 ]; then
  echo
  echo "Evaluator parity check FAILED: hk's built-in evaluator disagrees with the pkl CLI."
  echo "Look for Pkl constructs listed under 'Problem' in docs/superpowers/specs/2026-09-14-hk-v2-migration-design.md."
  exit 1
fi
echo "Evaluator parity check passed."
```
Run: `chmod +x scripts/check-evaluator-parity.sh`

- [ ] **Step 2: Add the mise task and the jq dependency**

In `mise.toml`, add `jq` to `[tools]` so the script's only non-hk/pkl dependency is provided by mise for every developer and CI (ubuntu runners ship jq, macOS may not):
```toml
[tools]
# for git hooks
hk = "2.0.0"
pkl = "0.32.1"
# for scripts/check-evaluator-parity.sh
jq = "1.8.2"
```
Then append the task (after the `[hooks]` block, before `[tasks."ci:check"]`):
```toml
[tasks."test:parity"]
description = "Check that hk's built-in Pkl evaluator and the pkl CLI agree on the configured steps"
run = "./scripts/check-evaluator-parity.sh"
```
Run `mise install` afterwards so `jq` is available.

- [ ] **Step 3: Run it — expect green**

Run: `mise run test:parity`
Expected: 32 `ok` lines (8 targets × 4 hooks) and `Evaluator parity check passed.`, exit 0.

- [ ] **Step 4: Prove it detects a divergence (red), then revert**

Temporarily reintroduce pklr defect #3 in `hk.pkl` by renaming the local:
```bash
sed -i 's/local allSteps = /local steps = /; s/defaultHooks(true, allSteps)/defaultHooks(true, steps)/' hk.pkl
mise run test:parity; echo "exit=$?"
git checkout hk.pkl
```
Expected: four `FAIL  hk.pkl [...]` lines whose diff shows every step prefixed with `<` (pkl CLI has them, hk plans none), the trailing `Evaluator parity check FAILED` message, `exit=1`. After `git checkout hk.pkl`, `git status --short` shows `hk.pkl` clean.

- [ ] **Step 5: Wire it into `test.sh`**

In `test.sh`, insert before the line `hk cache clear`:
```bash
# make sure hk's built-in evaluator and the pkl CLI agree before running step tests
mise run test:parity
```
The file must now read:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# make sure hk's built-in evaluator and the pkl CLI agree before running step tests
mise run test:parity

hk cache clear

cp hk.pkl hk.pkl.bak
trap 'mv hk.pkl.bak hk.pkl; hk cache clear' EXIT

cp hk-test-all.pkl hk.pkl
mise x -- hk test "$@"
```

- [ ] **Step 6: Add the CI job**

In `.github/workflows/test-steps.yml`, append a third job after `test-docker` (same indentation as the other jobs, reuse the exact pinned action versions already in the file):
```yaml
  evaluator-parity:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Set up mise
        uses: jdx/mise-action@c2a87611a18de5b3828c5652fe268e992400cb5c # v4.3.0
        with:
          github_token: ${{ secrets.GH_PAT_READ_WETRANSFORM }}

      - name: Check that hk's built-in evaluator agrees with the pkl CLI
        run: mise run test:parity
```

- [ ] **Step 7: Register the required check**

In `.wetf-repo.yml`, add to `required_checks` after `- test-docker`:
```yaml
  - evaluator-parity
```

- [ ] **Step 8: Lint the changed files and run the full local checks**

Run:
```bash
mise x -- hk check --all
./test.sh
```
Expected: `hk check --all` passes (actionlint validates the workflow, prettier the YAML, yaml-schema `.wetf-repo.yml` if it carries a schema comment). `./test.sh` first prints the 32 `ok` parity lines, then runs the step tests as in Task 3 Step 6.

- [ ] **Step 9: Commit**

```bash
git add scripts/check-evaluator-parity.sh mise.toml test.sh .github/workflows/test-steps.yml .wetf-repo.yml
git commit -m "test: add evaluator parity check for hk's built-in Pkl evaluator

Compares the step names per hook rendered by the pkl CLI with the steps hk
plans, for every entry point and distributable config. Runs via
\`mise run test:parity\`, from test.sh and as the required CI check
evaluator-parity."
```

---

### Task 5: Documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: README — remove the backend section, require hk 2**

In `README.md`, under "## Setting up hk in a new repository", replace the paragraph starting `Currently the configuration requires to explicitly configure the \`pkl\` CLI to be used as backend` together with its following ` ```toml ... ``` ` block (the `[env]` / `HK_PKL_BACKEND = "pkl"` block) with:
```markdown
hk **2.0.0 or newer** is required: the shared configuration relies on hk's
built-in Pkl evaluator and is tested against it (see _Evaluator parity_ below).
Do **not** set `HK_PKL_BACKEND` — hk 2 rejects it. If you upgrade a repository
from hk 1, delete that entry from the `[env]` section of `mise.toml`.

The `pkl` CLI is still useful for debugging (`pkl eval hk.pkl`) and is used by
the `pkl` and `pklformat` steps, so keep it in `mise.toml`.
```

- [ ] **Step 2: README — pitfalls for consumers' own `hk.pkl`**

Directly before the heading `#### Using a pre-defined shared configuration`, insert:
```markdown
#### Writing `hk.pkl` for hk 2

hk 2 evaluates `hk.pkl` with its built-in evaluator (pklr), which currently
mis-evaluates a few valid Pkl constructs **without reporting an error** — the
affected hooks simply run no steps. Avoid these in your own `hk.pkl`:

- Do not name a local property `steps` (`local steps = ...`). hk 2 has a
  top-level `steps` property and the local shadows it; use another name such
  as `local mySteps`.
- Do not amend an imported mapping while adding entries that reference another
  module, e.g. `(Steps.steps) { ["mine"] = Shared.prettier }`. Build a new
  mapping with spread instead: `new Mapping<String, Model.Step> { ...Steps.steps; ["mine"] = Shared.prettier }`.
- Do not filter steps with `is` type tests; use the provided
  `Functions.defaultHooks` (which is written to work around this).

To check a configuration, compare `pkl eval -f json hk.pkl` with
`hk run check --all --plan --json </dev/null`: the step names must match.
This repository runs that comparison in CI (`mise run test:parity`).
```

- [ ] **Step 3: README — update example version and troubleshooting**

- In the sentence `Replace \`<version>\` with the desired release version, e.g. \`2.4.0\`` change `2.4.0` to `3.0.0`.
- In "### Troubleshooting", the paragraph `This may not help in all cases, especially when using remote configurations. You can try to run \`pkl\` directly to see if the configuration is as expected:` stays; after its ` ```sh pkl eval hk.pkl ``` ` block, append:
```markdown
If `pkl eval` shows the expected hooks but hk runs no steps, hk's built-in
evaluator disagrees with the pkl CLI — see _Writing `hk.pkl` for hk 2_ below.
```

- [ ] **Step 4: CLAUDE.md**

- In the architecture tree, change `└── Config.pkl         ← base hk config (extends remote hk v1.39.0 package)` to `└── Config.pkl         ← base hk config (amends the remote hk package; version pinned here and in Builtins.pkl)`.
- In the command table add a row after `Run tests`:
  `| Check evaluator parity      | \`mise run test:parity\` |`
- Under "### Tool versions" append the sentence: `hk itself is pinned in \`Config.pkl\`, \`Builtins.pkl\` and \`mise.toml\` (all updated together by Renovate's "hk" group).`
- Add a new subsection before "### CI":
```markdown
### Pkl constraints (hk 2 / pklr)

hk 2 evaluates configuration with its built-in evaluator, which mis-evaluates
some valid Pkl silently. Never use: `x is SomeClass`; amending an imported
mapping while adding entries that reference another module; a `local steps`
in a module amending `Config.pkl`; `hasProperty`/`getPropertyOrNull`/
`Map.getOrNull`. Use `Dynamic` normalisation and spread (`...X.steps`)
instead, and run `mise run test:parity` after every Pkl change. Details:
`docs/superpowers/specs/2026-09-14-hk-v2-migration-design.md`.
```
- In the "### CI" list, append: `- \`test-steps.yml\` also runs the \`evaluator-parity\` job (required check)`.

- [ ] **Step 5: Lint and verify no stale references remain**

Run:
```bash
grep -rn "HK_PKL_BACKEND" --include='*.md' --include='*.toml' --include='*.yml' --include='*.sh' . | grep -v docs/superpowers
mise x -- hk check --all
```
Expected: the grep prints only the two README sentences that tell users to remove/not set the variable (in the paragraphs added in Step 1) and nothing in `mise.toml`; `hk check --all` passes (prettier formats Markdown — if it reports differences run `mise x -- hk fix --all --step prettier` and re-run).

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document hk 2 requirement and pklr pitfalls"
```

---

### Task 6: Final verification and hand-off

**Files:** none.

- [ ] **Step 1: Full local run**

```bash
mise x -- hk validate
mise run test:parity
mise x -- hk check --all
./test.sh
git log --oneline master..HEAD
```
Expected: valid; parity passed; checks pass; step tests pass (modulo sandbox-blocked installs, which must be listed in the hand-off note); five commits after the spec commit, in this order: `refactor:` (Functions), `refactor:` (spread), `feat!:`, `test:`, `docs:`.

- [ ] **Step 2: Compare with the hk 1 baseline one last time**

```bash
for h in check fix pre-commit pre-push; do
  diff "$SCRATCH/baseline-plan-$h.txt" <(mise x -- hk run "$h" --all --plan -n </dev/null 2>&1 | grep -E '[✓○]' | sed 's/  (.*//' | sort) && echo "$h: same as hk 1"
done
```
Expected: four `same as hk 1` lines.

- [ ] **Step 3: Hand off**

Do not push or open a PR without being asked. Report: the branch name, the commit list, the parity result, any step tests skipped because of the sandbox, and the three upstream issues still to file against `jdx/pklr` (repro material: the constructs named in the spec's "Problem" table).
