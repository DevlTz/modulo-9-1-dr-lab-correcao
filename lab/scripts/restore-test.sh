#!/bin/bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# -le 1 ]] || die 'Uso: bash scripts/restore-test.sh [sets/.../manifest.json]'
lock_operation
mkdir -p evidencias
log="evidencias/restore-$(date -u +%Y%m%dT%H%M%SZ).log"
# Só este serviço efêmero é removido; nenhum volume da aplicação é alterado.
cleanup() { dc --profile restore rm -sf restore-db; }
trap cleanup EXIT
dc --profile restore up -d --wait --wait-timeout 120 restore-db
# Sem leitura de /backups: a fonte é exclusivamente o MinIO.
dc run --rm --no-deps -T backup restore-test "$@" 2>&1 | tee "$log"
