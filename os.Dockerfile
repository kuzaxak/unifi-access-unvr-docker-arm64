FROM arm64v8/debian:11 AS os

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/usr/bin/env", "bash", "-c"]

RUN --mount=target=/var/lib/apt/lists,type=cache,sharing=private --mount=target=/var/cache/apt,type=cache,sharing=private \
    set -euo pipefail \
    && apt-get update \
    && apt-get install -y apt-transport-https ca-certificates \
    && sed -i 's/http:/https:/g' /etc/apt/sources.list \
    && apt-get update \
    && apt-get -y upgrade \
    && apt-get -y dist-upgrade \
    && apt-get --purge autoremove -y \
    # inotify-tools: fix_hosts.sh. net-tools (arp) + iproute2: Access door device
    # discovery on local subnet (shells out to arp/ip). net-tools also required
    # by Protect to adopt ONVIF cameras.
    && apt-get --no-install-recommends -y install \
        vim \
        adduser \
        inotify-tools \
        curl \
        wget \
        mount \
        psmisc \
        dpkg \
        apt \
        lsb-release \
        sudo \
        gnupg \
        apt-transport-https \
        ca-certificates \
        dirmngr \
        mdadm \
        lvm2 \
        iproute2 \
        ethtool \
        procps \
        cron \
        systemd \
        systemd-timesyncd \
        sysstat \
        net-tools \
        jq \
    # Strip *.wants targets that try to bring up hardware we do not have
    # (mdadm, lvm, smartd, etc). Keep journald and tmpfiles so logging works.
    && find /etc/systemd/system \
        /lib/systemd/system \
        -path '*.wants/*' \
        -not -name '*journald*' \
        -not -name '*systemd-tmpfiles*' \
        -not -name '*systemd-user-sessions*' \
        -exec rm \{} \;

RUN set -euo pipefail \
    && curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
        | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/debian `lsb_release -cs` nginx" \
        | sudo tee /etc/apt/sources.list.d/nginx.list \
    && printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n' \
        | sudo tee /etc/apt/preferences.d/99nginx

# PostgreSQL 14 from PGDG. unifi-core / ulp-go share the `main` cluster on 5432.
# Access's postinst creates a second cluster on 5435 (`access`) - that runs from
# the same PG 14 binary.
RUN --mount=target=/var/lib/apt/lists,type=cache,sharing=private --mount=target=/var/cache/apt,type=cache,sharing=private \
    set -euo pipefail \
    && curl -sL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor \
        | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null \
    && echo "deb https://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" > /etc/apt/sources.list.d/postgresql.list \
    && apt-get update \
    && apt-get --no-install-recommends -y install postgresql-14

COPY --from=firmware-selected version /usr/lib/version
COPY files/etc /etc/

