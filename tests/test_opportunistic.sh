#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/cluster_config.sh"
load_cluster_config "$root"
worker=${MPI_TEST_WORKER:-${MPI_WORKER_LIST[0]}}
ssh_options=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes)
baseline=$(MPI_OPPORTUNISTIC=0 "$root/scripts/discover_nodes.sh" | awk -F: -v node="$worker" '$1 == node {print $2}')
[[ "$baseline" =~ ^[1-9][0-9]*$ ]] || { printf 'Configured test worker is not available\n' >&2; exit 1; }
worker_pid=$(ssh "${ssh_options[@]}" "$worker" 'nohup nice -n 19 yes >/dev/null 2>&1 & echo $!')
cleanup() {
    ssh "${ssh_options[@]}" "$worker" "kill $worker_pid" 2>/dev/null || true
}
trap cleanup EXIT
sleep 1
busy=$(MPI_OPPORTUNISTIC=1 "$root/scripts/discover_nodes.sh" | awk -F: -v node="$worker" '$1 == node {print $2}')
[[ "$busy" =~ ^[0-9]+$ && "$busy" -lt "$baseline" ]] || {
    printf 'Expected fewer opportunistic slots on the busy worker, got %s\n' "$busy" >&2
    exit 1
}
cleanup
trap - EXIT
sleep 1
idle=$(MPI_OPPORTUNISTIC=1 "$root/scripts/discover_nodes.sh" | awk -F: -v node="$worker" '$1 == node {print $2}')
[[ "$idle" == "$baseline" ]] || {
    printf 'Expected %s slots after worker recovery, got %s\n' "$baseline" "$idle" >&2
    exit 1
}
printf 'opportunistic_slots busy=%s recovered=%s\n' "$busy" "$idle"
