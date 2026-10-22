#!/usr/bin/env bash
# incidentes/<n>-provocar.sh — PREENCHER
# Família: __________   Incidente: __________
# CHECKLIST DE SEGURANÇA (obrigatório antes de usar):
#  [ ] Existe <n>-reverter.sh escrito e testado.
#  [ ] A ação fica dentro da rede lab91_lab (nada fora do laboratório).
#  [ ] O incidente de capacidade NÃO enche o disco do host.
#  [ ] Critério de parada combinado: 45 min ou efeito fora do laboratório.
set -e

# TODO: comando que provoca a falha (reversível). Exemplos no CATALOGO.md.
# docker compose stop <servico>
# docker network disconnect lab91_lab <servico>
# docker compose exec pg-primary psql -U postgres -d loja -c "DELETE FROM pedidos WHERE criado > now() - interval '2 min';"

echo "Falha provocada. Descreva aqui o sintoma esperado."
