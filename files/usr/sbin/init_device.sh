#!/bin/bash

for e in $(tr "\000" "\n" < /proc/1/environ); do
    eval "export $e"
done

echo "${DEVICE:-UNVR}" > /etc/default/device

if [[ "${DEBUG:-false}" == 'true' || "${DEBUG_UNIFI_CORE:-false}" == 'true' ]]; then
    if [ -f /usr/share/unifi-core/app/config/default.yaml ]; then
        cp -a /usr/share/unifi-core/app/config/default.yaml /usr/share/unifi-core/app/config/default.yaml.bak
        sed -Ei "s/defaultLevel: '.+'/defaultLevel: 'debug'/g" /usr/share/unifi-core/app/config/default.yaml
    fi
elif [ -f /usr/share/unifi-core/app/config/default.yaml.bak ]; then
    mv /usr/share/unifi-core/app/config/default.yaml.bak /usr/share/unifi-core/app/config/default.yaml
fi
