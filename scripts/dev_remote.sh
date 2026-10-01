#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/cluster_config.sh"
load_cluster_config "$root"
[[ $# -ge 1 ]] || { printf 'Usage: %s WORKER [COMMAND... ]\n' "$0" >&2; exit 2; }
node=$1
shift
is_cluster_worker "$node" || {
    printf 'Target is not a configured worker alias\n' >&2
    exit 2
}
ssh_options=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes)
if [[ $# -eq 0 ]]; then
    exec ssh "${ssh_options[@]}" -t "$node"
fi
exec ssh "${ssh_options[@]}" "$node" -- "$@"
