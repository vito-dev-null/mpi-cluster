#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
source "$script_dir/cluster_config.sh"
load_cluster_config "$repo_root"
local_node=${LOCAL_NODE:-$MPI_CONTROLLER}
candidate_list=$MPI_CANDIDATES
slot_mode=${MPI_SLOT_MODE:-physical}
opportunistic=${MPI_OPPORTUNISTIC:-0}

slots_for_node() {
    local physical=$1 logical=$2 busy_cores=$3 slots
    if [[ "$slot_mode" == logical ]]; then
        slots=$logical
    else
        slots=$physical
    fi
    if [[ "$opportunistic" == 1 ]]; then
        slots=$((slots - busy_cores))
        (( slots < 0 )) && slots=0
    fi
    printf '%s' "$slots"
}

read -r -a candidate_nodes <<< "$candidate_list"
for node in "${candidate_nodes[@]}"; do
    if [[ "$node" == "$local_node" ]]; then
        physical=$(lscpu -p=CORE,SOCKET 2>/dev/null | awk -F, '!/^#/ {seen[$1 "," $2]=1} END {print length(seen)}')
        logical=$(nproc 2>/dev/null || printf '0')
        busy_cores=$(LC_ALL=C ps -eo pcpu=,comm= 2>/dev/null | awk '$2 !~ /^(ps|sshd|bash|sh|awk|sleep)$/ {sum += $1} END {printf "%d", sum / 100}')
        slots=$(slots_for_node "$physical" "$logical" "$busy_cores")
        (( slots < 1 )) && slots=1
        [[ "$slots" -ge 1 ]] && printf '%s:%s\n' "$node" "$slots"
        continue
    fi
    node_address=$(getent ahostsv4 "$node.local" 2>/dev/null | awk 'NR == 1 {print $1}')
    [[ -n "$node_address" ]] || node_address=$node
    ping -c 1 -W 2 "$node_address" >/dev/null 2>&1 || continue
    reported=$(ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=yes "$node" hostname 2>/dev/null) || continue
    physical=$(ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=yes "$node" 'lscpu -p=CORE,SOCKET 2>/dev/null | grep -v "^#" | sort -u | wc -l' 2>/dev/null) || continue
    logical=$(ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=yes "$node" 'nproc' 2>/dev/null) || continue
    busy_cores=$(ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=yes "$node" \
        "LC_ALL=C ps -eo pcpu=,comm= 2>/dev/null | awk '\$2 !~ /^(ps|sshd|bash|sh|awk|sleep)\$/ {sum += \$1} END {printf \"%d\", sum / 100}'" 2>/dev/null) || continue
    [[ -n "$reported" && "$physical" -ge 1 ]] || continue
    slots=$(slots_for_node "$physical" "$logical" "$busy_cores")
    [[ "$slots" -ge 1 ]] && printf '%s:%s\n' "$node" "$slots"
done