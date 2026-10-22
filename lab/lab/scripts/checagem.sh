#!/usr/bin/env bash
# scripts/checagem.sh — checagem pré-voo do ambiente (base da seção de aceite do D1)
mkdir -p evidencias
OUT="evidencias/checagem_$(date +%F_%H%M).txt"
{
  echo "== Checagem $(date '+%F %T') =="
  docker compose ps --format 'table {{.Name}}\t{{.State}}'
  docker compose exec -T pg-primary psql -U postgres -At \
    -c "SELECT 'replicacao', state FROM pg_stat_replication;"
  docker compose exec -T pg-replica psql -U postgres -At \
    -c "SELECT 'replica_em_recovery', pg_is_in_recovery();"
  docker compose exec -T pg-primary psql -U postgres -d loja -At \
    -c "SELECT 'primario', count(*), max(criado) FROM pedidos;"
  docker compose exec -T pg-replica psql -U postgres -d loja -At \
    -c "SELECT 'replica', count(*), max(criado) FROM pedidos;"
  docker compose exec -T pg-primary psql -U postgres -At \
    -c "SELECT 'arquivamento', failed_count, last_archived_time FROM pg_stat_archiver;"
  echo -n "backups_locais: "; docker compose exec -T backup sh -c 'ls -1 /backups | wc -l'
} 2>&1 | tee "$OUT"
