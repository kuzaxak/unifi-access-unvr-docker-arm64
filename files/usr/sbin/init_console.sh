#!/usr/bin/env bash

set -euo pipefail

settings_file="/data/unifi-core/config/settings.yaml"
uuid_file="/data/uuid.txt"
uuid_pattern='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

ensure_uuid() {
    if [ ! -s "$uuid_file" ] || ! tr -d '[:space:]' < "$uuid_file" | grep -Eq "$uuid_pattern"; then
        cat /proc/sys/kernel/random/uuid > "$uuid_file"
    fi

    tr -d '[:space:]' < "$uuid_file"
}

if [ -f "$settings_file" ]; then
    current_id="$(
        sed -nE 's/^anonymous_device_id:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' "$settings_file" \
            | head -n1
    )"

    if ! printf '%s' "$current_id" | grep -Eq "$uuid_pattern"; then
        UUID="$(ensure_uuid)"
        if grep -q '^anonymous_device_id:' "$settings_file"; then
            sed -Ei "s/^anonymous_device_id:.*/anonymous_device_id: ${UUID}/" "$settings_file"
        else
            printf '\nanonymous_device_id: %s\n' "$UUID" >> "$settings_file"
        fi
    fi
fi
