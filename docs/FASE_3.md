# Actividad 3 — Protocol Buffers y gRPC

## Implementación

Se añadieron cuatro contratos versionados en `proto/penguin/v1/`: mensajes comunes, jugadores, tienda y cafetería. Sus clientes y servidores Go se generan en `platform/gen/penguin/v1/`.
Las operaciones existentes ahora se atienden mediante gRPC: listar/crear/consultar jugadores y productos, actualizar monedas/stock y listar/crear/consultar pedidos.

El middleware conserva las rutas y JSON HTTP de Godot y los convierte en llamadas gRPC. Nginx recibe esas llamadas por el puerto interno 9090 y balancea entre los destinos saludables obtenidos de Consul. El puerto gRPC no está publicado en el host.
Consul registra las instancias como `grpc` en 9090 y comprueba el protocolo estándar `grpc.health.v1.Health/Check`, que consulta PostgreSQL. HTTP 8080 se conserva únicamente para salud de Compose.

Cafetería consulta a Jugadores mediante gRPC a través de Nginx antes de crear pedidos asociados. Se añadió una columna nullable `jugador_id` mediante migración idempotente de arranque, sin asignar identidad a pedidos anteriores.
Godot envía el jugador seleccionado en las llamadas de cafetería; no se añadieron cuentas ni autenticación en esta fase.

Los contextos de las llamadas llegan hasta las consultas SQL. Hay validación de entradas, errores gRPC explícitos, traducción HTTP y metadatos de instancia. El adaptador conserva números JSON y campos con cero, y devuelve arrays vacíos en lugar de null.
Los controladores HTTP internos anteriores se sustituyeron por handlers gRPC. La traducción HTTP queda centralizada en `middleware/api`.

## Dependencias y regeneración

- Go mínimo 1.25; imágenes Go 1.26.
- gRPC-Go v1.84.0 y Protobuf Go v1.36.12.
- protoc-gen-go v1.36.12 y protoc-gen-go-grpc v1.6.2.
- grpcurl v1.9.4, en contenedor de herramientas bajo demanda.
- Generación verificada con protoc 3.19.6.

```bash
bash tools/generate_proto.sh
docker compose up --build -d --wait
docker compose build grpcurl
```

Los plugins quedan en `.tools/bin`, excluido de Git. El código generado se conserva en el repositorio y no se edita manualmente. Las librerías se fijan mediante go.mod/go.sum.

## Comandos grpcurl reproducibles

```bash
docker compose run --rm -T grpcurl -plaintext -v -import-path /proto -proto penguin/v1/store.proto -d '{}' gateway:9090 penguin.v1.Store/ListProducts
docker compose run --rm -T grpcurl -plaintext -import-path /proto -proto penguin/v1/players.proto -d '{}' gateway:9090 penguin.v1.Players/ListPlayers
docker compose run --rm -T grpcurl -plaintext -import-path /proto -proto penguin/v1/cafeteria.proto -d '{}' gateway:9090 penguin.v1.Cafeteria/ListOrders
python3 tools/verify_grpc.py
```

Los contratos explícitos evitan depender de reflection en un gateway con varios servicios. El JSON mostrado por grpcurl sigue las reglas Protobuf (int64 como cadenas); el adaptador HTTP convierte esos campos al contrato numérico que ya usa Godot.

## Evidencia realmente ejecutada

`go test ./...` y `go vet ./...` pasaron en platform, jugadores, tienda, cafetería y middleware.
Hay pruebas nuevas para la conversión de errores, JSON, metadata, arrays vacíos y validación de jugadores antes de escribir pedidos. La prueba del adaptador utiliza una conexión gRPC real en memoria con bufconn; las pruebas de integración utilizan PostgreSQL y contenedores reales.

`docs/fase3/grpc-validation.log` contiene la salida íntegra de las pruebas con grpcurl, incluyendo una respuesta verbose de Nginx con `x-instance-name` y el contenido real de productos.
Resultados obtenidos:

