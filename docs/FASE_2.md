# Actividad 2 — Consul y descubrimiento dinámico

## Cambios

Consul 1.22 en un contenedor propio con almacenamiento persistente, sin publicar puertos en el host.
Los tres backends comparten el módulo local `pixelpenguin/platform/registry`, que registra ID, nombre lógico, IP y puerto de cada instancia. No se añadió ninguna biblioteca Go externa.

El contenedor gateway incluye un sincronizador Go y Nginx. El sincronizador consulta únicamente instancias `passing` con etiqueta `http`, genera upstreams, valida cada cambio con `nginx -t` y solicita recarga gradual. No se usa el socket de Docker y no hay listas estáticas de IP o nombres de contenedores de backend.
La configuración final se puede inspeccionar dentro del gateway en `/etc/nginx/nginx.conf`; la fuente versionada es `nginx/nginx.conf.tmpl`.

El registro arranca crítico, pasa a saludable tras el check HTTP y consulta PostgreSQL. Los cierres normales solicitan baja; Consul retira registros críticos después del plazo configurado y su ciclo de limpieza. El registro se recupera si desaparece y se actualiza si cambia la IP del contenedor.
Si no quedan destinos, Nginx responde 503. Si Consul falla, los destinos previos caducan después de 10 segundos sin una consulta completa exitosa, más los tiempos acotados de consulta y sincronización.

Se retiraron los formularios públicos y `frontend/app.js`. La web ahora muestra una portada con instrucciones para entrar mediante Godot. No hay login o registro simulados. Los endpoints heredados aún requieren protección en las próximas fases; retirar formularios no resuelve la autenticación.

## Archivos principales

- `platform/registry/registry.go`, `registry_test.go`: registro, baja y recuperación.
- `platform/cmd/gateway/main.go`, `main_test.go`: descubrimiento, validación y supervisor de Nginx.
- `nginx/nginx.conf.tmpl`, `nginx/Dockerfile`: plantilla e imagen.
- `backend/*/main.go`, `go.mod`, Dockerfiles: integración del módulo compartido y construcción desde la raíz.
- `docker-compose.yml`: Consul, almacenamiento, dependencias y configuración de servicios.
- `tools/verify_discovery.py`: pruebas reproducibles con restauración por escenario.
- `frontend/index.html`, `style.css`, Dockerfile: portada sin administración.

Se eliminaron los archivos obsoletos `middleware/services.json` y `frontend/app.js`. El middleware conserva su base de aplicación sin balanceador duplicado.

## Ejecución y comprobaciones

```bash
docker compose up --build -d --wait
bash tools/verify_infra.sh
docker compose exec -T gateway nginx -t
python3 tools/verify_discovery.py
```

Para guardar salida, usando Bash:

```bash
set -o pipefail
python3 tools/verify_discovery.py | tee docs/fase2/validation.log
```

El verificador interrumpe temporalmente servicios del proyecto. Ejecutarlo sin otros usuarios conectados; restaura cada servicio en un bloque `finally`. No borra volúmenes ni modifica datos de negocio. La prueba de la instancia temporal puede tardar varios minutos por la limpieza real de Consul.

Inspección directa:

```bash
docker compose exec -T consul consul catalog services
docker compose exec -T consul wget -qO- 'http://127.0.0.1:8500/v1/health/service/tienda?passing=true'
docker compose exec -T gateway cat /etc/nginx/nginx.conf
docker compose logs --tail 30 gateway
```

## Resultados reales

Se ejecutaron `go test ./...` y `go vet ./...` en `platform` y los tres backends: salida 0. En `platform` hay pruebas reales de registro inicial, registro existente, cambio de IP, errores de Consul, bajas, filtrado de salud/protocolo, deduplicación, orden estable y rechazo de endpoints inválidos. Los módulos backend siguen sin pruebas unitarias de negocio.

La construcción y el arranque terminaron con los once contenedores saludables. `nginx -t` y el smoke test HTTP pasaron después de terminar las pruebas de fallos.

El log íntegro está en `docs/fase2/validation.log`; incluye:

```text
PASS baja normal elimina registro y destino de Nginx
PASS caída abrupta excluye instancia no saludable del enrutamiento
PASS Consul elimina registro crítico tras plazo de limpieza
PASS nueva instancia se registra sin editar destinos
PASS Nginx enruta a la nueva instancia descubierta
PASS base caída deja cero destinos saludables y devuelve 503
PASS pérdida de Consul caduca destinos anteriores y devuelve 503
DISCOVERY_VALIDATION failures=0
```

Además se comprobó HTTP 404 para `/app.js` y que la portada no contiene inputs, formularios ni referencia al script eliminado.
Firefox headless generó una captura a 1280×800, inspeccionada visualmente y guardada en `docs/fase2/portada.png`.
No se modificaron escenas, recursos ni scripts Godot durante esta fase. Las rutas HTTP que usa Godot pasaron el smoke test; no se repitió una sesión gráfica del juego en esta fase.

## Límites y siguiente actividad

Consul es de un solo nodo y no tiene ACL; esta configuración es local y académica. La pérdida del registry termina suspendiendo el tráfico de aplicación intencionalmente. El heartbeat del gateway indica disponibilidad del proxy, no de todos los backends.
Frontend y heartbeat del middleware conservan nombres Docker fijos; el descubrimiento dinámico corresponde a los tres servicios backend.
No hay gRPC todavía. La siguiente actividad definirá contratos, adaptadores HTTP y balanceo gRPC real mediante Nginx y grpcurl.
Registro de cuentas, sesiones, compras seguras y chat permanecen pendientes.

No se realizaron commits. Esta actividad queda agrupada por sus archivos para revisión y un commit posterior solicitado por el usuario; no hay hashes que atribuir.

## Referencias

- Registro/baja de servicios: https://developer.hashicorp.com/consul/api-docs/agent/service
- Consulta de salud y filtro passing: https://developer.hashicorp.com/consul/api-docs/health
- Recarga gradual de Nginx: https://nginx.org/en/docs/control.html
