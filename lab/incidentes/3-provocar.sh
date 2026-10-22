#!/usr/bin/env bash
# Incidente 3: queda do standby; nunca desligar um pg-replica promovido.
set -Eeuo pipefail
source "$(dirname "$0")/../scripts/common.sh"
[[ $# == 0 ]] || die 'Uso: ./lab.sh incidente iniciar 3'
lock_operation
[[ "$(cat runtime/active)" == pg-primary ]] || die 'Incidente 3 exige pg-primary escritor e pg-replica standby; confira os papéis.'
[[ "$(sql pg-primary 'SELECT pg_is_in_recovery()')" == f ]] || die 'Escritor indisponível.'
[[ "$(sql pg-replica 'SELECT pg_is_in_recovery()')" == t ]] || die 'pg-replica não é standby; parada cancelada.'
dc stop pg-replica
echo 'Standby parado. Pedidos devem continuar; ./lab.sh validar deve detectar redundância ausente.'
