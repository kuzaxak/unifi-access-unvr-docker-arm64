# UniFi OS Docker container for arm64, with Protect and Access

Run UniFi OS, UniFi Protect, and UniFi Access in a privileged Docker container
on ARM64 Linux.

This project extends
[dciancu/unifi-protect-unvr-docker-arm64](https://github.com/dciancu/unifi-protect-unvr-docker-arm64)
with the Access application and the extra services Access needs.

> [!IMPORTANT]
> This is experimental and unsupported by Ubiquiti. UniFi Access controls doors.
> Do not use this for real access-control hardware without your own risk review,
> backups, and burn-in testing.
>
> This repository does not publish prebuilt images. Build locally from official
> Ubiquiti firmware and package URLs so Ubiquiti binaries are not redistributed.
>
> After initial setup, disable UniFi OS and application auto-updates. A normal
> console update can replace patched files or move package dependencies in ways
> this container does not expect.

## Usage

Build the image, then start it with the provided compose file:

```bash
bash build.sh
docker compose up -d
```

The default Linux compose file uses host networking. Open the UniFi OS setup UI
at:

```text
https://<host-ip>
```

For macOS Docker Desktop, use the lab-only compose file:

```bash
docker compose -f docker-compose.macos.yml up -d
```

macOS Docker Desktop cannot adopt real Access devices or Protect cameras because
the container runs inside a NATed Linux VM. Use a Linux host on the same L2
network as the devices, or a bridged Linux VM, for real hardware.

## Building

`build.sh` runs two stages:

1. `build-firmware.sh` downloads a UniFi firmware image from Ubiquiti, extracts
   the UniFi OS packages, and writes generated artifacts under `firmware/<series>/`.
2. `build-os.sh` installs the extracted packages plus Protect and Access into
   a Debian 11 ARM64 systemd image.

Generated firmware artifacts are intentionally ignored by git.

```bash
# Full default build, using firmware.txt and stable app packages
bash build.sh

# Keep firmware extraction and image build separate
bash build-firmware.sh
BUILD_STABLE=1 bash build-os.sh

# Build from latest package URLs returned by fw-update.ui.com
BUILD_EDGE=1 bash build-os.sh

# Keep separate extraction directories for different firmware families
FIRMWARE_SERIES=5.x bash build-firmware.sh
FIRMWARE_SERIES=5.x BUILD_STABLE=1 bash build-os.sh

# Build an older firmware family by supplying its firmware URL
FIRMWARE_SERIES=4.x FW_URL=<unvr-4.x-firmware-url> bash build-firmware.sh
FIRMWARE_SERIES=4.x BUILD_STABLE=1 bash build-os.sh

# Inspect current Ubiquiti firmware/package URLs
bash check-latest-firmware.sh unvr
```

Single-file Docker build is also supported:

```bash
docker build -t unifi-os-docker-arm64:stable --build-arg STABLE=1 .
```

## Build Options

`build-os.sh` accepts:

| Variable | Purpose |
|---|---|
| `DOCKER_IMAGE` | Image name, default `unifi-os-docker-arm64` |
| `FIRMWARE_SERIES` | Firmware artifact directory under `firmware/`, default `5.x` |
| `FIRMWARE_DIR` | Explicit firmware artifact directory |
| `BUILD_STABLE` | Build the stable tag, using pinned stable Access and firmware-bundled Protect |
| `BUILD_EDGE` | Build the edge tag, resolving latest app packages from Ubiquiti |
| `BUILD_TAG_VERSION` | Add versioned tags based on the installed Access version |
| `DOCKER_NO_CACHE` | Pass `--no-cache` to Docker build |
| `BUILD_PRUNE` | Remove existing project images and prune build cache before building |
| `ACCESS_URL`, `UUA_URL`, `MS_URL` | Override Access-side package URLs |
| `PROTECT_URL`, `AIFC_CNS_URL`, `AIFC_CTR_URL` | Override Protect and AI package URLs |
| `MSR_URL`, `MSP_URL`, `MST_URL`, `DS_URL` | Override Protect media-service package URLs |

`build-firmware.sh` accepts:

| Variable | Purpose |
|---|---|
| `FW_URL` | Firmware URL to download instead of `firmware.txt` |
| `FW_EDGE` | Resolve latest release firmware from Ubiquiti |
| `FW_UNSTABLE` | Skip the stable probability filter when resolving latest firmware |
| `FW_ALL_DEBS` | Save every Ubiquiti-maintained package from firmware extraction |
| `FIRMWARE_SERIES` | Output directory under `firmware/`, default `5.x` |
| `FIRMWARE_DIR` | Explicit output directory |

## Config

Create a `docker-compose.override.yml` for local configuration:

```yaml
services:
  unifi-os:
    environment:
      # Console identity shim. UNVR is the default and the best-tested path.
      - DEVICE=UNVR

      # Enable verbose service logging.
      # - DEBUG=true
      # - DEBUG_UNIFI_CORE=true
      # - DEBUG_STORAGE=true

      # Optional: force the Access management interface by interface name.
      # - ACCESS_MNGT_NETWORK_ID=eth0

      # Optional: find the Access management interface by IP, useful for
      # macvlan or VXLAN deployments where Docker interface names can change.
      # - ACCESS_MNGT_NETWORK_IP=192.168.50.200

      # Optional: lower the device-facing interface MTU for encapsulated paths.
      # - ACCESS_DEVICE_MTU=1200
```

Persistent state is stored in:

| Host path | Container path | Purpose |
|---|---|---|
| `./storage/srv` | `/srv` | Application state and media |
| `./storage/data` | `/data` | UniFi Core, Access, database state |
| `./storage/persistent` | `/persistent` | Persistent console files |

Back up all three before updating.

## Network

The default `docker-compose.yml` uses `network_mode: host`. This is the
simplest Linux deployment mode and is the expected mode for adopting real
hardware on the local LAN.

Ubiquiti documents the Access communication ports and discovery model in
[Getting Started with UniFi Access](https://help.ui.com/hc/en-us/articles/17452334269975-Getting-Started-with-UniFi-Access)
and the broader
[Required Ports Reference](https://help.ui.com/hc/en-us/articles/218506997-UniFi-Ports-Used).

Important Access ports:

| Port | Proto | Purpose |
|---|---|---|
| 10001 | UDP | Device discovery during adoption |
| 8080 | TCP | Device adoption/inform |
| 12080 | TCP | Access HTTP API, localhost/internal |
| 12443 | TCP | Access device communication and UI/API |
| 12445 | TCP | Access OpenAPI when enabled |
| 12812 | TCP | Access MQTT device messaging |

The Access package used by this image currently exposes OpenAPI HTTPS on
`12445` via `port.open_api.https`. Re-check that package setting when upgrading
Access.

Important Protect ports:

| Port | Proto | Purpose |
|---|---|---|
| 7442 | TCP | Camera communication |
| 7444 | TCP | Protect HTTPS/API |
| 7445, 7446 | TCP | Event/media services |
| 7447 | TCP | RTSP |
| 3478 | UDP | STUN/WebRTC |

### Cloud or Routed Deployments

Fresh Access adoption is sensitive to L2 discovery. A plain routed VPN may be
enough for some post-adoption traffic, but do not assume it is enough for first
adoption. If the controller is not on the same broadcast domain as the devices,
extend L2 explicitly and verify UDP 10001 traffic with packet captures.

A tested pattern is:

```text
Office LAN 192.168.50.0/24
  Access devices
  Router / firewall
    VXLAN VNI 100 over an encrypted site-to-site tunnel
Cloud or remote Linux host
  br-office bridge
  vxlan0 attached to br-office
  docker macvlan network parent=br-office
  unifi-os container 192.168.50.200/24
```

For this topology, run the container on the macvlan network only. Do not also
attach the default docker bridge. UniFi OS 5.x can otherwise see the bridge
address, select it as controller identity, and generate device or invitation
URLs that point at an unreachable `172.x.x.x` address.

Example macvlan compose:

```yaml
services:
  unifi-os:
    image: unifi-os-docker-arm64:stable
    container_name: unifi-os
    hostname: UNVR
    privileged: true
    cgroup: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup
      - /srv/unifi-os/srv:/srv
      - /srv/unifi-os/data:/data
      - /srv/unifi-os/persistent:/persistent
    environment:
      - container=docker
      - DEVICE=UNVR
      - ACCESS_MNGT_NETWORK_IP=192.168.50.200
      - ACCESS_DEVICE_MTU=1200
    networks:
      office-lan:
        ipv4_address: 192.168.50.200

networks:
  office-lan:
    external: true
```

After startup, verify:

```bash
docker exec unifi-os ip -brief addr
docker exec unifi-os ip route
docker exec unifi-os cat /sys/class/net/eth0/mtu
docker exec unifi-os curl -sS http://127.0.0.1:12080/api/v2/settings | jq .
```

Expected result: the container has only the intended LAN address, no docker
bridge address, and Access reports the LAN address as `controller_ip`.

## Setup

1. Build and start the container.
2. Open `https://<host-ip>` and complete the UniFi OS setup wizard.
3. Disable UniFi OS and application auto-updates.
4. Open Access and Protect from the console launcher.
5. Adopt devices only after packet-level discovery is known to work.
6. Make a backup before every image or firmware change.

If using Access hardware, verify the device-facing path with:

```bash
tcpdump -ni <lan-interface> "udp port 10001 or tcp port 8080 or tcp port 12443 or tcp port 12812"
```

For encapsulated paths such as VXLAN over IPSec, also verify MTU. Small UDP
discovery packets can work while larger TLS/MQTT management traffic fails. The
included `unifi-access-network.timer` can lower the Access management interface
MTU with `ACCESS_DEVICE_MTU`.

## Logs

Host-side:

```bash
docker compose logs -f
```

Inside the container:

```bash
docker exec -it unifi-os journalctl -f
docker exec -it unifi-os journalctl -u unifi-core -u unifi-access -u unifi-protect -f
```

Common log locations:

| Path | Purpose |
|---|---|
| `/data/unifi-core/logs` | UniFi OS / Core logs |
| `/data/unifi-access/log` | Access logs |
| `/srv/unifi-protect/logs` | Protect logs |
| `/var/log/storage_disk_debug.log` | Storage shim debug log when enabled |

## How This Differs From Upstream Protect

The upstream project focuses on UniFi Protect on UNVR. This repo keeps the same
general container shape, then adds:

- Access package installation and dependencies.
- Access nginx launcher/proxy route support.
- Access device-network timer for management interface and MTU repair.
- PostgreSQL handling for the additional Access cluster.
- Additional UniFi OS services needed by Access/Identity flows.

## Known Limitations

- This is not supported by Ubiquiti.
- No prebuilt image is provided.
- Downgrades are unsafe. Back up first and prefer forward-only migrations.
- Access adoption requires real discovery reachability. Test with `tcpdump`,
  not only with ping.
- Protect hardware has not been broadly validated here. Treat camera support as
  experimental until you have tested your camera models.
- The default console identity is `UNVR`. Other `DEVICE=` values exist in the
  shim, but they are not equally tested.
- Ubiquiti package URLs, firmware contents, and minified UniFi Core JavaScript
  can change. The build intentionally fails when patch anchors drift.

## Credits

This project is based on
[dciancu/unifi-protect-unvr-docker-arm64](https://github.com/dciancu/unifi-protect-unvr-docker-arm64).
The upstream project established the working UNVR-in-Docker pattern, including
firmware extraction, privileged systemd container operation, UniFi Core patching,
storage shims, and many of the operational caveats this repo still follows.

See the upstream README and acknowledgements for its own lineage and credits.

## Disclaimer

This project is experimental and is not associated with, endorsed by, or
supported by Ubiquiti. Use it at your own risk. You are responsible for backups,
network security, door-safety requirements, local laws, and the consequences of
running unsupported access-control software.
