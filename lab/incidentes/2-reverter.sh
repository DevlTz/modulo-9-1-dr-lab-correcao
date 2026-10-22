#!/usr/bin/env bash
# incidentes/3-reverter.sh
# Desfaz o incidente gerando um novo backup imediatamente.
set -e

echo "Gerando uma nova cópia de backup a partir do primário..."
docker compose exec -T backup sh -c "pg_dump -h pg-primary -U postgres -d loja -Fc > /backups/bk_\$(date +%Y%m%d_%H%M).dump"

echo "Revertido com sucesso. Rode ./lab.sh checar para confirmar."