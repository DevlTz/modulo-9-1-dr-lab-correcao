#!/bin/bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
dc() { docker compose -f "$ROOT/docker-compose.yml" "$@"; }
die() { echo "ERRO: $*" >&2; exit 1; }
node_valid() { [[ "$1" == pg-primary || "$1" == pg-replica ]]; }
lock_operation() {
  command -v flock >/dev/null || die 'Instale util-linux (flock).'
  mkdir -p runtime
  exec 9>runtime/operation.lock
  flock -n 9 || die 'Outra operação de DR está em andamento.'
}
sql() { dc exec -T -u postgres "$1" psql -X -w -U postgres -d loja -Atq -v ON_ERROR_STOP=1 -c "$2"; }
set_active() {
  printf '%s\n' "$1" > runtime/active.tmp
  chmod 644 runtime/active.tmp
  sync -f runtime/active.tmp
  mv runtime/active.tmp runtime/active
  sync -f runtime
}
wait_sql() {
  local node=$1 expected=$2 query=$3
  for ((attempt=0; attempt<30; attempt++)); do
    if [[ "$(sql "$node" "$query" 2>/dev/null)" == "$expected" ]]; then return 0; fi
    sleep 2
  done
  die "Validação de $node não convergiu."
}

prepare_runtime() {
  mkdir -p runtime evidencias
  chmod 755 runtime
  if [[ ! -e runtime/active ]]; then set_active pg-primary; fi
  node_valid "$(cat runtime/active)" || die 'Estado de escritor inválido; inspecione o incidente.'
  chmod 755 scripts/*.sh initdb/02-hba.sh lab.sh
  dc config --quiet
}
