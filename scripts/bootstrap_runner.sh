#!/usr/bin/env bash
set -euo pipefail

repo_url=${1:?Usage: bootstrap_runner.sh https://github.com/OWNER/REPO}
runner_dir=${RUNNER_DIR:-$HOME/actions-runner}
runner_version=${RUNNER_VERSION:-2.329.0}
runner_name=${RUNNER_NAME:-mpi-controller}

command -v curl >/dev/null || { printf 'curl is required\n' >&2; exit 2; }
command -v tar >/dev/null || { printf 'tar is required\n' >&2; exit 2; }
command -v sudo >/dev/null || { printf 'sudo is required for service installation\n' >&2; exit 2; }
command -v gh >/dev/null || { printf 'gh is required to obtain a short-lived registration token\n' >&2; exit 2; }
sudo -n -v >/dev/null 2>&1 || {
    printf 'Non-interactive sudo is required before runner registration; no token was requested.\n' >&2
    exit 10
}

repo_slug=${repo_url#https://github.com/}
repo_slug=${repo_slug%.git}
registration_token=$(gh api -X POST "repos/$repo_slug/actions/runners/registration-token" --jq .token)
[[ -n "$registration_token" ]] || { printf 'GitHub did not return a registration token\n' >&2; exit 3; }
trap 'unset registration_token' EXIT

mkdir -p "$runner_dir"
cd "$runner_dir"
archive="actions-runner-linux-x64-${runner_version}.tar.gz"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --output "$archive" \
        "https://github.com/actions/runner/releases/download/v${runner_version}/${archive}"
fi
if [[ ! -x ./config.sh ]]; then
    tar xzf "$archive"
fi

./config.sh --unattended --url "$repo_url" --token "$registration_token" \
    --name "$runner_name" \
    --labels "self-hosted,linux,x64,mpi-controller" \
    --work _work --replace

sudo ./svc.sh install "$USER"
sudo ./svc.sh start
./run.sh --version 2>/dev/null || true
printf 'Runner installed on the configured controller. Verify with: systemctl status actions.runner.*\n'