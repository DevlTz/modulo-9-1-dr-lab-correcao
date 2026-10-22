#!/usr/bin/env bash
# incidentes/3-provocar.sh
# Família: Dados   Incidente: Perda do backup local
# CHECKLIST DE SEGURANÇA (obrigatório antes de usar):
#  [x] Existe 3-reverter.sh escrito e testado.
#  [x] A ação fica dentro da rede lab91_lab (nada fora do laboratório).
#  [x] O incidente de capacidade NÃO enche o disco do host.
#  [x] Critério de parada combinado: 45 min ou efeito fora do laboratório.
set -e

docker compose stop pg-replica

echo "Falha provocada: O contêiner pg-replica foi parado."
echo "Sintoma esperado: A aplicação continua funcionando normalmente e o gerador segue gravando, mas a checagem de replicação falhará silenciosamente."
echo "O que se mede: Tempo de detecção da parada da réplica através das métricas de monitoramento/checagem."