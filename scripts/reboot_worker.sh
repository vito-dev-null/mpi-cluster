#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/cluster_config.sh"
load_cluster_config "$root"
node=${1:?Usage: reboot_worker.sh WORKER}
is_cluster_worker "$node" || { printf 'Target is not a configured worker alias\n' >&2; exit 2; }
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=yes "$node" 'sudo -n systemctl reboot' || {
    printf 'Cannot reboot %s non-interactively: sudo NOPASSWD for /usr/bin/systemctl reboot is not configured.\n' "$node" >&2
    exit 10
}