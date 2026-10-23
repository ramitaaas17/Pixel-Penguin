# Pixel-Penguin — sistema distribuido

Juego Godot con plaza nevada, servicios Go y bases PostgreSQL independientes.
La escena principal es `scenes/plaza/Plaza.tscn`. El mapa anterior y sus recursos se conservan.

## Estado del proyecto

- Actividad 1: Nginx como gateway y balanceador HTTP; persistencia, health checks y recuperación verificados. Evidencia histórica: `docs/FASE_1.md`.
- Actividad 2: Consul y sincronización de destinos saludables con Nginx. Implementación y evidencia: `docs/FASE_2.md`, `docs/fase2/validation.log`.
- Actividad 3: contratos Protocol Buffers, comunicación gRPC real y balanceo mediante Nginx. Evidencia: `docs/FASE_3.md` y `docs/fase3/`.
- Fase 4: registro, login, sesiones revocables y pantallas integradas en Godot. Evidencia: `docs/FASE_4.md`.
- Chat global autenticado, presencia y movimiento compartido entre clientes Web y nativos: `docs/CHAT_Y_PRESENCIA.md`. Sin NPC activos. Los comercios siguen en consulta hasta implementar las compras seguras de la fase 5.

La web abre el juego Godot exportado a WebAssembly, con la misma plaza, registro y login que la aplicación nativa. Detalles: `docs/WEB.md`. Las escrituras antiguas de monedas, stock y pedidos están bloqueadas tanto por HTTP como por gRPC; el servidor determina la identidad a partir de la sesión.

## Arquitectura actual

```text
Godot / Web ── HTTP ──→ Nginx público :3000 / :8000
                        ├→ Frontend estático (juego WebAssembly)
                        ├→ /plaza WebSocket → sala global del middleware
                        └→ Middleware Go (adaptador HTTP/JSON)
                             └─ gRPC → Nginx interno :9090
                                        ├→ Jugadores + Auth gRPC → PostgreSQL
                                        ├→ Tienda gRPC ×2 → PostgreSQL
                                        └→ Cafetería gRPC → PostgreSQL
                                             └─ gRPC → Nginx → Auth.GetSession

Backend Go → registro/bajas → Consul
Consul → gRPC Health Check → Backend → comprobación de PostgreSQL
Consul → instancias passing → sincronizador Go → upstreams de Nginx
```

Nginx enruta y balancea. El middleware adapta HTTP/JSON a gRPC; no tiene balanceador propio. Cafetería consulta Auth.GetSession para recuperar la identidad y filtrar pedidos privados.
Los servicios mantienen HTTP 8080 únicamente para salud local y gRPC 9090 para negocio. Los puertos internos no se publican; el gateway recibe HTTP externo y gRPC interno en recorridos separados. `services.json` ya no existe.
La comunicación gRPC usa HTTP/2 sin TLS dentro de la red privada de desarrollo. `/plaza` usa WebSocket para chat y presencia; una sola instancia del middleware coordina la sala y valida sesiones por gRPC. No se soportan réplicas de esa sala sin coordinación adicional.

## Ejecutar

Requisitos: Godot 4.7.2 con sus plantillas de exportación Web instaladas (Editor → Administrar plantillas de exportación), Docker funcionando y Docker Compose con `--wait`. Go 1.26 o superior y Python 3 solo son necesarios en el host para desarrollo y pruebas. Las imágenes compilan con Go 1.26. Para regenerar contratos se necesita también protoc.

```bash
cp .env.example .env
# Configurar contraseñas propias antes del primer arranque.
bash setup.sh
```

No sobrescribir un `.env` existente. Variables requeridas: `JUGADORES_DB_PASSWORD`, `TIENDA_DB_PASSWORD`, `CAFETERIA_DB_PASSWORD`. `.env` está excluido de Git.

- Juego en navegador: http://localhost:3000
- API de Godot: http://localhost:8000
- Salud del gateway: http://localhost:8000/heartbeat
- Salud del middleware: http://localhost:8000/middleware/heartbeat

El gateway espera a sus dependencias saludables. Durante los primeros ciclos de Consul puede responder 503 hasta que los servicios estén registrados y pasando sus checks.
El heartbeat del gateway indica que Nginx responde; no asegura que todos los servicios de aplicación estén disponibles.

```bash
docker compose --env-file .env.example config --quiet
docker compose ps
docker compose exec -T gateway nginx -t
bash tools/verify_infra.sh
```

