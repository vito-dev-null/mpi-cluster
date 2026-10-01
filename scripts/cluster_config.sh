is_valid_host_alias() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
    [[ ! "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

load_cluster_config() {
    local repo_root=$1 config_file line key value worker candidate
    config_file="$repo_root/.env"

    MPI_CONTROLLER=${MPI_CONTROLLER:-}
    MPI_WORKERS=${MPI_WORKERS:-}
    if [[ -r "$config_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=${line#"${line%%[![:space:]]*}"}
            [[ -z "$line" || "$line" == \#* ]] && continue
            [[ "$line" == *=* ]] || continue
            key=${line%%=*}
            value=${line#*=}
            case "$key" in
                MPI_CONTROLLER|MPI_WORKERS) ;;
                *) continue ;;
            esac
            if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$ ]]; then
                printf 'Invalid %s value in local .env configuration\n' "$key" >&2
                return 2
            fi
            if [[ "$key" == MPI_CONTROLLER && -z "${MPI_CONTROLLER:-}" ]]; then
                MPI_CONTROLLER=$value
            elif [[ "$key" == MPI_WORKERS && -z "${MPI_WORKERS:-}" ]]; then
                MPI_WORKERS=$value
            fi
        done < "$config_file"
    fi

    MPI_CONTROLLER=${MPI_CONTROLLER:-localhost}
    MPI_WORKERS=${MPI_WORKERS:-worker1,worker2}
    if [[ ! "$MPI_WORKERS" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(,[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]] ||
        ! is_valid_host_alias "$MPI_CONTROLLER"; then
        printf 'Invalid cluster host configuration; use SSH aliases, not credentials or addresses\n' >&2
        return 2
    fi

    IFS=, read -r -a MPI_WORKER_LIST <<< "$MPI_WORKERS"
    for worker in "${MPI_WORKER_LIST[@]}"; do
        if ! is_valid_host_alias "$worker"; then
            printf 'Invalid worker alias in local cluster configuration\n' >&2
            return 2
        fi
        if [[ "$worker" == "$MPI_CONTROLLER" ]]; then
            printf 'Controller and worker aliases must be different\n' >&2
            return 2
        fi
    done
    MPI_CANDIDATES=${MPI_CANDIDATES:-"$MPI_CONTROLLER ${MPI_WORKER_LIST[*]}"}
    read -r -a candidate_list <<< "$MPI_CANDIDATES"
    for candidate in "${candidate_list[@]}"; do
        if ! is_valid_host_alias "$candidate"; then
            printf 'Invalid candidate alias in local cluster configuration\n' >&2
            return 2
        fi
    done
}

is_cluster_worker() {
    local worker
    for worker in "${MPI_WORKER_LIST[@]}"; do
        [[ "$worker" == "$1" ]] && return 0
    done
    return 1
}