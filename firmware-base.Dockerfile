# Base image with tools needed to extract Ubiquiti firmware binaries.
# binwalk -e unpacks the squashfs; dpkg-repack rebuilds .deb files from the
# unpacked rootfs so we can install them into a fresh Debian 11 container.
FROM debian:trixie AS firmware-base
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/usr/bin/env", "bash", "-c"]
RUN --mount=target=/var/lib/apt/lists,type=cache --mount=target=/var/cache/apt,type=cache \
    set -euo pipefail \
    && apt-get update \
    && apt-get install -y apt-transport-https ca-certificates \
    && sed -i 's/http:/https:/g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get dist-upgrade -y \
    && apt-get --purge autoremove -y \
    && apt-get install -y wget jq binwalk dpkg-repack
