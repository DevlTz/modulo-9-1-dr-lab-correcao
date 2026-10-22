#!/bin/sh
set -eu
node=${HAPROXY_SERVER_NAME:?}
case "$node" in pg-primary|pg-replica) ;; *) exit 1;; esac
[ "$(cat /control/active 2>/dev/null)" = "$node" ] || exit 1
[ ! -e "/control/fenced-$node" ] || exit 1
export PGCONNECT_TIMEOUT=2 PGOPTIONS='-c statement_timeout=2000'
# Usa o endereço realmente associado ao backend pelo HAProxy.
result=$(psql -X -w -h "${HAPROXY_SERVER_ADDR:?}" -p "${HAPROXY_SERVER_PORT:-5432}" \
  -U postgres -d loja -Atq -v ON_ERROR_STOP=1 \
  -c "SELECT NOT pg_is_in_recovery() AND current_setting('transaction_read_only') = 'off'")
[ "$result" = t ]
