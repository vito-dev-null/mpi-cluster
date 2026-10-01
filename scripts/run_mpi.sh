#!/usr/bin/env bash
set -euo pipefail

cluster_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
discovery=$cluster_dir/scripts/discover_nodes.sh
stub=$cluster_dir/lib/libpsm2.so.2
remote_dir=/tmp/mpi-cluster
source "$cluster_dir/scripts/cluster_config.sh"
load_cluster_config "$cluster_dir"
controller=$MPI_CONTROLLER
candidate_list=$MPI_CANDIDATES
ssh_options=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes)
nodes=()

[[ $# -ge 1 ]] || { printf 'Usage: %s PROGRAM [ARGS...]\n' "$0" >&2; exit 2; }
program=$1
shift
[[ -x "$program" ]] || { printf 'Program is not executable: %s\n' "$program" >&2; exit 2; }
[[ -r "$stub" ]] || { printf 'Missing persistent PSM2 stub: %s\n' "$stub" >&2; exit 2; }
[[ -x "$discovery" ]] || { printf 'Missing discovery script: %s\n' "$discovery" >&2; exit 2; }

hosts=$(LOCAL_NODE="$controller" MPI_CANDIDATES="$candidate_list" \
    MPI_OPPORTUNISTIC="${MPI_OPPORTUNISTIC:-0}" MPI_SLOT_MODE="${MPI_SLOT_MODE:-physical}" \
    "$discovery" | paste -sd, -)
[[ -n "$hosts" ]] || { printf 'No reachable MPI nodes discovered\n' >&2; exit 10; }
[[ "$hosts" == "$controller":* ]] || { printf 'Configured controller is unavailable\n' >&2; exit 11; }
printf 'Discovered MPI nodes: %s\n' "$hosts" >&2

read -r -a discovered_nodes <<< "${hosts//,/ }"
for node in "${discovered_nodes[@]}"; do
    if [[ "$node" != "$controller":* ]]; then
        nodes+=("${node%%:*}")
    fi
done

name=$(basename "$program")
[[ "$name" =~ ^[A-Za-z0-9._+-]+$ ]] || {
    printf 'Program name contains unsupported characters\n' >&2
    exit 2
}
local_hash=$(sha256sum "$program" | awk '{print $1}')
stub_hash=$(sha256sum "$stub" | awk '{print $1}')
mkdir -p "$remote_dir"
install -m 755 "$program" "$remote_dir/$name"
install -m 755 "$stub" "$remote_dir/libpsm2.so.2"
for node in "${nodes[@]}"; do
    ssh "${ssh_options[@]}" "$node" "mkdir -p '$remote_dir'"
    scp "${ssh_options[@]}" -q "$program" "$node:$remote_dir/$name"
    scp "${ssh_options[@]}" -q "$stub" "$node:$remote_dir/libpsm2.so.2"
    ssh "${ssh_options[@]}" "$node" "chmod 755 '$remote_dir/$name' '$remote_dir/libpsm2.so.2'"
    remote_hash=$(ssh "${ssh_options[@]}" "$node" "sha256sum '$remote_dir/$name' | cut -d' ' -f1")
    remote_stub_hash=$(ssh "${ssh_options[@]}" "$node" "sha256sum '$remote_dir/libpsm2.so.2' | cut -d' ' -f1")
    [[ "$remote_hash" == "$local_hash" ]] || { printf 'Program checksum mismatch on %s\n' "$node" >&2; exit 12; }
    [[ "$remote_stub_hash" == "$stub_hash" ]] || { printf 'Stub checksum mismatch on %s\n' "$node" >&2; exit 13; }
done

host_option=${MPI_HOSTS:-$hosts}
declare -A discovered_slots=()
while IFS=: read -r node slots; do
    discovered_slots["$node"]=$slots
done < <(tr ',' '\n' <<< "$hosts")
read -r -a requested_hosts <<< "${host_option//,/ }"
for host in "${requested_hosts[@]}"; do
    IFS=: read -r node requested_slots <<< "$host"
    is_valid_host_alias "$node" && [[ "$requested_slots" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Invalid MPI host specification: %s\n' "$host" >&2
        exit 16
    }
    [[ -n "${discovered_slots[$node]+set}" ]] || {
        printf 'Requested MPI node was not discovered: %s\n' "$node" >&2
        exit 16
    }
    [[ "$requested_slots" -le "${discovered_slots[$node]}" ]] || {
        printf 'Requested %s slots on %s but discovery reported %s\n' \
            "$requested_slots" "$node" "${discovered_slots[$node]}" >&2
        exit 16
    }
done
available_slots=$(awk -F: '{sum += $2} END {print sum}' <<< "${host_option//,/$'\n'}")
np=${MPI_NP:-$available_slots}
[[ "$np" =~ ^[1-9][0-9]*$ ]] || {
    printf 'MPI_NP must be a positive integer (received %s)\n' "$np" >&2
    exit 16
}
[[ "$np" -le "$available_slots" ]] || {
    printf 'Requested %s ranks but only %s physical slots are available (%s)\n' "$np" "$available_slots" "$host_option" >&2
    exit 16
}
if [[ "${MPI_SLOT_MODE:-physical}" == logical ]]; then
    map_args=(--map-by hwthread --bind-to hwthread)
else
    map_args=(--map-by slot --bind-to core)
fi
exec mpirun --host "$host_option" -np "$np" \
    "${map_args[@]}" ${MPI_REPORT_BINDINGS:+--report-bindings} \
    --mca pml ob1 --mca btl self,tcp \
    -x LD_LIBRARY_PATH="$remote_dir" "$remote_dir/$name" "$@"