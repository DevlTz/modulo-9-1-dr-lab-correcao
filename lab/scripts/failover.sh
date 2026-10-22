#!/bin/bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# == 1 && "$1" == --aceitar-perda-potencial ]] || die 'Uso: bash scripts/failover.sh --aceitar-perda-potencial (replicação assíncrona).'
lock_operation
old=$(cat runtime/active)
node_valid "$old" || die 'Estado inválido; recuperação manual necessária.'
if [[ "$old" == pg-primary ]]; then new=pg-replica; else new=pg-primary; fi
[[ ! -e "runtime/fenced-$new" ]] || die 'Candidato ainda está isolado; conclua rejoin.'
[[ "$(sql "$new" 'SELECT pg_is_in_recovery()')" == t ]] || die 'Candidato não é standby saudável.'
[[ "$(sql "$new" 'SELECT pg_is_wal_replay_paused()')" == f ]] || die 'Replay pausado; investigar antes da promoção.'
mkdir -p evidencias
log="evidencias/failover-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$log") 2>&1
trap 'echo "FALHA: tráfego permanece bloqueado se a troca não terminou. Consulte runtime e os logs." >&2' ERR
echo "T0=$(date -u +%FT%TZ) old=$old new=$new"
# Captura LSN; se o antigo primário estiver inacessível, não promete perda zero.
sql "$new" "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp()"
dc stop gerador backup
# Bloqueio persistente antes de qualquer promoção.
touch "runtime/fenced-$old"
sync -f runtime
set_active none
dc stop haproxy
old_id=$(dc ps -a -q "$old")
[[ -n "$old_id" ]] || die 'Não foi possível identificar o antigo primário para isolar.'
dc stop -t 30 "$old"
[[ "$(docker inspect --format '{{.State.Running}}' "$old_id")" == false ]] || die 'Isolamento não confirmado; promoção cancelada.'
# Espera aplicar todo WAL já recebido. Não equivale a conhecer WAL perdido no primário.
wait_sql "$new" t "SELECT COALESCE(pg_last_wal_replay_lsn() >= pg_last_wal_receive_lsn(), false)"
[[ "$(sql "$new" 'SELECT pg_promote(true, 60)')" == t ]] || die 'Promoção não concluída.'
wait_sql "$new" f 'SELECT pg_is_in_recovery()'
set_active "$new"
dc up -d --no-deps haproxy
# Prova escrita real pelo caminho usado pela aplicação; transação revertida.
ok=0
for ((i=0; i<30; i++)); do
  if dc exec -T haproxy psql -X -w -h 127.0.0.1 -U postgres -d loja -v ON_ERROR_STOP=1 \
    -c "BEGIN; INSERT INTO pedidos(cliente,valor) VALUES('dr_probe',0); ROLLBACK;"; then ok=1; break; fi
  sleep 2
done
[[ $ok == 1 ]] || die 'Proxy ainda não permite escrita.'
dc up -d --no-deps gerador backup
echo "T_ESCRITA=$(date -u +%FT%TZ) writer=$new"
echo "Antigo nó continua isolado. Execute rejoin.sh para recuperar a redundância."
