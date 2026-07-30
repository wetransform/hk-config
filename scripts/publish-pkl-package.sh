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
