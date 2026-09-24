#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

hk cache clear

# make sure hk's built-in evaluator and the pkl CLI agree before running step tests
mise run test:parity

cp hk.pkl hk.pkl.bak
trap 'mv hk.pkl.bak hk.pkl; hk cache clear' EXIT

cp hk-test-all.pkl hk.pkl
mise x -- hk test "$@"
