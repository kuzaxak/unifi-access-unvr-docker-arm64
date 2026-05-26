# Extract Ubiquiti UniFi OS base packages from UNVR firmware.
#
# UNVR firmware is the canonical UniFi OS arm64 image that dciancu's
# unifi-protect-unvr-docker-arm64 has battle-tested in production. It ships
# every UniFi OS daemon (unifi-core, ulp-go, uos/uos-agent/uos-discovery-client,
# unifi-directory, ubnt-archive-keyring) AND the unifi-protect application
# bundle. We extract both: protect installs straight from the firmware bundle,
# access installs from fw-update.ubnt.com on top.
#
# Identity-consistency: our ubnt-tools shim reports the console as UNVR, so
# extracting from UNVR firmware aligns asset bundle (unifi-assets-unvr), board
# id (0xea16), and feature flags (no hasGateway/hasUdapi) - removing every
# wizard step that would fail in a container.
FROM unifi-os-firmware-base AS firmware
ARG FW_URL
ARG FW_EDGE
ARG FW_ALL_DEBS
ARG FW_UNSTABLE
ARG FW_UPDATE_URL='https://fw-update.ubnt.com/api/firmware?filter=eq~~platform~~unvr&filter=eq~~channel~~release&sort=-version&limit=10'
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/usr/bin/env", "bash", "-c"]

RUN --mount=target=/var/lib/apt/lists,type=cache --mount=target=/var/cache/apt,type=cache \
    --mount=type=bind,from=firmware-selected,target=/opt/firmware,source=.,ro \
    set -euo pipefail \
    && FW_URL="${FW_URL:-}" \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get dist-upgrade -y \
    && apt-get --purge autoremove -y \
    && mkdir -p /opt/firmware-build && cd /opt/firmware-build \
    && if [ -z "$FW_URL" ] && [ -z "${FW_EDGE:-}" ] && [ -f /opt/firmware/firmware.txt ]; then FW_URL="$(tr -d '\n' < /opt/firmware/firmware.txt)"; fi  \
    && if [ -z "$FW_URL" ]; then { shopt -s lastpipe && wget -q --output-document - "$FW_UPDATE_URL" | \
        { if [ -n "${FW_UNSTABLE:-}" ]; then \
            jq -r '._embedded.firmware[0]._links.data.href'; \
        else \
            jq -r '._embedded.firmware | map(select(.probability_computed == 1))[0] | ._links.data.href'; \
        fi; } | \
        FW_URL="$(</dev/stdin)" && shopt -u lastpipe; }; fi \
    && echo "FW_URL: ${FW_URL}" \
    && wget --no-verbose --show-progress --progress=dot:giga -O fwupdate.bin "$FW_URL" \
    # Reuse a previously-built extraction tree if the user mounted one under ./firmware
    # with the matching sha1; saves the (slow) binwalk pass on rebuild.
    && if test -f /opt/firmware/fwupdate.sha1 && cat /opt/firmware/fwupdate.sha1 && sha1sum -c /opt/firmware/fwupdate.sha1; then \
        rm fwupdate.bin \
        && cp -a /opt/firmware/* . \
        && ls -lhR \
        && (cd / && rm -rf $(ls -A | grep -vE 'opt|sys|proc|dev'); exit 0) \
        && exit 0; \
    fi \
    && sha1sum fwupdate.bin | tee fwupdate.sha1 \
    && printf '%s\n' "$FW_URL" > firmware.txt \
    && useradd --shell /bin/bash build \
    && binwalk --run-as=build -e fwupdate.bin \
    && rm fwupdate.bin \
    && cp _fwupdate.bin.extracted/squashfs-root/usr/lib/version . \
    && dpkg-query --admindir=_fwupdate.bin.extracted/squashfs-root/var/lib/dpkg/ -W -f='${package} | ${Maintainer}\n' | \
        grep -E '@ubnt.com|@ui.com' | cut -d '|' -f 1 > packages.txt \
    && cat packages.txt \
    && mkdir debs-build && cd debs-build \
    && while read pkg; do \
        dpkg-repack --root=../_fwupdate.bin.extracted/squashfs-root/ --arch=arm64 "$pkg"; \
    done < ../packages.txt \
    && ls -lh \
    && if [ -n "${FW_ALL_DEBS:-}" ]; then mkdir ../all-debs && cp * ../all-debs/; fi \
    # Base OS packages both Protect and Access need. unifi-assets-unvr pairs
    # with the UNVR identity our ubnt-tools shim reports.
    #
    # ucs-agent + uid-agent + ucore-setup-listener + unifi-identity-update are
    # critical for Access cloud sign-in: without them unifi-core's publish()
    # message bus has no handler for ulp.bindSsoAccount / cloud.register topics
    # and POST /api/cloud/register hangs 60s on messageBox.longPollTimeout.
    # dciancu's Protect-only image works without them because Protect's
    # cloud-claim takes a different path. ubnt-ucp4cpp is the UCP4 device
    # protocol library; ubnt-rpsd is the RPC subprocess daemon. ustate-exporter
    # is the gRPC server unifi-core polls on 127.0.0.1:11052 (the source of the
    # continuous ECONNREFUSED noise without it). ustd / ubnt-common / libubnt /
    # libuled / libcurlpp / libsodiumpp / c2lib are runtime deps for the
    # daemons above. We skip hardware-only debs (ubnt-sfp-handler, ubntnas,
    # ubnt-disk-smart-mon, ui-snmp) and system-level debs (linux-image-*,
    # unvr-initramfs, kmod-*, base-files-*) that have no use in a container.
    && mkdir ../debs \
    && shopt -s nullglob \
    && cp ubnt-archive-keyring_* ubnt-tools_* ubnt-ucp4cpp_* ubnt-rpsd_* \
        ubnt-common_* ubnt-binmecpp_* ubnt-disk-smart-mon_* \
        unifi-core_* ulp-go_* unifi-assets-unvr_* unifi-directory_* unifi-hal_* \
        unifi-email-templates-all_* unifi-identity-update_* \
        uos_* uos-agent_* uos-discovery-client_* \
        ucs-agent_* uid-agent_* ucore-setup-listener_* uled-control_* \
        ustate-exporter_* ustd_* ubnd_* \
        c2lib_* libcurlpp_* libsodiumpp_* libubnt_* libuled_* simple-pid_* \
        analytic-report-go_* ble-http-transport_* \
        python3-unifi-console-protos_* \
        node* ../debs/ \
    # App-bundled debs the OS-stage install mounts for STABLE mode. Access is
    # never in UNVR firmware (we download it from fw-download); Protect always
    # is. Both directories always exist so the mount=type=bind never fails.
    && mkdir ../unifi-protect-deb \
    && cp unifi-protect_* ../unifi-protect-deb/ 2>/dev/null || true \
    && mkdir ../unifi-access-deb \
    && shopt -u nullglob \
    && cd .. \
    && rm -r _fwupdate.bin.extracted debs-build \
    && (cd / && rm -rf $(ls -A | grep -vE 'opt|sys|proc|dev'); exit 0) && exit 0
