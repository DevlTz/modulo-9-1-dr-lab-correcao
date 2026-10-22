#!/usr/bin/env bash
# Antes da promoção: religa o escritor. Após promoção: exige rejoin explícito.
set -Eeuo pipefail
source "$(dirname "$0")/../scripts/common.sh"
[[ $# == 0 || ( $# == 1 && "$1" == --descartar-dados-do-no ) ]] || die 'Uso: ./lab.sh incidente reverter 1 [--descartar-dados-do-no]'
active=$(cat runtime/active)
if [[ "$active" == pg-replica ]]; then
  [[ "${1:-}" == --descartar-dados-do-no ]] || die 'Após o failover, reintegrar pg-primary substitui seus dados. Preserve dados divergentes se necessário; use: ./lab.sh incidente reverter 1 --descartar-dados-do-no'
  exec bash scripts/rejoin.sh pg-primary --descartar-dados-do-no
fi
lock_operation
[[ "$(cat runtime/active)" == pg-primary ]] || die 'Escritor mudou ou está indefinido; confira o estado antes de reverter.'
[[ ! -e runtime/fenced-pg-primary ]] || die 'Nó isolado; investigue o failover antes de religar.'
dc up -d --no-deps pg-primary
wait_sql pg-primary f 'SELECT pg_is_in_recovery()'
echo 'pg-primary voltou sem troca de escritor.'
