#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/cluster_config.sh"
load_cluster_config "$root"
controller=$MPI_CONTROLLER
program=$root/bin/mpi_benchmark
iterations=${ITERATIONS:-120000000}
repeats=${REPEATS:-3}
results_file=$(mktemp)
error_file=$(mktemp)
trap 'rm -f "$results_file" "$error_file"' EXIT

[[ -x "$program" ]] || { printf 'Missing benchmark: %s\n' "$program" >&2; exit 2; }
discovered=$("$root/scripts/discover_nodes.sh" | paste -sd, -)
printf 'discovered=%s\n' "$discovered" >&2
printf 'configuration,run,ranks,seconds\n' | tee "$results_file"
declare -A slots=()
while IFS=: read -r node count; do
    slots["$node"]=$count
done < <(printf '%s\n' "$discovered" | tr ',' '\n')
configurations=("$controller")
available_workers=()
for worker in "${MPI_WORKER_LIST[@]}"; do
    if [[ -n "${slots[$worker]+set}" ]]; then
        configurations+=("$controller+$worker")
        available_workers+=("$worker")
    fi
done
if [[ "${#available_workers[@]}" -gt 1 ]]; then
    configurations+=("$controller+${available_workers[*]// /+}")
fi
for configuration in "${configurations[@]}"; do
    IFS=+ read -r -a configuration_nodes <<< "$configuration"
    host_entries=()
    for node in "${configuration_nodes[@]}"; do
        host_entries+=("$node:${slots[$node]}")
    done
    hosts=$(IFS=,; printf '%s' "${host_entries[*]}")
    ranks=$(awk -F: '{sum += $2} END {print sum}' <<< "${hosts//,/$'\n'}")
    for run in $(seq 1 "$repeats"); do
        if ! output=$(MPI_CANDIDATES="$MPI_CANDIDATES" MPI_HOSTS="$hosts" MPI_NP="$ranks" \
            "$root/scripts/run_mpi.sh" "$program" "$iterations" 2>"$error_file"); then
            cat "$error_file" >&2
            exit 1
        fi
        seconds=$(awk -F'seconds=' '/^RESULT / {split($2, fields, " "); print fields[1]}' <<< "$output")
        [[ -n "$seconds" ]] || { cat "$error_file" >&2; exit 1; }
        printf '%s,%s,%s,%s\n' "$configuration" "$run" "$ranks" "$seconds" | tee -a "$results_file"
    done
done

printf '\n=== SUMMARY ===\n'
LC_ALL=C awk -F, -v baseline_name="$controller" '
NR == 1 { next }
{
    sum[$1] += $4
    count[$1]++
    if (!($1 in min) || $4 < min[$1]) min[$1] = $4
    if (!($1 in max) || $4 > max[$1]) max[$1] = $4
    ranks[$1] = $3
}
END {
    baseline = sum[baseline_name] / count[baseline_name]
    for (name in sum) {
        average = sum[name] / count[name]
        speedup = baseline / average
        efficiency = speedup / (ranks[name] / 2)
        printf "%s average=%.6f min=%.6f max=%.6f speedup=%.3f efficiency=%.3f\n", name, average, min[name], max[name], speedup, efficiency
    }
}' "$results_file" | sort