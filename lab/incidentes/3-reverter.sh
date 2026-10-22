#!/usr/bin/env bash
# incidentes/3-reverter.sh
# Desfaz o incidente gerando um novo backup imediatamente.
set -e

docker compose start pg-replica

echo "Secundário religado. Rode ./lab.sh checar para confirmar."