## Actividad 1 — Nginx

El gateway publica 3000 y 8000, mantiene `/jugadores`, `/tienda` y `/cafeteria`, y balancea llamadas gRPC entre las instancias disponibles después de la adaptación HTTP. `X-Instance-Name` identifica la instancia de tienda y `X-Gateway` identifica el proxy.
La web usa el mismo origen. Godot nativo conserva su URL HTTP; la exportación Web utiliza `window.location.origin` para acceder al backend por el mismo gateway, conservando host, puerto y protocolo.
El Nginx del frontend solo sirve archivos; el gateway dedicado realiza proxy y balanceo.

La fase 1 usaba upstreams estáticos. La fase 2 los reemplaza por una plantilla dinámica; su evidencia previa queda conservada como historial.

## Actividad 2 — Consul

Cada backend utiliza `platform/registry`: registra ID único, nombre lógico, IP del contenedor, puerto 9090 y etiqueta `grpc`. Se registra inicialmente como `critical`; Consul ejecuta `grpc.health.v1.Health/Check` cada 2 segundos, con timeout de 1 segundo. Ese check consulta PostgreSQL con un contexto acotado.
Al recibir SIGTERM/SIGINT el servicio solicita su baja y cierra HTTP y gRPC. Ante SIGKILL, Consul excluye el servicio al fallar su check y elimina el registro después de un minuto crítico más el ciclo de limpieza del agente.
Cada servicio revisa su registro cada 3 segundos: lo restaura si falta y actualiza la IP si cambió. No reinicia continuamente los checks saludables.

El gateway consulta `/v1/health/service/<nombre>?passing=true&tag=grpc` para jugadores, tienda y cafetería. Solo los nombres lógicos están definidos en código; las IP, puertos y cantidad de instancias proceden de Consul.
Ordena y deduplica destinos, renderiza `nginx/nginx.conf.tmpl`, ejecuta `nginx -t`, reemplaza atómicamente el archivo y recarga Nginx solo cuando cambian los destinos. No usa el socket de Docker.

Sin destinos saludables, la ruta devuelve 503. Ante un fallo de Consul mantiene brevemente la última configuración válida; después de 10 segundos sin consulta completa exitosa la vacía. A ese plazo se añade el tiempo de las consultas y del siguiente ciclo de sincronización (2 segundos).
Consul es un único servidor persistente para desarrollo académico, sin alta disponibilidad ni ACL. No se expone públicamente.

Inspección y prueba reproducible:

```bash
docker compose exec -T consul consul catalog services
docker compose exec -T consul wget -qO- 'http://127.0.0.1:8500/v1/health/service/tienda?passing=true'
docker compose exec -T gateway cat /etc/nginx/nginx.conf
docker compose logs --tail 30 gateway
python3 tools/verify_discovery.py
```

El último comando detiene/restaura una instancia, prueba una caída abrupta y su limpieza, crea una tercera instancia temporal, interrumpe/restaura la base de tienda y Consul. Usarlo en desarrollo sin otros usuarios; puede tardar varios minutos por el plazo real de limpieza. No elimina datos. Cada escenario restaura lo detenido en un bloque `finally`.

## Actividad 3 — Protocol Buffers y gRPC

Contratos `proto/penguin/v1/`: Players (jugadores), Store (productos), Cafeteria (pedidos) y mensajes comunes. Código generado versionable en `platform/gen/penguin/v1/`.
Las rutas HTTP conservan nombres y JSON en español; los mensajes Protobuf usan nombres en inglés. El adaptador mantiene IDs, monedas y stock como números JSON, incluso cuando valen cero; las listas vacías son `[]`.

El middleware mantiene una conexión gRPC al gateway. Nginx balancea cada llamada entre los destinos saludables descubiertos. Los metadatos `x-instance-name` se conservan en la cabecera HTTP `X-Instance-Name`.
Las llamadas tienen deadline y el contexto se propaga a SQL. El adaptador traduce InvalidArgument→400, NotFound→404, Unavailable→503 y DeadlineExceeded→504, sin devolver errores SQL privados.
No se habilitan reintentos configurados de escritura en el cliente o Nginx. La idempotencia y la coordinación distribuida de compras siguen pendientes.

