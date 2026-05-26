#!/usr/bin/env bash

set -euo pipefail

http_dir="/data/unifi-core/config/http"
console_group="/data/unifi-core/config/consoleGroup.yaml"

if [ -x /usr/sbin/configure_unifi_access_network.sh ]; then
    /usr/sbin/configure_unifi_access_network.sh || true
fi

for _ in $(seq 1 120); do
    if [ -f "$http_dir/shared-runnable-users.conf" ]; then
        break
    fi
    sleep 1
done

mkdir -p "$http_dir"

if [ -f "$console_group" ]; then
    # Access-only rollback images must advertise local Access ownership, or Core
    # enables the service but omits it from the authenticated launcher app list.
    perl -0pi -e \
        's/(access:\n\s+owned:\s+)false/${1}true/; s/(protect:\n\s+owned:\s+false\n\s+required:\s+)true/${1}false/' \
        "$console_group"
    chown unifi-core:unifi-core "$console_group"
fi

for _ in $(seq 1 120); do
    if systemctl is-active --quiet unifi-access; then
        break
    fi
    sleep 1
done

if [ ! -e /run/unifi-access-nginx-route.core-restarted ]; then
    # The 4.x systemd watcher is reduced to a startup sample in this container.
    # Restart Core once after Access is active so the launcher sees Access as
    # running and fetches the Access manifest.
    touch /run/unifi-access-nginx-route.core-restarted
    systemctl restart unifi-core

    for _ in $(seq 1 60); do
        if systemctl is-active --quiet unifi-core; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Core 4.1.140 enables Access but does not render its runnable nginx route in
# this Access-only rollback image. Add the same route shape Core renders for
# Users so the portal can serve Access assets and proxy Access API calls.
cat > "$http_dir/upstream-access_api_backend.conf" <<'EOF'
upstream access_api_backend {
    server 127.0.0.1:12080;

    keepalive 2;

    zone upstreams 512k;
}
EOF

cat > "$http_dir/shared-runnable-access.conf" <<'EOF'
location /app-assets/access/ {
    include /usr/share/unifi-core/http/cors.conf;
    include /usr/share/unifi-core/http/security.conf;
    include /usr/share/unifi-core/http/auth.conf;
    include /usr/share/unifi-core/http/proxy.conf;

    alias /usr/lib/unifi-access/swai/;

    expires max;
}

location /proxy/access/ {
    include /usr/share/unifi-core/http/cors.conf;
    include /usr/share/unifi-core/http/security.conf;
    include /usr/share/unifi-core/http/auth.conf;
    include /usr/share/unifi-core/http/proxy.conf;

    proxy_pass http://access_api_backend/;
}

location /proxy/access/public/ {
    include /usr/share/unifi-core/http/cors.conf;
    include /usr/share/unifi-core/http/security.conf;
    include /usr/share/unifi-core/http/proxy.conf;

    proxy_pass http://access_api_backend/public/;
}
EOF

chown unifi-core:unifi-core \
    "$http_dir/upstream-access_api_backend.conf" \
    "$http_dir/shared-runnable-access.conf"

if [ -s /var/run/nginx.pid ] && kill -0 "$(cat /var/run/nginx.pid)" 2>/dev/null; then
    nginx -t
    nginx -s reload
fi
