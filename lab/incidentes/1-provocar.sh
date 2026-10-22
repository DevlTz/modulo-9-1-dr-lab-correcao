#!/usr/bin/env bash
# Incidente 1: queda do escritor original; exige topologia inicial saudável.
set -Eeuo pipefail
source "$(dirname "$0")/../scripts/common.sh"
[[ $# == 0 ]] || die 'Uso: ./lab.sh incidente iniciar 1'
lock_operation
[[ "$(cat runtime/active)" == pg-primary ]] || die 'Incidente 1 exige pg-primary como escritor; confira os papéis antes de repetir.'
[[ "$(sql pg-primary 'SELECT pg_is_in_recovery()')" == f ]] || die 'pg-primary não é escritor saudável.'
[[ "$(sql pg-replica 'SELECT pg_is_in_recovery()')" == t ]] || die 'pg-replica não é standby.'
[[ "$(sql pg-replica 'SELECT status FROM pg_stat_wal_receiver')" == streaming ]] || die 'Standby sem streaming.'
dc stop pg-primary
echo 'Escritor parado. Observe a consulta no Adminer e os logs do gerador.'
echo 'Recupere com: ./lab.sh failover --aceitar-perda-potencial'