La fase 3 comprobó creación de pedidos asociados y su validación entre servicios. La fase 4 protege estas operaciones: Cafetería ahora consulta `Auth.GetSession`, lista únicamente los pedidos de la identidad autenticada y bloquea la creación antigua hasta incorporar compras seguras. Los logs de fase 3 son evidencia histórica anterior a esa restricción.

Versiones fijadas: gRPC-Go 1.84.0, Protobuf Go 1.36.12, generador gRPC 1.6.2 y grpcurl 1.9.4. La autenticación añadió x/crypto 0.58.0 y requiere Go 1.26, usado también por las imágenes.

```bash
bash tools/generate_proto.sh
docker compose build grpcurl
docker compose run --rm -T grpcurl -plaintext -v -import-path /proto -proto penguin/v1/store.proto -d '{}' gateway:9090 penguin.v1.Store/ListProducts
python3 tools/verify_grpc.py
```

El generador instala plugins con versiones fijadas en `.tools/bin`; se verificó con protoc 3.19.6. El contenedor `grpcurl` solo se usa bajo demanda y no publica puertos. Los comandos proporcionan los contratos explícitamente; no requieren reflection del gateway.
`verify_grpc.py` verifica el balanceo del catálogo público y el rechazo de operaciones privadas sin sesión. Las escrituras técnicas probadas durante fase 3 quedaron intencionalmente bloqueadas al introducir autenticación.

Comprobación desde el cliente real y regresiones:

```bash
godot --headless --path . --script res://tools/verify_api.gd
godot --headless --path . --script res://tools/verify_plaza.gd -- --plaza-preview
godot --headless --path . --script res://tools/verify_pixel_ui.gd -- --plaza-preview
```

## Fase 4 — Cuentas y sesiones

Desde la raíz del proyecto, ejecutar `godot --path .` o abrir `project.godot` y pulsar F5. La bienvenida ofrece Entrar, Crear cuenta y Pasear como invitado. Después de autenticarse, el HUD muestra nombre y monedas; Mi cuenta permite cerrar sesión.

Registro: usuario único de 3–20 letras en español, números o `_`, sin distinguir mayúsculas y normalizando acentos Unicode NFC. La contraseña requiere al menos 8 caracteres y admite hasta 72 bytes UTF-8, límite de bcrypt. Se confirma en el cliente y nunca se trunca silenciosamente.
Cada registro crea cuenta, jugador y sesión dentro de una transacción PostgreSQL. El servidor asigna 100 monedas iniciales; el cliente no elige el saldo.

Contraseñas: bcrypt coste 12 mediante `golang.org/x/crypto` 0.58.0. Sesiones: token aleatorio de 32 bytes, caducidad de 12 horas y almacenamiento SHA-256 del token en PostgreSQL. Los hashes no forman parte de los contratos públicos. El token viaja como `Authorization: Bearer ...`, permanece en memoria de Godot y no se guarda en disco. Al volver a abrir el juego se inicia sesión otra vez.
Cerrar sesión revoca el token actual en el servidor; otras sesiones de la cuenta pueden seguir activas. El logout necesita conexión para confirmar la revocación; si falla, la interfaz permite reintentar. La caducidad y los errores 401 limpian la identidad local y ofrecen entrar otra vez o pasear.
Nginx limita las peticiones de registro/login; Go limita a cuatro operaciones bcrypt simultáneas.

Los jugadores anteriores se conservan sin cuentas vinculadas. Registrar un nombre que coincide con un jugador anterior crea otro jugador; no concede acceso a sus monedas. Los pedidos anteriores sin propietario tampoco se asignan automáticamente y no aparecen en listas privadas.

| Ruta | Acceso actual |
|---|---|
| POST `/auth/register`, `/auth/login` | Público, con validación y límite de solicitudes |
| GET `/auth/session` | Sesión válida; devuelve identidad y caducidad |
| POST `/auth/logout` | Revoca el token presentado; repetible |
| GET `/tienda`, `/tienda/{id}` | Catálogo público |
| GET `/jugadores/{id}` | Solo el propio jugador autenticado |
| GET `/jugadores` | Listado general bloqueado |
| GET `/cafeteria`, `/cafeteria/{id}` | Solo pedidos del jugador autenticado |
| Escrituras antiguas de monedas, stock, jugadores y catálogo | Bloqueadas |
| POST `/cafeteria` | Requiere sesión y queda pendiente de compras seguras |

