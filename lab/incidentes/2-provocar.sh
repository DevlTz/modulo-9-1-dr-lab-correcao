#!/usr/bin/env bash
# Incidente 2: perda dos dumps locais concluídos; objetos MinIO preservados.
set -Eeuo pipefail
source "$(dirname "$0")/../scripts/common.sh"
[[ $# == 0 ]] || die 'Uso: ./lab.sh incidente iniciar 2'
lock_operation
# Antes do exercício, o operador deve ter aprovado ./lab.sh testar-backup.
dc exec -T backup python3 /opt/backup.py health
# Se a provocação falhar, retoma a rotina sem anunciar perda bem-sucedida.
resume_on_error() {
  code=$?
  if (( code != 0 )); then
    echo 'Provocação interrompida; tentando retomar a rotina de backup.' >&2
    dc up -d --no-deps backup || true
  fi
}
trap resume_on_error EXIT
dc stop backup
dc run --rm --no-deps -T --entrypoint sh backup -c '
  set -eu
  test -d /backups/complete
  if ! find /backups/complete -type f -name loja.dump -print -quit | grep -q .; then
    echo "Nenhum dump local concluído; incidente não provocado." >&2
    exit 1
  fi
  find /backups/complete -type f -name loja.dump -delete
  rm -f /backups/status.json
  if find /backups/complete -type f -name loja.dump -print -quit | grep -q .; then
    echo "Ainda há dumps locais; exclusão incompleta." >&2
    exit 1
  fi
'
echo 'Dumps locais removidos. Objetos remotos preservados; rotina parada para o exercício.'
echo 'Execute ./lab.sh testar-backup; depois ./lab.sh incidente reverter 2.'
