#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/cluster_config.sh"
load_cluster_config "$root"
controller=$MPI_CONTROLLER
hello=$root/tests/mpi_hello
mpicc -O2 -march=x86-64 -mtune=generic -Wall -Wextra "$root/tests/mpi_hello.c" -o "$hello"
"$root/scripts/run_mpi.sh" "$hello" >/dev/null
discovered=$("$root/scripts/discover_nodes.sh" | paste -sd, -)
printf 'discovered=%s\n' "$discovered"

run_test() {
    local label=$1 hosts=$2 ranks
    ranks=$(awk -F: '{sum += $2} END {print sum}' <<< "${hosts//,/$'\n'}")
    printf '\nTEST %s\n' "$label"
    MPI_CANDIDATES="$MPI_CANDIDATES" MPI_HOSTS="$hosts" MPI_NP="$ranks" MPI_REPORT_BINDINGS=1 "$root/scripts/run_mpi.sh" "$hello"
    printf 'exit=0\n'
}

declare -A slots=()
while IFS=: read -r node count; do
    slots["$node"]=$count
done < <(tr ',' '\n' <<< "$discovered")
run_test "$controller" "$controller:1"
for worker in "${MPI_WORKER_LIST[@]}"; do
    if [[ -n "${slots[$worker]+set}" ]]; then
        run_test "$controller+$worker" "$controller:${slots[$controller]},$worker:${slots[$worker]}"
    fi
done
if [[ "${#slots[@]}" -gt 1 ]]; then
    run_test all-nodes "$discovered"
fi