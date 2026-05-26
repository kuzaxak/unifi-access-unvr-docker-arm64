#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

image_name="${DOCKER_IMAGE:-unifi-os-docker-arm64}"
firmware_series="${FIRMWARE_SERIES:-5.x}"
firmware_dir="${FIRMWARE_DIR:-firmware/${firmware_series}}"

if [ ! -f "${firmware_dir}/version" ]; then
    echo "Missing firmware artifacts in ${firmware_dir}; run FIRMWARE_SERIES=${firmware_series} ./build-firmware.sh first." >&2
    exit 1
fi

opts="--label project_version=$(tr -d '\n ' < VERSION.txt)"
fw_version="$(tr -d '\n ' < "${firmware_dir}/version")"
opts="$opts --label FW_VERSION=${fw_version} --label FW_SERIES=${firmware_series}"
if [[ -n "${DOCKER_NO_CACHE+x}" ]]; then
    opts="$opts --no-cache"
fi
# Pass through every per-app URL override (Access, Protect, AI features,
# media-server family). Useful when a caller wants to pin a specific deb
# without editing the Dockerfile.
for arg in ACCESS_URL UUA_URL MS_URL PROTECT_URL AIFC_CNS_URL AIFC_CTR_URL \
           MSR_URL MSP_URL MST_URL DS_URL; do
    val="${!arg:-}"
    if [[ -n "$val" ]]; then
        opts="$opts --build-arg ${arg}=${val}"
    fi
done

if [[ -n "${BUILD_PRUNE+x}" ]]; then
    docker images | grep "$image_name" | tr -s ' ' | cut -d ' ' -f 2 \
        | xargs -I {} docker rmi -f "${image_name}:{}" || true
    docker buildx prune -f
fi

if [[ -n "${BUILD_EDGE+x}" ]]; then
    docker build $opts --build-context firmware-selected="${firmware_dir}" -f os.Dockerfile -t "${image_name}:edge" .
    if [[ -n "${BUILD_TAG_VERSION+x}" ]]; then
        version="$(docker run --rm "${image_name}:edge" dpkg -s unifi-access | grep '^Version:' | cut -d ' ' -f 2 | tr -d '\n')"
        docker tag "${image_name}:edge" "${image_name}:v${version}"
        docker tag "${image_name}:edge" "${image_name}:v$(cut -d '.' -f 1-2 <<< "$version")"
        docker tag "${image_name}:edge" "${image_name}:v$(cut -d '.' -f 1 <<< "$version")"
    fi
fi

if [[ -n "${BUILD_STABLE+x}" ]] || [[ -z "${BUILD_EDGE+x}" ]]; then
    docker build $opts --build-context firmware-selected="${firmware_dir}" -f os.Dockerfile --build-arg STABLE=1 -t "${image_name}:stable" --pull .
    if [[ -n "${BUILD_TAG_VERSION+x}" ]]; then
        version="$(docker run --rm "${image_name}:stable" dpkg -s unifi-access | grep '^Version:' | cut -d ' ' -f 2 | tr -d '\n')"
        docker tag "${image_name}:stable" "${image_name}:v${version}"
        docker tag "${image_name}:stable" "${image_name}:v$(cut -d '.' -f 1-2 <<< "$version")"
        docker tag "${image_name}:stable" "${image_name}:v$(cut -d '.' -f 1 <<< "$version")"
    fi
fi
