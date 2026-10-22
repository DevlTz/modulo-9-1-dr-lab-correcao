#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# == 0 ]] || die 'Uso: ./lab.sh backup'
lock_operation
active=$(cat runtime/active)
node_valid "$active" || die 'Nenhum escritor autorizado.'
[[ ! -e "runtime/fenced-$active" ]] || die 'Escritor isolado; investigar antes do backup.'
dc stop backup
result=0
dc run --rm --no-deps -T backup once || result=$?
# Retoma o agendamento inclusive se o backup avulso falhou, mantendo seu erro.
dc up -d --no-deps backup || { [[ $result != 0 ]] || result=1; }
exit "$result"
