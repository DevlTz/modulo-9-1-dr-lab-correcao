#!/usr/bin/env bash
# Recompõe a proteção com novo backup e retoma o agendamento.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
[[ $# == 0 ]] || { echo 'Uso: ./lab.sh incidente reverter 2' >&2; exit 1; }
bash scripts/backup-now.sh
echo 'Novo backup concluído e rotina retomada.'
