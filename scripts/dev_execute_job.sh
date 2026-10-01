#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 2 ]] || {
    printf 'Usage: %s TYPE COMMAND [ARGS...]\n' "$0" >&2
    exit 2
}
job_type=$1
shift
job_root=${DEV_JOB_ROOT:-/tmp/mpi-cluster/jobs}
mkdir -p "$job_root"
job_id="${job_type}-$(date +%Y%m%d-%H%M%S)-$$"
job_file="$job_root/$job_id.running"
started=$(date --iso-8601=seconds)
printf 'job=%s\ntype=%s\nstarted=%s\ncommand=%q ' "$job_id" "$job_type" "$started" "$1" >"$job_file"
printf '%q ' "$@" >>"$job_file"
printf '\n' >>"$job_file"

finish() {
    result=$?
    finished=$(date --iso-8601=seconds)
    mv "$job_file" "$job_root/$job_id.done" 2>/dev/null || true
    printf 'job=%s type=%s status=%s finished=%s\n' "$job_id" "$job_type" \
        "$([[ "$result" -eq 0 ]] && echo COMPLETED || echo FAILED)" "$finished" >&2
    return "$result"
}
trap finish EXIT
printf 'JOB %s TYPE %s STATUS RUNNING\n' "$job_id" "$job_type" >&2
"$@"
