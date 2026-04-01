# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**hk-config** is a shared configuration library for [hk](https://hk.jdx.dev) (a git hooks manager). It provides reusable, composable Pkl configurations for linting and code quality that other repositories can import and amend.

## Common commands

Tools are managed via [mise](https://mise.jdx.dev). Install them with:

```sh
hk install --mise
```

| Task                        | Command           |
| --------------------------- | ----------------- |
| Run all checks on all files | `hk check --all`  |
| Run all auto-fixes          | `hk fix --all`    |
| Run tests                   | `./test.sh`       |
| Evaluate Pkl config         | `pkl eval hk.pkl` |
| Clear hk cache              | `hk cache clear`  |

## Architecture

The configuration is written in [Pkl](https://pkl-lang.org) (Apple's configuration-as-code language) and follows a composition pattern using `amends` and `import`.

### Layer structure

```
hk.pkl / hk-test-all.pkl          ← entry points (this repo's own hooks)
configs/Default.pkl                ← distributable configs for consumers
configs/autofix/Default.pkl        ← same, with autofix enabled
configs/Gradle.pkl                 ← Gradle variant (adds Spotless)
    └── steps/Default.pkl          ← step definitions (what tools to run)
        └── Shared.pkl             ← central step library (tool versions + config)
            └── Config.pkl         ← base hk config (extends remote hk v1.39.0 package)
```

**Key files:**

- **Shared.pkl** — Central registry defining all linting/validation steps with pinned tool versions (prettier, actionlint, gitleaks, renovate, yaml-schema, etc.). This is the primary file to edit when adding or updating tools.
- **Model.pkl** — Defines `ExtendedStep`, a custom type extending the remote hk `Step` with additional fields.
- **Functions.pkl** — Contains `defaultHooks()`, a helper that maps steps to `pre-commit`/`pre-push` hooks.
- **steps/\*.pkl** — Compose subsets of steps from `Shared.pkl` for different project types.
- **configs/\*.pkl** — Full hook configurations for consumer repos to `amend`.

### How consumers use this repo

Other repos import from this repo's GitHub releases:

```pkl
amends "package://pkg.pkl-lang.org/github.com/wetransform-os/hk-config@2.2.0#/configs/Default.pkl"
```

### Tool versions

All tool versions are pinned in `Shared.pkl` as module-level properties and updated automatically by Renovate. The `mise.toml` pins hk and pkl versions for this repo's own development.

### CI

- `test-steps.yml` — Runs all steps on Ubuntu, macOS, and Windows
- `tf-check-hooks.yml` — Runs hook checks on PRs
- Secret scanning runs on every push via `tf-scan-for-secrets.yml`
