#!/usr/bin/env bash
# incidentes/1-provocar.sh  —  EXEMPLO RESOLVIDO (Família Disponibilidade)
# Incidente: queda do nó primário do banco.
# Regra de segurança: toda provocação é reversível (ver 1-reverter.sh), fica
# dentro da rede isolada e tem critério de parada (45 min).
set -e
docker compose stop pg-primary
echo "Nó primário parado. O gerador deve passar a imprimir ESCRITA FALHOU."
echo "Recuperação esperada: promover a réplica e reapontar a entrada (runbook de failover)."
