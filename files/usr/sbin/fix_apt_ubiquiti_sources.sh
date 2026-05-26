#!/usr/bin/env bash

set -euo pipefail

# Pin the Ubiquiti apt list so the container's own ubnt packages don't get
# silently overwritten by a uos-agent self-update run inside the container.
chattr +i /etc/apt/sources.list.d/ubiquiti.list
