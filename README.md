# hk-config

Shared configurations for managing pre-commit and pre-push git hooks using [hk](https://hk.jdx.dev).

## Using hk

If you have a repository where a configuration was already set up using hk, you can simply run:

```sh
hk install --mise
```

If hk is not installed yet, you should be able to install it, including required tools, using mise (`mise install`).

The command will install the git hooks defined in the configuration in your local repository.
With this set up, the defined hooks will be executed automatically on the respective git actions (e.g. pre-commit, pre-push).
Usually this consists of running checks like code formatting, linting, or running tests.

By convention, we set up a check in GitHub Actions that runs the checks for all files on a pull request.

Sometimes it may be required to run checks or fixes manually on all files, for example when changing the configuration of the hooks or then first introducing the checks.

You can run the checks manually using:

```sh
hk check --all
```

You can run fixes manually using:

```sh
hk fix --all
```

### Troubleshooting

It can be that `hk` uses an outdated configuration because of its internal caching mechanism.
In this case you can clear the cache using:

```sh
hk cache clear
```

This may not help in all cases, especially when using remote configurations.
You can try to run `pkl` directly to see if the configuration is as expected:

```sh
pkl eval hk.pkl
```

If the configuration is not as expected it may be that the remote file is cached by `pkl`.
It is unclear though how to clear the `pkl` cache in this case, solution is usually to change the URL (e.g. by using a different tag or commit hash).

## Setting up hk in a new repository

As a prerequisite for all setups with hk we set up a mise configuration.
First, make sure you have [mise](https://mise.jdx.dev) installed.

Create a `mise.toml` file in the root of your repository or extend the existing one and add the tools `hk` and `pkl`.

You can do this using the following command:

```sh
mise use hk pkl
```

The respective section in the `mise.toml` file should look like this:

```toml
[tools]
hk = "latest"
pkl = "latest"
```

If experimental features are enabled in your mise setup, you can add a `postinstall` hook to automatically install the git hooks after running `mise install`:

```toml
[hooks]
postinstall = "hk install --mise"
```

### Setting up the hk configuration

Create a file `hk.pkl` in the root of your repository.

You have the option to

1. use a pre-defined shared configuration from this repository (see `configs/` folder)
2. reuse shared pre-defined linter configurations from this repository (see `Shared.pkl`)
3. define your own configuration from scratch

For the last option please refer to the [hk documentation](https://hk.jdx.dev/).

Depending on your configuration it is important to also add the required tools (e.g. `actionlint`, `prettier`, etc.) to your `mise.toml` file.

#### Using a pre-defined shared configuration

Example content of `hk.pkl` using a shared configuration:

```pkl
amends "https://raw.githubusercontent.com/wetransform/hk-config/refs/tags/<tag>/configs/Default.pkl"
```

Make sure to replace `<tag>` with the desired version tag, e.g. `v1.0.2`.

#### Reusing shared linter configurations

Example content of `hk.pkl` reusing shared linter configurations:

```pkl
amends "https://raw.githubusercontent.com/wetransform/hk-config/refs/tags/<tag>/Config.pkl"
import "https://raw.githubusercontent.com/wetransform/hk-config/refs/tags/<tag>/Builtins.pkl"
import "https://raw.githubusercontent.com/wetransform/hk-config/refs/tags/<tag>/Shared.pkl"

local linters = new Mapping<String, Step> {
  // use shared linters from Shared.pkl
  ["prettier"] = Shared.prettier
  ["pkl"] = Shared.pkl
  ["actionlint"] = Shared.actionlint
}

hooks {
  ["pre-commit"] {
    fix = true    // automatically modify files with available linter fixes
    stash = "git" // stashes unstaged changes while running fix steps
    steps = linters
  }
  // instead of pre-commit, you can instead define pre-push hooks
  ["pre-push"] {
    steps = linters
  }
  // "fix" and "check" are special steps for `hk fix` and `hk check` commands
  ["fix"] {
    fix = true
    steps = linters
  }
  ["check"] {
    steps = linters
  }
}
```

You can also reuse the function that creates the hooks mapping to avoid boilerplate code:

```pkl
amends "https://raw.githubusercontent.com/wetransform/hk-config/refs/tags/<tag>/Config.pkl"
import "https://raw.githubusercontent.com/wetransform/hk-config/refs/tags/<tag>/Shared.pkl"
import "https://raw.githubusercontent.com/wetransform/hk-config/refs/tags/<tag>/Functions.pkl"

local linters = new Mapping<String, Step> {
  // use shared linters from Shared.pkl
  ["prettier"] = Shared.prettier
  ["pkl"] = Shared.pkl
  ["actionlint"] = Shared.actionlint
}

hooks = Functions.defaultHooks(true, linters)
```
