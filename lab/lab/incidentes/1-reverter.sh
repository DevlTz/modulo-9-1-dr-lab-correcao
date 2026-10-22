#!/usr/bin/env bash
# incidentes/1-reverter.sh  —  desfaz o incidente 1 e devolve o ambiente ao normal
set -e
docker compose start pg-primary
# Se a réplica foi promovida durante a recuperação, o antigo primário volta
# divergente; recrie a réplica para o próximo incidente:
#   docker compose down && docker volume rm lab91_replica_data && docker compose up -d
echo "Primário religado. Rode ./lab.sh checar para confirmar."
