#!/usr/bin/env bash

set -euo pipefail

PLATFORM="${1:-unvr}"

echo "Latest console firmware for platform=${PLATFORM}:"
curl -sf "https://fw-update.ubnt.com/api/firmware?filter=eq~~platform~~${PLATFORM}&filter=eq~~channel~~release&sort=-version&limit=1" \
    | jq -r '._embedded.firmware[0] | "version=\(.version) sha256=\(.sha256_checksum) url=\(._links.data.href)"'

for product in unifi-protect unifi-access ai-feature-console ai-feature-controller ms msr msp mst ds unifi-user-assets unifi-face-shared-lib; do
    echo
    echo "Latest ${product} .deb (arm64):"
    curl -sf "https://fw-update.ubnt.com/api/firmware-latest?filter=eq~~product~~${product}&filter=eq~~channel~~release&filter=eq~~platform~~uos-deb11-arm64" \
        | jq -r '._embedded.firmware[0] | "version=\(.version) sha256=\(.sha256_checksum) url=\(._links.data.href)"'
done
