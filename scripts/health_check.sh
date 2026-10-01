#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
printf '=== CONTROLLER DISK ===\n'
df -P -h / | awk 'NR == 1 || NR == 2'
"$root/scripts/check_cluster.sh"
printf 'discovered='
"$root/scripts/discover_nodes.sh" | paste -sd, -