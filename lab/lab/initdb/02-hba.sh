#!/bin/bash
# Libera a conexão de replicação (precisa ser executável)
set -e
echo "host replication replicador all scram-sha-256" >> "$PGDATA/pg_hba.conf"
