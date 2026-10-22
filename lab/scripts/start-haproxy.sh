#!/bin/sh
set -eu
active=$(cat /control/active)
case "$active" in pg-primary|pg-replica) ;; *) echo 'Nenhum escritor autorizado.' >&2; exit 1;; esac
[ ! -e "/control/fenced-$active" ] || exit 1
# No HAProxy 2.9 um backend pode começar UP antes do primeiro check.
# Desabilita administrativamente o não eleito ANTES de abrir o listener.
awk -v active="$active" '
  $1 == "server" && ($2 == "pg-primary" || $2 == "pg-replica") && $2 != active {
    print $0 " disabled"; next
  }
  {print}
' /usr/local/etc/haproxy/haproxy.cfg > /tmp/haproxy.runtime.cfg
export HAPROXY_SERVER_NAME="$active" HAPROXY_SERVER_ADDR="$active" HAPROXY_SERVER_PORT=5432
ready=0
for i in $(seq 1 60); do
  if /opt/lab/check-writer.sh; then ready=1; break; fi
  sleep 2
done
[ "$ready" = 1 ] || { echo 'Escritor indisponível; proxy não iniciado.' >&2; exit 1; }
# A troca de escritor é sempre feita com o proxy parado e recria esta configuração.
[ "$(cat /control/active)" = "$active" ] || exit 1
exec haproxy -W -db -f /tmp/haproxy.runtime.cfg
