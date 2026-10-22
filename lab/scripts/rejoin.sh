#!/bin/bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# == 2 ]] || die 'Uso: bash scripts/rejoin.sh pg-primary|pg-replica --descartar-dados-do-no'
target=$1
node_valid "$target" || die 'Nó inválido.'
[[ "$2" == --descartar-dados-do-no ]] || die 'Reclone exige aceite explícito do descarte do volume do nó antigo.'
lock_operation
active=$(cat runtime/active)
node_valid "$active" || die 'Escritor inválido.'
[[ "$active" != "$target" ]] || die 'Nunca execute rejoin no escritor ativo.'
[[ "$(sql "$active" 'SELECT pg_is_in_recovery()')" == f ]] || die 'Escritor não validado.'
# Mantém o nó bloqueado até clone e streaming serem confirmados.
touch "runtime/fenced-$target"
sync -f runtime
dc stop -t 30 "$target"
id=$(dc ps -a -q "$target")
[[ -n "$id" && "$(docker inspect --format '{{.State.Running}}' "$id")" == false ]] || die 'Não foi possível confirmar nó parado.'
# O clone substitui exclusivamente o PGDATA do alvo, jamais do escritor.
# Se existir WAL/escrita divergente, exporte a evidência antes de autorizar este comando.
dc run --rm --no-deps -T --user postgres -e "SOURCE_NODE=$active" \
  -e PGPASSWORD=replica123 --entrypoint bash "$target" -ceu '
    [[ "$PGDATA" == /var/lib/postgresql/data ]] || exit 1
    [[ "$SOURCE_NODE" != "$NODE_NAME" ]] || exit 1
    [[ "$(cat /control/active)" == "$SOURCE_NODE" ]] || exit 1
    [[ -f "/control/fenced-$NODE_NAME" ]] || exit 1
    find "$PGDATA" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    pg_basebackup -h "$SOURCE_NODE" -U replicador -D "$PGDATA" -Fp -Xs -R -P
    pg_verifybackup "$PGDATA"
    chmod 0700 "$PGDATA"
    test -f "$PGDATA/standby.signal"
  '
dc up -d --no-deps "$target"
wait_sql "$target" t 'SELECT pg_is_in_recovery()'
wait_sql "$target" streaming 'SELECT status FROM pg_stat_wal_receiver'
rm "runtime/fenced-$target"
sync -f runtime
echo "$target reintegrado como standby. Escritor permanece $active; não há failback automático."