La autorización también está en los servicios gRPC. Elegir un ID, cambiar JSON o llamar directamente con grpcurl no permite adquirir otra identidad ni establecer monedas/stock.
Los comercios mantienen su interfaz y catálogo, con botones de compra deshabilitados y explicación visible. El modo invitado conserva movimiento, navegación y colisiones, sin acceso a operaciones privadas.

```bash
docker compose build grpcurl
python3 tools/verify_auth.py
python3 tools/run_auth_ui.py --render-auth
python3 tools/verify_grpc.py
bash tools/verify_infra.sh
```

Estas pruebas deben ejecutarse en desarrollo sin otros usuarios. `verify_auth.py` crea cuentas y pedidos exclusivos de prueba, comprueba concurrencia/caducidad/permisos y limpia únicamente sus fixtures. `run_auth_ui.py` crea una cuenta temporal desde Godot, guarda capturas y prueba caída/recuperación del servicio. No imprime tokens ni contraseñas.
Las capturas reales están en `docs/fase4/ui/`, y los resultados en `docs/fase4/`.

## Persistencia y migración

Volúmenes: `jugadores-data`, `tienda-data`, `cafeteria-data` y `consul-data`.
`docker compose down` los conserva. No usar `down -v` si se quieren mantener datos.
Los scripts `schema.sql` inicializan bases vacías. Jugadores aplica `backend/jugadores/migrations/001_accounts.sql` para añadir cuentas y sesiones sin modificar registros anteriores. Cafetería además aplica al arrancar la migración idempotente `backend/cafeteria/migrations/001_order_player.sql`, que añade `jugador_id` nullable sin asignar jugadores a pedidos anteriores. Los volúmenes anónimos anteriores no se adoptan automáticamente.
Antes de sustituir una instalación anterior, respaldar cada base desde esa instalación:

```bash
docker compose exec -T db-jugadores sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > jugadores-backup.sql
docker compose exec -T db-tienda sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > tienda-backup.sql
docker compose exec -T db-cafeteria sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > cafeteria-backup.sql
```

Guardar los respaldos fuera del repositorio y probar la restauración antes de reemplazar la instalación. Cambiar `.env` no modifica contraseñas de bases ya inicializadas.

## Desarrollo y archivos principales

- `docker-compose.yml`, `.env.example`, `setup.sh`: despliegue local.
- `platform/registry`: registro, recuperación y baja compartidos por los tres servicios.
- `platform/cmd/gateway`: sincronizador y supervisor de Nginx.
- `nginx/nginx.conf.tmpl`, `nginx/Dockerfile`: plantilla e imagen del gateway.
- `backend/*`: controladores, modelos y salud de PostgreSQL.
- `frontend`: exportación Web de Godot servida por Nginx, sin administración pública.
- `tools/verify_infra.sh`, `tools/verify_discovery.py`: comprobaciones HTTP y de descubrimiento.

```bash
cd platform
go test ./...
go vet ./...
```

Repetir compilación y análisis en `backend/jugadores`, `backend/tienda`, `backend/cafeteria` y `middleware` cuando cambien. La plataforma compartida incorpora gRPC-Go y Protobuf; los módulos de backend la importan mediante `replace` local y se construyen desde la raíz del repositorio.

## Próxima actividad y commits

Siguiente fase: compras seguras con intención de compra, precios del servidor, control de concurrencia, idempotencia y coordinación entre bases. Chat y presencia se adelantaron por petición del usuario.
No se realizaron commits automáticos. Grupos de revisión: retirada de NPC; actividad 1; actividad 2 y retirada del panel web heredado; actividad 3 y adaptación HTTP/gRPC; fase 4 de autenticación e interfaz. No hay hashes nuevos que atribuir a las actividades.


## Chat y presencia

Abrir http://localhost:3000 en dos ventanas con cuentas distintas. Pulsar Chat de la plaza o Enter para conversar; ESC pliega el panel. Los jugadores conectados aparecen con su nombre y sus movimientos se comparten. Invitados pueden explorar, pero no envían mensajes ni aparecen en la sala. Una cuenta abierta en otra ventana transfiere su conexión.

La sala conserva 50 mensajes en memoria, se recupera mediante snapshot al reconectar y revalida sesiones por gRPC cada cinco segundos. Reiniciar el middleware borra ese historial efímero; PostgreSQL conserva las cuentas. No se soportan varias réplicas del middleware ni colisiones autoritativas en el servidor. Arquitectura, límites, comandos y evidencias: `docs/CHAT_Y_PRESENCIA.md`.
