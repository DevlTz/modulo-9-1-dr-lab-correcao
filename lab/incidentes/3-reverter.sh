#!/usr/bin/env bash
# Recupera o standby e aguarda streaming antes de anunciar sucesso.
set -Eeuo pipefail
source "$(dirname "$0")/../scripts/common.sh"
[[ $# == 0 ]] || die 'Uso: ./lab.sh incidente reverter 3'
lock_operation
[[ "$(cat runtime/active)" == pg-primary ]] || die 'Papéis mudaram durante o incidente; confira o estado antes de reverter.'
[[ ! -e runtime/fenced-pg-replica ]] || die 'pg-replica está isolado; é necessária análise/reintegração.'
dc up -d --no-deps pg-replica
wait_sql pg-replica t 'SELECT pg_is_in_recovery()'
wait_sql pg-replica streaming 'SELECT status FROM pg_stat_wal_receiver'
echo 'Standby retomou o streaming.'
