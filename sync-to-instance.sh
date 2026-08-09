#!/usr/bin/env bash
# Upload a file or directory to the current Lambda instance.
#
#   ./sync-to-instance.sh <local-path> [remote-path]
#
# remote-path defaults to /home/ubuntu/<basename of local-path>.
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
    echo "  LAMBDA_INSTANCE_IP=<ip> $0 <local-path> [remote-path]" >&2
    exit 1
fi

local_path="${1:?usage: $0 <local-path> [remote-path]}"
remote_path="${2:-/home/ubuntu/$(basename "$local_path")}"

echo "Uploading $local_path -> ubuntu@$ip:$remote_path"
rsync -avz --progress \
    -e "ssh -i $script_dir/id_ed25519 -o StrictHostKeyChecking=accept-new" \
    "$local_path" "ubuntu@$ip:$remote_path"
