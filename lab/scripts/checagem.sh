#!/usr/bin/env bash
# Mantém o comando checar e o arquivo de evidência; valida os papéis atuais.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidencias
OUT="evidencias/checagem_$(date +%Y%m%dT%H%M%S).txt"
bash scripts/check.sh 2>&1 | tee "$OUT"