# Access install args (downloaded from fw-update.ubnt.com latest at build time)
ARG ACCESS_URL
ARG UUA_URL
ARG MS_URL
# Protect install args (Protect's component deps live alongside the protect deb)
ARG PROTECT_URL
ARG AIFC_CNS_URL
ARG AIFC_CTR_URL
ARG MSR_URL
ARG MSP_URL
ARG MST_URL
ARG DS_URL
# Pinned STABLE URLs. Access stable URL was last verified against the
# unifi-os-deb11-arm64 firmware-latest endpoint; AI feature stables come
# straight from dciancu (same versions as their tested Protect image).
ARG ACCESS_STABLE_URL="https://fw-download.ubnt.com/data/unifi-access/a62a-uos-deb11-arm64-4.2.27-654941c3-971e-4a52-8b86-9fcd4116f56a.deb"
ARG AIFC_CNS_STABLE_URL="https://fw-download.ubnt.com/data/ai-feature-console/cba6-uos-deb11-arm64-1.10.5-de8752ff-02a0-4b28-9ddf-9158deb0a276.deb"
ARG AIFC_CTR_STABLE_URL="https://fw-download.ubnt.com/data/ai-feature-controller/4041-uos-deb11-arm64-2.0.11-768932b3-d647-4e39-8a57-723534e5549f.deb"
ARG DEB_UPDATE_URL="https://fw-update.ubnt.com/api/firmware-latest?filter=eq~~product~~{product}&filter=eq~~channel~~release&filter=eq~~platform~~uos-deb11-arm64"
ARG STABLE
RUN --mount=target=/var/lib/apt/lists,type=cache --mount=target=/var/cache/apt,type=cache \
    --mount=type=bind,from=firmware-selected,source=debs,target=/opt/debs \
    --mount=type=bind,from=firmware-selected,source=unifi-protect-deb,target=/opt/unifi-protect-deb \
    --mount=type=bind,from=firmware-selected,source=unifi-access-deb,target=/opt/unifi-access-deb \
    set -euo pipefail \
    && ACCESS_URL="${ACCESS_URL:-}" \
    && UUA_URL="${UUA_URL:-}" \
    && MS_URL="${MS_URL:-}" \
    && PROTECT_URL="${PROTECT_URL:-}" \
    && AIFC_CNS_URL="${AIFC_CNS_URL:-}" \
    && AIFC_CTR_URL="${AIFC_CTR_URL:-}" \
    && MSR_URL="${MSR_URL:-}" \
    && MSP_URL="${MSP_URL:-}" \
    && MST_URL="${MST_URL:-}" \
    && DS_URL="${DS_URL:-}" \
    && STABLE="${STABLE:-}" \
    && systemctl enable systemd-timesyncd.service \
    && systemctl enable systemd-time-wait-sync.service \
    && apt-get --no-install-recommends -y install /opt/debs/ubnt-archive-keyring_*_arm64.deb \
    && echo "deb https://apt.artifacts.ui.com `lsb_release -cs` main release" > /etc/apt/sources.list.d/ubiquiti.list \
    && apt-get update \
    # uos-discovery-client's postinst tries to start the service via systemctl,
    # which has no PID 1 yet during the build. Trick it with an echo-only stub,
    # restore after install, then enable for real at boot.
    && mv /bin/systemctl /bin/systemctl.tmp \
    && printf '#!/bin/bash\necho 0\n' > /bin/systemctl \
    && chmod +x /bin/systemctl \
    && apt-get --no-install-recommends -y install /opt/debs/uos-discovery-client_*_arm64.deb \
    && mv /bin/systemctl.tmp /bin/systemctl \
    && systemctl enable uos-discovery-client.service \
    # ms ships dlopen-only deps that are not declared in its Depends.
    && apt-get --no-install-recommends -y install libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
        libgstreamer-plugins-bad1.0-0 libglib2.0-0 \
    # Edge path: every app deb resolved from fw-update.ubnt.com latest.
    && if [ -z "$STABLE" ]; then \
        if [ -z "$PROTECT_URL" ]; then \
            PROTECT_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/unifi-protect/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$AIFC_CNS_URL" ]; then \
            AIFC_CNS_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/ai-feature-console/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$AIFC_CTR_URL" ]; then \
            AIFC_CTR_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/ai-feature-controller/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$MS_URL" ]; then \
            MS_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/ms/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$MSR_URL" ]; then \
            MSR_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/msr/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$MSP_URL" ]; then \
            MSP_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/msp/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$MST_URL" ]; then \
            MST_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/mst/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$DS_URL" ]; then \
            DS_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/ds/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$ACCESS_URL" ]; then \
            ACCESS_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/unifi-access/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && if [ -z "$UUA_URL" ]; then \
            UUA_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/unifi-user-assets/')" | jq -r '._embedded.firmware[0]._links.data.href')"; \
        fi \
        && echo "PROTECT_URL=${PROTECT_URL}" \
        && echo "AIFC_CNS_URL=${AIFC_CNS_URL}" \
        && echo "AIFC_CTR_URL=${AIFC_CTR_URL}" \
        && echo "MS_URL=${MS_URL}" \
        && echo "MSR_URL=${MSR_URL}" \
        && echo "MSP_URL=${MSP_URL}" \
        && echo "MST_URL=${MST_URL}" \
        && echo "DS_URL=${DS_URL}" \
        && echo "ACCESS_URL=${ACCESS_URL}" \
        && echo "UUA_URL=${UUA_URL}" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/unifi-protect.deb "$PROTECT_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/ai-feature-console.deb "$AIFC_CNS_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/ai-feature-controller.deb "$AIFC_CTR_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/ms.deb "$MS_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/msr.deb "$MSR_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/msp.deb "$MSP_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/mst.deb "$MST_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/ds.deb "$DS_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/unifi-access.deb "$ACCESS_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/unifi-user-assets.deb "$UUA_URL" \
        && apt-get -y --no-install-recommends -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' \
            install /opt/debs/*.deb /opt/ai-feature-console.deb /opt/ai-feature-controller.deb \
                /opt/ms.deb /opt/msr.deb /opt/msp.deb /opt/mst.deb /opt/ds.deb \
                /opt/unifi-protect.deb coturn /opt/unifi-user-assets.deb /opt/unifi-access.deb \
        && rm /opt/ai-feature-console.deb /opt/ai-feature-controller.deb /opt/ms.deb /opt/msr.deb \
            /opt/msp.deb /opt/mst.deb /opt/ds.deb /opt/unifi-protect.deb \
            /opt/unifi-user-assets.deb /opt/unifi-access.deb; \
    fi \
    # Stable path: Protect from firmware-bundled deb, AI features from pinned
    # URLs, Access from pinned stable URL. ms/msr/msp/mst/ds/unifi-user-assets/
    # unifi-face-shared-lib still come from fw-update.ubnt.com because apt
    # feed at apt.artifacts.ui.com lags Access's minimum-version requirements.
    && if [ -n "$STABLE" ]; then \
        UUA_STABLE_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/unifi-user-assets/')" | jq -r '._embedded.firmware[0]._links.data.href')" \
        && MS_STABLE_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/ms/')" | jq -r '._embedded.firmware[0]._links.data.href')" \
        && UFSL_STABLE_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/unifi-face-shared-lib/')" | jq -r '._embedded.firmware[0]._links.data.href')" \
        && MSR_STABLE_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/msr/')" | jq -r '._embedded.firmware[0]._links.data.href')" \
        && MSP_STABLE_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/msp/')" | jq -r '._embedded.firmware[0]._links.data.href')" \
        && MST_STABLE_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/mst/')" | jq -r '._embedded.firmware[0]._links.data.href')" \
        && DS_STABLE_URL="$(wget -q -O - "$(printf "$DEB_UPDATE_URL" | sed 's/{product}/ds/')" | jq -r '._embedded.firmware[0]._links.data.href')" \
        && echo "ACCESS_STABLE_URL=${ACCESS_STABLE_URL}" \
        && echo "AIFC_CNS_STABLE_URL=${AIFC_CNS_STABLE_URL}" \
        && echo "AIFC_CTR_STABLE_URL=${AIFC_CTR_STABLE_URL}" \
        && echo "UUA_STABLE_URL=${UUA_STABLE_URL}" \
        && echo "MS_STABLE_URL=${MS_STABLE_URL}" \
        && echo "UFSL_STABLE_URL=${UFSL_STABLE_URL}" \
        && echo "MSR_STABLE_URL=${MSR_STABLE_URL}" \
        && echo "MSP_STABLE_URL=${MSP_STABLE_URL}" \
        && echo "MST_STABLE_URL=${MST_STABLE_URL}" \
        && echo "DS_STABLE_URL=${DS_STABLE_URL}" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/ai-feature-console.deb "$AIFC_CNS_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/ai-feature-controller.deb "$AIFC_CTR_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/ms.deb "$MS_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/msr.deb "$MSR_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/msp.deb "$MSP_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/mst.deb "$MST_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/ds.deb "$DS_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/unifi-user-assets.deb "$UUA_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/unifi-face-shared-lib.deb "$UFSL_STABLE_URL" \
        && wget --no-verbose --show-progress --progress=dot:giga -O /opt/unifi-access.deb "$ACCESS_STABLE_URL" \
        && apt-get -y --no-install-recommends -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' \
            install /opt/debs/*.deb /opt/ai-feature-console.deb /opt/ai-feature-controller.deb \
                /opt/ms.deb /opt/msr.deb /opt/msp.deb /opt/mst.deb /opt/ds.deb \
                /opt/unifi-protect-deb/*.deb coturn /opt/unifi-face-shared-lib.deb \
                /opt/unifi-user-assets.deb /opt/unifi-access.deb \
        && rm /opt/ai-feature-console.deb /opt/ai-feature-controller.deb /opt/ms.deb /opt/msr.deb \
            /opt/msp.deb /opt/mst.deb /opt/ds.deb /opt/unifi-face-shared-lib.deb \
            /opt/unifi-user-assets.deb /opt/unifi-access.deb; \
    fi

RUN \
    # policy-rc.d off so apt does not try to start services against a non-existent
    # systemd at build time.
    echo 'exit 0' > /usr/sbin/policy-rc.d \
    # ustorage gRPC fallback. unifi-core expects a gRPC server on 127.0.0.1:11052
    # that only exists on real UniFi consoles. Without this patch the setup
    # wizard fails with ECONNREFUSED. The sed forces the JS to take the
    # shell-ustorage code path our shim at /usr/bin/ustorage answers.
    && if ! sed -i '/return at()?s.push/{s//return at(),!0?s.push/;h};${x;/./{x;q0};x;q1}' /usr/share/unifi-core/app/service.js; then \
        echo 'ERROR: ustorage sed pattern not found in service.js - upstream may have changed' && exit 1; \
    fi \
    # Relax pre-setup nginx hostname check so the setup wizard works through
    # reverse-proxied hostnames. Original regex only accepts
    # unifi/localhost/raw-IP and 302s everything else.
    && if ! sed -i 's|host !~\* \^(unifi|host !~* ^(.+|' /usr/share/unifi-core/http/site-setup.conf; then \
        echo 'ERROR: site-setup.conf hostname patch failed - upstream may have changed' && exit 1; \
    fi \
    # Save originals so our shims at files/sbin/{mdadm,ubnt-tools} can fall
    # through for subcommands we do not override.
    && mv /sbin/mdadm /sbin/mdadm.orig \
    && mv /sbin/ubnt-tools /sbin/ubnt-tools.orig \
    && systemctl enable postgresql-cluster@14-main.service storage_disk dbpermissions fix_hosts fix_apt_ubiquiti_sources init_console init_device \
    && systemctl enable unifi-access-network.timer \
    && sed -i 's/rm -f/rm -rf/' /sbin/pg-cluster-upgrade \
    && touch /usr/bin/uled-ctrl \
    && chmod +x /usr/bin/uled-ctrl \
    && chown root:root /etc/sudoers.d/* \
    # ulp-go reads PGHOST from this envs file. Force loopback since the
    # container hosts its own postgres clusters.
    && echo -e '\n\nexport PGHOST=127.0.0.1\n' >> /usr/lib/ulp-go/scripts/envs.sh

COPY files/sbin /sbin/
COPY files/usr /usr/

VOLUME ["/srv", "/data", "/persistent"]

STOPSIGNAL SIGINT
CMD ["/lib/systemd/systemd"]

LABEL STABLE=${STABLE}
LABEL ACCESS_STABLE_URL=${ACCESS_STABLE_URL}
LABEL ACCESS_URL=${ACCESS_URL}
LABEL UUA_URL=${UUA_URL}
LABEL MS_URL=${MS_URL}
LABEL PROTECT_URL=${PROTECT_URL}
LABEL AIFC_CNS_STABLE_URL=${AIFC_CNS_STABLE_URL}
LABEL AIFC_CTR_STABLE_URL=${AIFC_CTR_STABLE_URL}
