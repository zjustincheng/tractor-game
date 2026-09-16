#!/usr/bin/env sh
set -eu

compose_file="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/compose.yaml"
docker compose -f "$compose_file" config --quiet
docker compose -f "$compose_file" up -d --build
docker compose -f "$compose_file" ps
