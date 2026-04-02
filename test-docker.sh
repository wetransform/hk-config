#!/usr/bin/env bash
set -euo pipefail

# Run step tests in a minimal Debian Docker container.
# Skips steps that require dependencies not present in a minimal environment:
# - prettier, renovate: require npm/node
# - detectsecrets: requires uv or pipx
#
# Usage: ./test-docker.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat > /tmp/hk-docker-test.sh << 'TESTSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
apt-get update -qq && apt-get install -y -qq curl git
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
export MISE_YES=1
mise install
cp hk.pkl hk.pkl.bak
trap 'mv hk.pkl.bak hk.pkl; hk cache clear' EXIT
cp hk-test-all.pkl hk.pkl
skip_steps="prettier renovate detectsecrets"
pattern=$(echo "$skip_steps" | tr ' ' '\n' | sed 's/.*$/^&$/' | paste -sd'|')
step_args=()
while IFS= read -r step; do
    [[ -n "$step" ]] && step_args+=(--step "$step")
done < <(hk test --list | awk -F ' :: ' 'NF==2{print $1}' | sort -u | grep -Ev "$pattern")
hk test -v "${step_args[@]}"
TESTSCRIPT
chmod +x /tmp/hk-docker-test.sh

docker run --rm \
    -v "$REPO_ROOT:/workspace" \
    -v "/tmp/hk-docker-test.sh:/hk-docker-test.sh" \
    -w /workspace \
    debian:bookworm-slim \
    /hk-docker-test.sh
