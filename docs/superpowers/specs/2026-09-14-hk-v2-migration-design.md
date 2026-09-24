# Design: Migrate hk-config to hk 2 (built-in pklr evaluator)

**Date:** 2026-09-14
**Status:** Approved (design)

## Problem

hk 2.0.0 removes the pkl CLI backend. The `HK_PKL_BACKEND=pkl` setting that
this repo and all consumers rely on is now a hard error, and the built-in
Rust evaluator [pklr](https://github.com/jdx/pklr) (2.0.1, bundled in hk
2.0.0) is the only way hk reads `hk.pkl`.

Our configuration is valid Pkl (the pkl CLI evaluates it correctly), but pklr
mis-evaluates three constructs we use. Each was isolated with minimal
reproductions in a spike on 2026-09-14:

| # | Construct | pklr behaviour | Where we use it |
|---|-----------|----------------|-----------------|
| 1 | `v is SomeClass` type test | Always `true`, for every class in both directions. | `Functions.pkl` (`is Model.ExtendedStep`, `is Config.Step`) |
| 2 | Amending an imported mapping while adding an entry that references another imported module, e.g. `(Default.steps) { ["x"] = Shared.x }` | Fails with a misleading `field not found: <first key>`, or (depending on context) yields entries silently. | `steps/Default.pkl`, `steps/Tofu.pkl`, `steps/Gradle.pkl`, `steps/All.pkl`, `hk.pkl` |
| 3 | `local steps = …` in a module that amends hk's `Config.pkl` | Collides with hk 2's new top-level `steps` property; hooks evaluate to empty step maps with no error. | `hk.pkl` |

Symptoms with the current code under hk 2 are either an evaluation error or,
worse, hooks that run **no steps at all** without any warning.

Other hk 2 changes are compatible with our setup: explicit `hooks[...]` with
their own `steps` remain supported, `prefix` as argv list, `tests`, `profiles`,
`stash`, `exclusive`, `output_summary` and the `Builtins` we amend
(`prettier`, `pkl`, `pkl_format`, `actionlint`, `terraform`, `tofu`) all still
exist with unchanged semantics. `min_hk_version` defaults to `2.0.0` when the
base amends hk@2.0.0.

## Goal

Move this repo to hk 2.0.0 and publish a new **major** release of hk-config
whose configs evaluate identically under hk 2's built-in evaluator and under
the reference pkl CLI, with no loss of functionality:

- same steps in the same hooks (`check`, `fix`, `pre-commit`, `pre-push`) for
  every entry point and every distributable config,
- the `ExtendedStep` flags (`disable_pre_commit`, `disable_pre_push`,
  `disable_check`, `disable_fix`) keep working,
- the consumer API (`configs/*.pkl`, `Shared.pkl`, `Model.pkl`,
  `Functions.defaultHooks`) is unchanged apart from the hk version they carry,
- a CI check catches any future divergence between the two evaluators.

## Non-goals

- Adopting hk 2's top-level shared `steps` map. Our per-hook filtering needs
  explicit hooks; the new map is optional and not needed.
- Fixing pklr itself. We file the three reproductions upstream (see
  _Upstream_), but this design does not wait for fixes.
- Keeping hk 1 as a supported target. hk 1.58.1 with the pkl CLI backend
  happens to evaluate the new configs (verified), but we document hk ≥ 2 as
  the requirement.
- Changing the release/packaging pipeline. `pkl project package` and the
  release-asset flow stay as they are; the pkl CLI remains a dev dependency.

## Design

### 1. Base version bump

`Config.pkl` and `Builtins.pkl` amend hk@2.0.0:

```pkl
amends "package://github.com/jdx/hk/releases/download/v2.0.0/hk@2.0.0#/Config.pkl"
```

`mise.toml` pins `hk = "2.0.0"`, keeps `pkl` (needed for `pkl project package`
and the `pkl`/`pklformat` steps) and **removes** the `[env]` block with
`HK_PKL_BACKEND`. Renovate's existing regex manager for `Config.pkl` /
`Builtins.pkl` keeps matching the URL format, so nothing changes there.

### 2. `Functions.pkl`: filter without `is`

`defaultHooks` keeps its signature. Instead of type-testing each value, it
normalises every entry to a `Dynamic` that always carries the four flags with
their defaults, by spreading the value's `toDynamic()` form over a template.
A plain `Config.Step` has no `step` member, so `step` stays `null`; an
`ExtendedStep` overrides the flags it sets and its `step`.

```pkl
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
  // hand the original typed Step back to hk, never the Dynamic
  local extract = (k, v) -> v.step ?? useSteps[k]

  local precommitSteps = normalized.filter((k, v) -> !v.disable_pre_commit).mapValues(extract).toMapping()
  local prepushSteps   = normalized.filter((k, v) -> !v.disable_pre_push).mapValues(extract).toMapping()
  local checkSteps     = normalized.filter((k, v) -> !v.disable_check).mapValues(extract).toMapping()
  local fixSteps       = normalized.filter((k, v) -> !v.disable_fix).mapValues(extract).toMapping()

  ["pre-commit"] { fix = autofix; stash = "git"; steps = precommitSteps }
  ["pre-push"]   { steps = prepushSteps }
  ["fix"]        { fix = true; steps = fixSteps }
  ["check"]      { steps = checkSteps }
}
```

Verified in the spike: both evaluators produce the same result for plain
steps, `ExtendedStep` wrappers and amended `Builtins` steps.
`Typed` values must go through `toDynamic()` before spreading, otherwise the
pkl CLI rejects the spread. `Model.pkl` is unchanged.

A comment in `Functions.pkl` records *why* `is` is avoided, with a link to the
upstream issue once filed, so nobody "simplifies" it back.

