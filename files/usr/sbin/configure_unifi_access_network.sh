#!/usr/bin/env bash

set -euo pipefail

network_id="${ACCESS_MNGT_NETWORK_ID:-}"
network_ip="${ACCESS_MNGT_NETWORK_IP:-}"
device_mtu="${ACCESS_DEVICE_MTU:-1200}"
access_api="${ACCESS_API_URL:-http://127.0.0.1:12080}"

if [ -z "$network_id" ] && [ -n "$network_ip" ]; then
    network_id="$(ip -o -4 addr show | awk -v ip="$network_ip" '
        {
            split($4, address, "/")
            if (address[1] == ip) {
                print $2
                exit
            }
        }
    ')"
fi

if [ -z "$network_id" ]; then
    network_id="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
fi

if [ -z "$network_id" ]; then
    exit 0
fi

if ip link show "$network_id" >/dev/null 2>&1; then
    current_mtu="$(cat "/sys/class/net/$network_id/mtu")"
    if [ "$current_mtu" -gt "$device_mtu" ]; then
        ip link set dev "$network_id" mtu "$device_mtu"
    fi
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

networks="$(curl -fsS --max-time 3 "$access_api/api/v2/networks" 2>/dev/null || true)"
if [ -z "$networks" ] || ! jq -e --arg id "$network_id" \
    '.code == 1 and ((.data // []) | any(.id == $id))' >/dev/null <<<"$networks"; then
    exit 0
fi

settings="$(curl -fsS --max-time 3 "$access_api/api/v2/settings" 2>/dev/null || true)"
if [ -z "$settings" ]; then
    exit 0
fi

current_network="$(jq -r '.data.mngt_network_id // empty' <<<"$settings")"
if [ "$current_network" != "$network_id" ]; then
    curl -fsS --max-time 5 \
        -X PUT "$access_api/api/v2/settings" \
        -H "Content-Type: application/json" \
        --data "{\"mngt_network_id\":\"$network_id\"}" >/dev/null 2>&1 || true
fi
