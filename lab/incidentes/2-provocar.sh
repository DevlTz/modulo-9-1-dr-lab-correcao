#!/usr/bin/env bash
# incidentes/3-provocar.sh
# Família: Dados   Incidente: Perda do backup local
# CHECKLIST DE SEGURANÇA (obrigatório antes de usar):
#  [x] Existe 3-reverter.sh escrito e testado.
#  [x] A ação fica dentro da rede lab91_lab (nada fora do laboratório).
#  [x] O incidente de capacidade NÃO enche o disco do host.
#  [x] Critério de parada combinado: 45 min ou efeito fora do laboratório.
set -e

echo "Provocando a perda do backup local..."
# Força o container de backup a apagar os dumps usando sh -c
docker compose exec -T backup sh -c "rm -f /backups/*.dump"

echo "Todos os dumps locais foram apagados. O diretório de backups deve estar vazio."
echo "Recuperação esperada: sincronizar os arquivos de dump de volta a partir do bucket minio para o diretório local."