### 3. Step modules: spread instead of amend

Every `(X.steps) { … }` over an imported mapping becomes a fresh mapping that
spreads the imported one:

```pkl
// steps/Default.pkl
steps = new Mapping<String, Model.Step> {
  ...Core.steps
  ["terraform"] = Builtins.terraform
}
```

Same change in `steps/Tofu.pkl`, `steps/Gradle.pkl` and `steps/All.pkl`.
`steps/Core.pkl` already constructs its mapping directly and stays as is.
Semantics are identical in Pkl (later entries override earlier keys, as with
amending).

### 4. Entry points: no `local steps`

`hk.pkl` renames its local to `allSteps` and builds it with a spread:

```pkl
local allSteps = new Mapping<String, Model.Step> {
  ...Steps.steps
  ["hktest"] = new Step { check = "hk test"; exclusive = true }
}

hooks = Functions.defaultHooks(true, allSteps)
```

`hk-test-all.pkl` and `configs/**/*.pkl` have no local of that name and only
need the base bump (they amend `Config.pkl`, so nothing to edit there).

### 5. Evaluator parity check (the regression test)

New script `scripts/check-evaluator-parity.sh`, wired as mise task
`test:parity` and run by `test.sh` and by a new `evaluator-parity` job in
`.github/workflows/test-steps.yml` (ubuntu only; the check is platform
independent).

For each entry point (`hk.pkl`, `hk-test-all.pkl`) and each distributable
config (`configs/*.pkl`, `configs/autofix/*.pkl`), in a temporary copy of the
repository whose `hk.pkl` is replaced: entry points are copied over it, a
distributable config is referenced from a one-line
`amends "./configs/<name>.pkl"` so its relative imports keep resolving:

1. **Oracle:** `pkl eval -f json hk.pkl`, reduced to a sorted list of step
   names per hook (`check`, `fix`, `pre-commit`, `pre-push`).
2. **Subject:** `hk run <hook> --all --plan --json -n -q </dev/null` for the
   same four hooks, reduced to the sorted list of `.steps[].name`. Stdin must
   be closed: `pre-push` otherwise blocks waiting for ref input.
3. Fail on any difference, printing both lists.

The plan lists every configured step, including ones skipped by profile or
glob, so the comparison is on configuration, not on the working tree's files.
The step tests themselves (`hk test`) remain the functional check for the
tools.

The new job is added to `required_checks` in `.wetf-repo.yml` as
`evaluator-parity`, alongside the existing `test-steps (...)` and
`test-docker` entries, so branch protection requires it.

### 6. Documentation

- `README.md`: drop the `HK_PKL_BACKEND` section; state hk ≥ 2.0.0 as
  required; note that the pkl CLI is still useful for `pkl eval` debugging and
  for packaging; add a short "Writing hk.pkl for hk 2" note with the two
  pitfalls consumers can hit themselves (do not name a local `steps`; prefer
  spread over amending an imported mapping when adding entries that reference
  another module); update the example version to the new major.
- `CLAUDE.md`: fix the stale "extends remote hk v1.39.0 package" line to
  describe the version as pinned in `Config.pkl`; mention the parity check in
  the command table.
- `CHANGELOG.md` is generated by the release tooling and is not edited.

### 7. Release

Single PR, commits following Conventional Commits. The commit bumping the hk
base carries a breaking-change footer so the release is a new major:

```
feat!: migrate to hk 2 (built-in pklr evaluator)

BREAKING CHANGE: requires hk >= 2.0.0; remove `HK_PKL_BACKEND` from mise.toml.
```

Consumers migrate by bumping `hk` in their `mise.toml`, deleting the
`HK_PKL_BACKEND` env entry, and pointing their `amends` at the new
hk-config major.

## Upstream

File three issues against `jdx/pklr` with the minimal reproductions from the
spike (each is a 5–10 line `hk.pkl` plus, for #2, two small modules):

1. `is` type test always true for class types.
2. Amending an imported mapping with an entry referencing another imported
   module fails with `field not found: <key>` / drops entries.
3. `local` property shadowing an inherited property (`steps`) breaks evaluation
   of the amending module.

Also suggest to `jdx/hk` that `hk validate` warn when a configured hook has
zero steps, since silent empty hooks were the worst failure mode observed.

## Verification (definition of done)

- `hk validate` passes for `hk.pkl` and `hk-test-all.pkl` under hk 2.0.0.
- `mise run test:parity` passes for all entry points and configs.
- `hk check --all` and `./test.sh` (`hk test`) pass locally under hk 2.0.0.
- Plans for `check`, `fix`, `pre-commit`, `pre-push` under hk 2 match the
  plans hk 1.58.1 + pkl CLI produced on `master` before the migration (spot
  check during implementation; the spike already showed equality for the
  final shape).
- `pkl project package` still builds the package.
- CI (`test-steps.yml` incl. the new parity job, `tf-check-hooks.yml`) green
  on the PR, and `evaluator-parity` listed in `.wetf-repo.yml`
  `required_checks`.

## Risks

- **pklr laziness.** pklr can drop entries silently instead of raising. The
  parity check is the mitigation; it must run on every PR, and Renovate bumps
  of hk go through it automatically.
- **Consumers' own `hk.pkl`.** Repos that copied the `local steps` pattern or
  amend our step mappings in their own file will hit defects #2/#3 without
  any error. The README note is the only lever we have; the release notes
  should repeat it.
- **Upstream fixes changing behaviour.** Once pklr fixes `is`, our
  `normalize` still evaluates identically (it never relied on the bug), so no
  action is needed; the comment can then be relaxed.
