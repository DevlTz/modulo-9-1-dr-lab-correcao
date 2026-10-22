#!/bin/bash
set -Eeuo pipefail
: "${NODE_NAME:?}"
active=$(cat /control/active)
if [[ ! -s "$PGDATA/PG_VERSION" && "$NODE_NAME" == pg-primary && "$active" != pg-primary ]]; then
  echo 'BLOQUEADO: não inicializar banco vazio fora da autorização.' >&2
  exit 1
fi
# Um antigo primário não pode reiniciar como escritor fora da autorização.
if [[ -s "$PGDATA/PG_VERSION" && ! -f "$PGDATA/standby.signal" && "$active" != "$NODE_NAME" ]]; then
  echo "BLOQUEADO: $NODE_NAME não é o escritor autorizado; execute rejoin.sh." >&2
  exit 1
fi
if [[ -f "/control/fenced-$NODE_NAME" && ! -f "$PGDATA/standby.signal" ]]; then
  echo "BLOQUEADO: nó isolado pelo procedimento de failover." >&2
  exit 1
fi
if [[ ! -s "$PGDATA/PG_VERSION" && "$NODE_NAME" == pg-replica ]]; then
  [[ "$active" == pg-primary ]] || { echo 'Bootstrap exige pg-primary ativo.' >&2; exit 1; }
  # Não limpa silenciosamente um volume parcialmente inicializado.
  [[ -z "$(find "$PGDATA" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
    echo 'PGDATA incompleto: inspecione o volume antes de tentar novamente.' >&2; exit 1;
  }
  ready=0
  for ((i=0; i<60; i++)); do
    if pg_isready -h pg-primary -U replicador -d loja; then ready=1; break; fi
    sleep 2
  done
  [[ $ready == 1 ]] || exit 1
  pg_basebackup -h pg-primary -U replicador -D "$PGDATA" -Fp -Xs -R -P
  chmod 0700 "$PGDATA"
fi
# Mesmos parâmetros nos dois nós, inclusive após promoção.
exec /usr/local/bin/docker-entrypoint.sh postgres \
  -c wal_level=replica -c max_wal_senders=10 -c wal_keep_size=256MB \
  -c hot_standby=on -c max_connections=60 \
  -c archive_mode=on -c archive_timeout=60 \
  -c 'archive_command=/opt/lab/archive-wal.sh %p %f' \
  -c 'restore_command=cp /archive/%f %p'
