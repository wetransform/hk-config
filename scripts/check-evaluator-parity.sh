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
# entry points, plus every distributable config (discovered, so a new config is never silently unchecked)
targets=(hk.pkl hk-test-all.pkl)
for f in configs/*.pkl configs/autofix/*.pkl; do
  targets+=("$f")
done

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

  for hook in "${hooks[@]}"; do
    if ! expected="$(pkl eval -f json "$dir/hk.pkl" | jq -r --arg h "$hook" '(.hooks[$h].steps // {}) | keys[]' | sort)"; then
      echo "FAIL  $target [$hook]: pkl CLI failed to evaluate the configuration (see output above)"
      failed=1
      continue
    fi
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
  echo "Evaluator parity check FAILED: hk's built-in evaluator disagrees with the pkl CLI."
  echo "Look for Pkl constructs listed under 'Problem' in docs/superpowers/specs/2026-09-14-hk-v2-migration-design.md."
  exit 1
fi
echo "Evaluator parity check passed."
