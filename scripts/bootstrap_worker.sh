#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/cluster_config.sh"
load_cluster_config "$root"
node=${1:?Usage: bootstrap_worker.sh WORKER}
stub=$root/lib/libpsm2.so.2
remote_dir=/tmp/mpi-cluster

is_cluster_worker "$node" || { printf 'Target is not a configured worker alias\n' >&2; exit 2; }
[[ -x "$stub" ]] || { printf 'Missing stub: %s\n' "$stub" >&2; exit 2; }
ssh_options=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=yes)
ssh "${ssh_options[@]}" "$node" "mkdir -p '$remote_dir'"
scp "${ssh_options[@]}" -q "$stub" "$node:$remote_dir/libpsm2.so.2"
ssh "${ssh_options[@]}" "$node" "chmod 755 '$remote_dir/libpsm2.so.2'"
local_hash=$(sha256sum "$stub" | cut -d' ' -f1)
remote_hash=$(ssh "${ssh_options[@]}" "$node" "sha256sum '$remote_dir/libpsm2.so.2' | cut -d' ' -f1")
[[ "$local_hash" == "$remote_hash" ]] || { printf 'Stub checksum mismatch on %s\n' "$node" >&2; exit 3; }
printf '%s ready stub_sha256=%s\n' "$node" "$remote_hash"