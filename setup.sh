#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v docker >/dev/null || { echo "Instala Docker antes de continuar."; exit 1; }
[ -f .env ] || { echo "Copia .env.example a .env y configura las contraseñas."; exit 1; }
bash tools/export_web.sh
docker compose up --build -d --wait
echo "Juego Web: http://localhost:3000 | API: http://localhost:8000"
