#!/usr/bin/env bash
set -euo pipefail

# Evaluator parity check.
#
# hk >= 2 evaluates hk.pkl with its built-in Rust evaluator (pklr) instead of
# the pkl CLI. Where pklr disagrees with the reference implementation it may
# silently drop steps or whole hooks rather than fail. This script compares,
# for every entry point and distributable config, the step names hk plans per
# hook with the step names the pkl CLI renders.
#
# Requires hk (>= 2), pkl, jq and git on PATH; run it via `mise run test:parity`.

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

hooks=(check fix pre-commit pre-push)
# entry points, plus every distributable config (discovered, so a new config is never silently unchecked)
targets=(hk.pkl hk-test-all.pkl)
for f in configs/*.pkl configs/autofix/*.pkl; do
  targets+=("$f")
done

# the pkl CLI ignores the proxy environment variables
pkl_args=()
proxy="${HTTPS_PROXY:-${https_proxy:-}}"
if [ -n "$proxy" ]; then
  pkl_args+=(--http-proxy "$proxy")
fi

# GNU mktemp accepts a bare -d; BSD/macOS mktemp may require a template
work="$(mktemp -d 2>/dev/null || mktemp -d -t hk-parity)"
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

  if ! rendered="$(pkl eval "${pkl_args[@]}" -f json "$dir/hk.pkl")"; then
    echo "FAIL  $target: pkl CLI failed to evaluate the configuration (see output above)"
    failed=1
    continue
  fi

  for hook in "${hooks[@]}"; do
    expected="$(jq -r --arg h "$hook" '(.hooks[$h].steps // {}) | keys[]' <<<"$rendered" | sort)"
    # stdin must be closed: `pre-push` otherwise waits for ref input
    if ! actual="$(hk --cd "$dir" run "$hook" --all --plan --json -n -q </dev/null | sed -n '/^{/,$p' | jq -r '.steps[].name' | sort)"; then
      echo "FAIL  $target [$hook]: hk failed to evaluate the configuration (see output above)"
      failed=1
      continue
    fi

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
  echo "Evaluator parity check FAILED: hk's built-in evaluator (pklr) disagrees with the pkl CLI."
  echo "Reduce the difference to a minimal Pkl file and report it at https://github.com/jdx/pklr/issues."
  exit 1
fi
echo "Evaluator parity check passed."
