#!/bin/bash
# Relocate the default PG 14 `main` cluster to /data so config and data live
# on the same persistent volume the container uses for state. Access's own
# `access` cluster is set up by the unifi-access postinst against /srv.
mkdir -p /data/postgresql/14/main/{data,conf}

if [[ -d /etc/postgresql/14/main ]]; then
  echo "Found /etc/postgresql/14/main dir. Moving everything to /data/postgresql/14/main/conf"
  mv /etc/postgresql/14/main/* /data/postgresql/14/main/conf
  rm -rf /etc/postgresql/14/main
  ln -s /data/postgresql/14/main/conf /etc/postgresql/14/main
fi

# Trust local connections so ulp-go / unifi-core / access do not need a password
# for 127.0.0.1 access. The container is the security boundary.
sed -Ei \
  -e 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+127\.0\.0\.1\/32[[:space:]]+).*/\1trust/' \
  -e 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+::1\/128[[:space:]]+).*/\1trust/' \
  -e 's/^(host[[:space:]]+replication[[:space:]]+all[[:space:]]+127\.0\.0\.1\/32[[:space:]]+).*/\1trust/' \
  -e 's/^(host[[:space:]]+replication[[:space:]]+all[[:space:]]+::1\/128[[:space:]]+).*/\1trust/' \
  /etc/postgresql/14/main/pg_hba.conf
sed -i -e 's/\/var\/lib\/postgresql\/14\/main/\/data\/postgresql\/14\/main\/data/g' /etc/postgresql/14/main/postgresql.conf

chown -R postgres:postgres /data/postgresql
chown -R postgres:postgres /srv/postgresql 2>/dev/null || true
chown -R postgres:postgres /etc/postgresql