```text
PASS grpcurl balancea llamadas Store/ListProducts entre dos instancias
PASS grpcurl consulta los tres servicios a través de Nginx
PASS altas, consultas y actualizaciones gRPC de registros de prueba
PASS Cafetería valida Jugadores por gRPC y guarda el pedido asociado
PASS contrato HTTP legado conserva JSON numérico y pedidos sin asociación
PASS errores gRPC NotFound/InvalidArgument sin insertar pedido inválido
PASS fallo entre servicios devuelve Unavailable y no inserta pedido
PASS migración idempotente conserva pedido asociado tras reinicio
PASS pedido sin asociación conservado tras reinicio
PASS limpieza exclusiva de fixtures gRPC/HTTP
GRPC_VALIDATION failures=0
```

`docs/fase3/interservice.log` conserva trazas reales de `Cafeteria/CreateOrder`, `Players/GetPlayer` y la validación del jugador. No se sustituyó ninguna implementación de producción por mocks.
Los registros de prueba se eliminaron por sus IDs exclusivos; las bases y sus volúmenes se conservaron.

Godot 4.7.2 importó los cambios sin errores. Pruebas ejecutadas en headless:

```text
API_VALIDATION failures=0
PLAZA_VALIDATION failures=0
PIXEL_UI_VALIDATION failures=0
```

Logs: `godot-api.log`, `godot-plaza.log` y `godot-ui.log` dentro de `docs/fase3/`.
La prueba API llama desde el autoload real de Godot al adaptador y obtiene listas de jugadores, productos y pedidos. Las otras verifican movimiento, colisiones, ausencia de NPC e interfaz lógica 960×600. No constituyen una nueva revisión visual en varios tamaños de ventana.

La regresión completa de descubrimiento se repitió sobre gRPC y terminó con `DISCOVERY_VALIDATION failures=0`. Su salida está en `docs/fase3/discovery-validation.log`: baja normal y abrupta, limpieza de Consul, tercera instancia sin cambios de configuración y recuperación de PostgreSQL y Consul.
Los logs de construcción reales se conservan en `build.log`, `gateway-build.log` y `grpcurl-build.log`.

## Archivos importantes

- `proto/penguin/v1/`, `platform/gen/penguin/v1/`: contratos y generación.
- `backend/*/rpc/`: operaciones gRPC y dependencias explícitas.
- `backend/*/models/`: SQL con contextos.
- `backend/cafeteria/migrations/`, `migration.go`: ampliación del esquema conservando datos.
- `middleware/api/`: adaptación HTTP/JSON y errores.
- `platform/registry/`, `platform/rpcutil/`: ciclo de vida, salud y metadata.
- `nginx/nginx.conf.tmpl`: balanceo gRPC y entrada HTTP separada.
- `tools/verify_grpc.py`, `verify_api.gd`, `generate_proto.sh`: pruebas y herramientas.

## Límites y próxima fase

La identidad todavía procede del selector legado. Comprobar que existe un jugador no autentica al usuario. La fase 4 derivará la identidad de una sesión y protegerá las operaciones.
Las compras siguen calculándose parcialmente en el cliente y no tienen coordinación distribuida ni idempotencia. No se declara resuelta esa funcionalidad.
Se conservan precios decimales para compatibilidad; la unificación de precios en monedas corresponde al trabajo de compras.
El transporte interno es gRPC sobre HTTP/2 sin TLS en la red local. WebSocket y chat siguen pendientes. Godot 4.6 no se verificó.
No se habilitaron reintentos configurados de escritura; la siguiente fase de compras deberá resolver reintentos e idempotencia de manera explícita.
No se realizaron commits ni se publicaron cambios. La actividad 3 queda identificada por sus contratos, handlers, adaptador y herramientas, lista para revisión y un commit posterior solicitado.

## Referencias oficiales

- gRPC Go: https://grpc.io/docs/languages/go/basics/
- Generación: https://grpc.io/docs/languages/go/generated-code/
- Proxy gRPC Nginx: https://nginx.org/en/docs/http/ngx_http_grpc_module.html
