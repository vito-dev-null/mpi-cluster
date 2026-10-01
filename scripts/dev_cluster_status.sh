#!/usr/bin/env bash
set -u

source "$(dirname "${BASH_SOURCE[0]}")/cluster_config.sh"
load_cluster_config "$root"
controller=$MPI_CONTROLLER
nodes=("$controller" "${MPI_WORKER_LIST[@]}")
ssh_options=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=yes)
failed=0

probe_node() {
    local node=$1
    printf '\n=== %s ===\n' "$node"
    if [[ "$node" == "$controller" ]]; then
        bash -s
    else
        if ! ssh "${ssh_options[@]}" "$node" bash -s; then
            printf 'ssh=FAIL\n'
            failed=1
        fi
    fi <<'EOF'
. /etc/os-release 2>/dev/null && printf 'os=%s\n' "$PRETTY_NAME"
printf 'kernel=%s\n' "$(uname -sr)"
printf 'physical_cores='; lscpu -p=CORE,SOCKET 2>/dev/null | awk -F, '!/^#/ {seen[$1 "," $2]=1} END {print length(seen)}'
printf 'logical_cpus=%s\n' "$(nproc 2>/dev/null || true)"
printf 'ram='; free -h 2>/dev/null | awk '/Mem:/ {print $2 " total, " $7 " available"}'
printf 'ram_used='; free -h 2>/dev/null | awk '/Mem:/ {print $3}'
printf 'load='; awk '{print $1}' /proc/loadavg 2>/dev/null
printf 'disk='; df -P -h / 2>/dev/null | awk 'NR == 2 {print $2 " total, " $4 " free (" $5 " used)"}'
printf 'ssh_service='; systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || true
printf 'mpi='; mpirun --version 2>/dev/null | head -1 || printf 'missing\n'
printf 'gcc='; gcc --version 2>/dev/null | head -1 || printf 'missing\n'
printf 'python='; python3 --version 2>/dev/null || printf 'missing\n'
printf 'containers='; (docker --version 2>/dev/null || podman --version 2>/dev/null || printf 'none\n')
printf 'gpu='; (lspci 2>/dev/null | grep -Ei 'vga|3d|display' || printf 'none detected\n')
printf 'cuda_rocm='; (command -v nvcc || command -v rocminfo || printf 'none\n')
EOF
}

for node in "${nodes[@]}"; do
    node_address=127.0.0.1
    if [[ "$node" != "$controller" ]]; then
        node_address=$(getent ahostsv4 "$node.local" 2>/dev/null | awk 'NR == 1 {print $1}')
        [[ -n "$node_address" ]] || node_address=$node
    fi
    if ! ping -c 1 -W 2 "$node_address" >/dev/null 2>&1; then
        printf '\n=== %s ===\nping=FAIL\n' "$node"
        failed=1
        continue
    fi
    probe_node "$node"
done

printf '\n=== MPI DISCOVERY ===\n'
discovery_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if discovered=$($discovery_dir/discover_nodes.sh 2>/dev/null | paste -sd, -); then
    printf 'nodes=%s\n' "${discovered:-none}"
    total_slots=0
    ram_values=()
    while IFS=: read -r node slots; do
        total_slots=$((total_slots + slots))
        if [[ "$node" == "$controller" ]]; then
            ram_values+=("$(LC_ALL=C awk '/MemTotal/ {printf "%s ", $2/1048576} /MemAvailable/ {printf "%s\n", $2/1048576}' /proc/meminfo)")
        else
            ram_values+=("$(ssh "${ssh_options[@]}" "$node" \
                'LC_ALL=C awk '\''/MemTotal/ {printf "%s ", $2/1048576} /MemAvailable/ {printf "%s\n", $2/1048576}'\'' /proc/meminfo' \
                </dev/null 2>/dev/null || printf '0 0\n')")
        fi
    done < <(printf '%s\n' "$discovered" | tr ',' '\n')
    ram_summary=$(LC_ALL=C printf '%s\n' "${ram_values[@]}" | LC_ALL=C awk '{total += $1; available += $2} END {printf "%.1f GiB total, %.1f GiB available", total, available}')
    printf 'TOTAL AVAILABLE CPU=%s physical slots\n' "$total_slots"
    printf 'TOTAL DISTRIBUTED RAM=%s (separate node memory domains)\n' "$ram_summary"
else
    printf 'nodes=FAIL\n'
    failed=1
fi

printf '\n=== RESULT ===\n'
if [[ "$failed" -eq 0 ]]; then
    printf 'DEV CLUSTER READY\n'
else
    printf 'DEV CLUSTER DEGRADED\n'
fi

printf '\n=== CONTROL PLANE ===\n'
job_root=${DEV_JOB_ROOT:-/tmp/mpi-cluster/jobs}
active_jobs=$(find "$job_root" -maxdepth 1 -name '*.running' -type f 2>/dev/null | sort || true)
if [[ -n "$active_jobs" ]]; then
    printf '%s\n' "$active_jobs" | sed 's#^.*/##; s/\.running$//' | while read -r job; do
        printf 'ACTIVE JOB %s\n' "$job"
    done
else
    printf 'ACTIVE JOBS none\n'
fi
printf 'BUILD WORKLOAD '
ps -eo comm= | grep -Eq '^(make|cmake|ninja|mpicc|gcc|g\+\+)$' && printf 'ACTIVE\n' || printf 'none\n'
printf 'AI WORKLOAD '
ps -eo comm= | grep -Eq '^(ollama|llama-server|llama-cli|vllm)$' && printf 'ACTIVE\n' || printf 'none\n'
exit "$failed"
