#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
discovery=$root/scripts/discover_nodes.sh
source "$root/scripts/cluster_config.sh"
load_cluster_config "$root"
controller=$MPI_CONTROLLER
nodes=("$controller" "${MPI_WORKER_LIST[@]}")
ssh_options=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=yes)
failed=0
printf '=== NODE STATUS ===\n'
online=()
controller_online=0
for node in "${nodes[@]}"; do
    if [[ "$node" == "$controller" ]]; then
        node_address=127.0.0.1
    else
        node_address=$(getent ahostsv4 "$node.local" 2>/dev/null | awk 'NR == 1 {print $1}')
        [[ -n "$node_address" ]] || node_address=$node
    fi
    if ! ping -c 1 -W 2 "$node_address" >/dev/null 2>&1; then
        printf '%s OFFLINE ping=FAIL ssh=FAIL\n' "$node"
        failed=1
        continue
    fi
    if [[ "$node" == "$controller" ]] || ssh "${ssh_options[@]}" "$node" hostname >/dev/null 2>&1; then
        printf '%s ONLINE ping=OK ssh=OK\n' "$node"
        online+=("$node")
        [[ "$node" == "$controller" ]] && controller_online=1
    else
        printf '%s DEGRADED ping=OK ssh=FAIL\n' "$node"
        failed=1
    fi
    printf 'latency_%s=' "$node"
    ping -c 3 -W 2 "$node_address" 2>/dev/null | awk -F'=' '/rtt/ {print $2}'
done

printf '\n=== CPU / MPI ===\n'
for node in "${online[@]}"; do
    if [[ "$node" == "$(hostname)" ]]; then
        command='physical=$(lscpu -p=CORE,SOCKET | awk -F, '\''!/^#/ {seen[$1 "," $2]=1} END {print length(seen)}'\''); printf "physical_cores=%s logical_cpus=%s\n" "$physical" "$(nproc)"; mpirun --version 2>&1 | head -1; ompi_info --version 2>&1 | head -1; dpkg-query -W -f="${binary:Package} ${Version}\n" openmpi-bin libopenmpi40 libpmix2t64 libprrte3 libfabric1 libucx0 libucc1 libpsm2-2 2>/dev/null | grep -E "^(openmpi-bin|libopenmpi40|libpmix2t64|libprrte3|libfabric1|libucx0|libucc1|libpsm2-2)" || true'
        bash -lc "$command"
    else
        ssh "${ssh_options[@]}" "$node" 'physical=$(lscpu -p=CORE,SOCKET | awk -F, '\''!/^#/ {seen[$1 "," $2]=1} END {print length(seen)}'\''); printf "physical_cores=%s logical_cpus=%s\n" "$physical" "$(nproc)"; mpirun --version 2>&1 | head -1; ompi_info --version 2>&1 | head -1; dpkg-query -W -f="${binary:Package} ${Version}\n" openmpi-bin libopenmpi40 libpmix2t64 libprrte3 libfabric1 libucx0 libucc1 libpsm2-2 2>/dev/null | grep -E "^(openmpi-bin|libopenmpi40|libpmix2t64|libprrte3|libfabric1|libucx0|libucc1|libpsm2-2)" || true'
    fi
done

printf '\n=== DYNAMIC MPI WORKERS ===\n'
discovered=$($discovery 2>/dev/null | paste -sd, - || true)
printf 'available=%s\n' "${discovered:-none}"

printf '\n=== PSM2 WORKAROUND ===\n'
if [[ -x "$root/lib/libpsm2.so.2" ]]; then
    printf 'persistent_stub=OK sha256='
    sha256sum "$root/lib/libpsm2.so.2" | cut -d' ' -f1
else
    printf 'persistent_stub=FAIL\n'
    failed=1
fi

printf '\n=== FINAL ===\n'
if [[ "$failed" -eq 0 && "${#online[@]}" -eq "${#nodes[@]}" ]]; then
    printf 'CLUSTER READY\n'
elif [[ "${#online[@]}" -gt 0 ]]; then
    printf 'CLUSTER DEGRADED\n'
else
    printf 'CLUSTER NOT READY\n'
fi
[[ "$controller_online" -eq 1 && -x "$root/lib/libpsm2.so.2" ]] && exit 0
exit 1