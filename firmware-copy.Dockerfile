# Tiny image that just holds the extracted firmware artifacts so the
# build pipeline can copy them out (`docker create` + `docker cp`) into
# ./firmware on disk. Used by build-firmware.sh.
FROM scratch
COPY --from=unifi-os-firmware /opt/firmware-build /
