#!/usr/bin/env bash
set -euo pipefail
baseUrl="${1:-http://localhost:8000}"
webUrl="${2:-http://localhost:3000}"
command -v curl >/dev/null
for route in heartbeat middleware/heartbeat tienda; do
    curl --fail --silent --show-error --max-time 20 "$baseUrl/$route" >/dev/null
    echo "PASS GET /$route"
done
for route in jugadores cafeteria; do
    code="$(curl --silent --show-error --max-time 20 --output /dev/null --write-out '%{http_code}' "$baseUrl/$route")"
    [ "$code" = "401" ]
    echo "PASS /$route exige autenticación"
done
curl --fail --location --silent --show-error --max-time 20 "$webUrl/" | grep -q 'index.wasm'
echo "PASS frontend a través del gateway"
instanceNames="$(for attempt in 1 2 3 4 5 6; do
    curl --fail --silent --show-error --max-time 20 --dump-header - --output /dev/null "$baseUrl/tienda" | tr -d '\r' | awk 'tolower($1) == "x-instance-name:" {print $2}'
done)"
printf '%s\n' "$instanceNames" | grep -qx 'tienda-service-1'
printf '%s\n' "$instanceNames" | grep -qx 'tienda-service-2'
echo "PASS ambas instancias atienden peticiones"
