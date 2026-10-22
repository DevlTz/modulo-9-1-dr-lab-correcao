#!/bin/bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
active=$(cat runtime/active)
node_valid "$active" || die 'Nenhum escritor autorizado.'
if [[ "$active" == pg-primary ]]; then standby=pg-replica; else standby=pg-primary; fi
[[ "$(sql "$active" 'SELECT pg_is_in_recovery()')" == f ]] || die 'Escritor em recovery.'
[[ "$(sql "$standby" 'SELECT pg_is_in_recovery()')" == t ]] || die 'Redundância ausente.'
[[ "$(sql "$standby" 'SELECT status FROM pg_stat_wal_receiver')" == streaming ]] || die 'Replicação sem streaming.'
[[ "$(sql "$standby" 'SELECT pg_is_wal_replay_paused()')" == f ]] || die 'Replay pausado.'
dc exec -T haproxy psql -X -w -h 127.0.0.1 -U postgres -d loja -v ON_ERROR_STOP=1 \
  -c "BEGIN; INSERT INTO pedidos(cliente,valor) VALUES('dr_check',0); ROLLBACK;"
dc exec -T backup python3 /opt/backup.py health
# Falhas históricas não equivalem a falha atual: exibe os dois tempos para análise.
sql "$active" 'SELECT archived_count, failed_count, last_archived_time, last_failed_time FROM pg_stat_archiver'
echo 'CHECAGEM OK: escrita, streaming e idade do backup; restore deve ser testado separadamente.'
