#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

image_name="unifi-os-firmware"
base_image_name="unifi-os-firmware-base"
firmware_series="${FIRMWARE_SERIES:-5.x}"
firmware_dir="${FIRMWARE_DIR:-firmware/${firmware_series}}"

opts=""
if [[ -n "${DOCKER_NO_CACHE+x}" ]]; then
    opts="--no-cache"
fi

mkdir -p "${firmware_dir}"

docker build $opts -f firmware-base.Dockerfile -t "${base_image_name}" --pull .

docker build $opts -f firmware.Dockerfile -t "${image_name}" \
    --build-arg "FW_URL=${FW_URL:-}" --build-arg "FW_EDGE=${FW_EDGE:-}" \
    --build-arg "FW_ALL_DEBS=${FW_ALL_DEBS:-}" --build-arg "FW_UNSTABLE=${FW_UNSTABLE:-}" \
    --build-context firmware-selected="${firmware_dir}" .

if [ -f "${firmware_dir}/version" ]; then
    rm -r "${firmware_dir:?}"/*
fi

docker build -f firmware-copy.Dockerfile --output "${firmware_dir}" .

echo "Firmware artifacts:"
ls -lhR "${firmware_dir}"
