#!/usr/bin/env bash
# Download a file or directory from the current Lambda instance.
#
#   ./sync-from-instance.sh <remote-path> [local-path]
#
# local-path defaults to ./downloads/<basename of remote-path>.
#
# The instance IP changes every time you launch a new instance, so it's read
# from secrets/instance_ip (one line, just the IP) rather than hardcoded —
# keep that file updated. Override for a single call without touching the
# file with LAMBDA_INSTANCE_IP=<ip>.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ip="${LAMBDA_INSTANCE_IP:-$(cat "$script_dir/secrets/instance_ip" 2>/dev/null | tr -d '[:space:]')}"

if [[ -z "$ip" ]]; then
    echo "ERROR: no instance IP found." >&2
    echo "  Put it in secrets/instance_ip (one line, just the IP), or run:" >&2
    echo "  LAMBDA_INSTANCE_IP=<ip> $0 <remote-path> [local-path]" >&2
    exit 1
fi

remote_path="${1:?usage: $0 <remote-path> [local-path]}"
local_path="${2:-$script_dir/downloads/$(basename "$remote_path")}"

mkdir -p "$(dirname "$local_path")"
echo "Downloading ubuntu@$ip:$remote_path -> $local_path"
rsync -avz --progress \
    -e "ssh -i $script_dir/id_ed25519 -o StrictHostKeyChecking=accept-new" \
    "ubuntu@$ip:$remote_path" "$local_path"
