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
