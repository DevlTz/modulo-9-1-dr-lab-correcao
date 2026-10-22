#!/bin/bash
set -Eeuo pipefail
src=$1
name=$2
[[ "$name" =~ ^[0-9A-F]{24}(\.[0-9A-F]{8}\.backup)?$ || "$name" =~ ^[0-9A-F]{8}\.history$ ]] || exit 1
archive=${ARCHIVE_DIR:-/archive}
dst="$archive/$name"
# Retentativa só é sucesso se os bytes forem os mesmos; nunca sobrescreve divergência.
if [[ -e "$dst" ]]; then cmp -s "$src" "$dst"; exit $?; fi
tmp=$(mktemp "$archive/.${name}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cp "$src" "$tmp"
# Persiste o conteúdo antes de publicar o nome final.
sync -f "$tmp"
# hard link publica atomicamente e não substitui destino já existente.
if ln "$tmp" "$dst"; then sync -f "$archive"; else cmp -s "$src" "$dst"; fi
