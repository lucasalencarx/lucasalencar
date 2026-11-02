#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
command -v docker >/dev/null || { echo 'Instale o Docker Engine e Compose seguindo o GUIA-LOCAL.md.'; exit 1; }
docker compose version >/dev/null
umask 077
if [ ! -f .env ]; then
  command -v openssl >/dev/null || { echo 'Instale openssl para gerar a chave.'; exit 1; }
  printf 'N8N_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)" > .env
fi
docker compose up -d
printf '\nAbra http://localhost:5678 e crie o acesso administrativo do n8n.\nGuarde .env e o volume n8n_data em backup.\n'
