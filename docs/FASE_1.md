# Fase 1 — evidencia y límites

Verificación local: 21 de octubre de 2026, zona America/Mexico_City (logs Docker en UTC del 22).
Sin commits realizados.

## Entorno

Docker 29.8.1, Compose v5.5.1 y Godot 4.7.2 estable Fedora.
En el primer intento no había daemon Docker; después de iniciarlo el usuario se pudieron completar las pruebas.
`.env` local se creó con contraseñas aleatorias, permisos 0600 y exclusión de Git. No se publican sus valores.

## Comprobaciones de código

- `docker compose --env-file .env.example config --quiet`: salida 0.
- En los cuatro módulos: `go test ./...` y `go vet ./...`: salida 0. No hay casos unitarios; `go test` comprueba compilación en esta fase.
- `bash -n setup.sh tools/verify_infra.sh`, `node --check frontend/app.js` y `git diff --check`: salida 0.

## Construcción y arranque reales

```bash
docker compose up --build -d --wait
docker compose exec -T gateway nginx -t
bash tools/verify_infra.sh
```

Se construyeron las seis imágenes de aplicación y arrancaron los diez contenedores del proyecto.
El primer arranque detectó un fallo real: `pg_isready` por socket local marcaba disponible el servidor temporal de inicialización. Cafetería recibió conexión rechazada. Se corrigió a comprobación TCP y se añadieron reintentos acotados de conexión al backend; el arranque posterior terminó con todos saludables.

Resultados obtenidos:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
PASS GET /heartbeat
PASS GET /middleware/heartbeat
PASS GET /jugadores
PASS GET /tienda
PASS GET /cafeteria
PASS frontend a través del gateway
PASS ambas instancias atienden peticiones
```

## Caída y recuperación

Se ejecutó `docker compose stop tienda-service-1`, se consultó `/tienda` seis veces leyendo `X-Instance-Name` y se restauró con `docker compose start tienda-service-1` en un bloque de recuperación garantizada. Después se consultó hasta observar ambas instancias.

```text
PASS caída de tienda-service-1: 6/6 respuestas de tienda-service-2
PASS recuperación: ambas instancias reciben tráfico
```

La detección es pasiva; Consul aún no está integrado.

## Persistencia

Un script de verificación creó registros exclusivos mediante POST en `/jugadores`, `/tienda` y `/cafeteria`, usando un nombre con UUID. Luego ejecutó:

```bash
docker compose up -d --force-recreate --wait
```

Después consultó cada recurso por ID y comparó todos sus campos con la respuesta original:

```text
PASS persistencia tras recreación: /jugadores id=3
PASS persistencia tras recreación: /tienda id=3
PASS persistencia tras recreación: /cafeteria id=1
PASS limpieza de los tres registros exclusivos de prueba
```

Se eliminaron únicamente esos tres registros mediante SQL en sus bases correspondientes. No se eliminaron volúmenes ni datos anteriores a la prueba. Esta verificación recreó contenedores conservando los volúmenes nombrados; no constituye una prueba de restauración desde respaldo.

## Godot

```bash
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/verify_plaza.gd -- --plaza-preview
godot --headless --path . --script res://tools/verify_pixel_ui.gd -- --plaza-preview
godot --path . -- --plaza-preview --plaza-capture=/tmp/pixel-penguin-fase1.png
```

La primera importación avisó de caché de fuente ausente antes de importar los recursos. Las ejecuciones posteriores cargaron fuente y tema sin esos errores.

```text
PASS Plaza sin NPC simulados
PLAZA_VALIDATION failures=0
PIXEL_UI_VALIDATION failures=0
PLAZA_CAPTURE /tmp/pixel-penguin-fase1.png status=0
```

La prueba de plaza comprobó A*, llegada física, puertas, límites y paseo sin cuenta. La prueba de UI comprobó español, fuente, estados de botones y distribución lógica 960×600; en headless no valida renderizado ni varios tamaños de ventana.
La captura real usó OpenGL Compatibility en Intel Arc y se inspeccionó visualmente. Copia: `docs/fase1/plaza.png`. No se sustituyeron capturas originales.

## Límites y siguientes fases

- Godot 4.6 y revisión visual en otros tamaños de ventana pendientes.
- No hay NPC activos, presencia conectada ni movimiento sincronizado.
- Cuentas, compras seguras y chat todavía pendientes.
- Consul y balanceo gRPC pendientes de las actividades 2 y 3.
- El middleware conserva solo su heartbeat como base de la futura aplicación.
- Ningún contenedor ajeno al proyecto fue iniciado ni modificado.

## Referencias

- Nginx upstream: https://nginx.org/en/docs/http/ngx_http_upstream_module.html
- Compose startup order: https://docs.docker.com/compose/how-tos/startup-order/
