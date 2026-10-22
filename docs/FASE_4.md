# Fase 4 — Registro, login y sesiones

## Resultado

El juego permite crear cuenta, entrar con contraseña, pasear como invitado, consultar la propia identidad y cerrar sesión. El selector libre de jugadores fue sustituido por bienvenida, registro, login y panel de cuenta con el tema pixel art existente.

El backend crea cada cuenta junto con su jugador y sesión en una transacción local. El saldo inicial de 100 monedas lo asigna el servidor. Los usuarios anteriores y sus monedas se conservan sin asignarles cuentas automáticamente.

## Seguridad y arquitectura

Auth se incorpora al servicio de Jugadores, sin un nuevo microservicio. Expone Register, Login, GetSession y Logout mediante gRPC, detrás de Nginx y el adaptador HTTP existente.
Contraseñas bcrypt coste 12 con x/crypto 0.58.0. Usuarios de 3–20 letras españolas, números o guion bajo, normalizados a NFC y únicos sin distinguir mayúsculas. Contraseñas de al menos 8 caracteres y máximo 72 bytes UTF-8, comprobadas sin truncamiento.
Tokens opacos aleatorios de 32 bytes, codificados base64url, con duración de 12 horas. PostgreSQL guarda solo su SHA-256; las respuestas públicas nunca incluyen hashes. Godot guarda el token únicamente en memoria y lo envía en Authorization, sin parámetros de URL.

Cada consulta privada valida la sesión en el servidor. GetPlayer permite únicamente el ID propio; Cafetería obtiene la identidad mediante Auth.GetSession y filtra pedidos por ella. Un pedido ajeno o sin propietario no se muestra al usuario.
Cerrar sesión elimina el token presentado. La operación se puede repetir. Caducar una sesión no invalida automáticamente las otras sesiones válidas de la cuenta.
Los errores de login no distinguen usuario inexistente de contraseña incorrecta; el backend usa comparación bcrypt también para usuarios válidamente formados que no existen.
Nginx limita registro/login a 5 solicitudes por segundo con ráfaga 10 por dirección; Go limita a cuatro operaciones bcrypt simultáneas.

Las escrituras antiguas de monedas, stock, creación libre de jugadores y productos están denegadas por gRPC. La creación antigua de pedidos queda bloqueada mientras se implementan compras seguras. Los comercios están en modo consulta; no se simulan compras exitosas.
El Compose sigue siendo local, con HTTP en la entrada y gRPC interno sin TLS. No se ha desplegado públicamente.

## Datos y migraciones

`backend/jugadores/migrations/001_accounts.sql` añade accounts y sessions de manera idempotente. accounts.player_id referencia un jugador nuevo por cuenta y es único; sessions referencia accounts con borrado en cascada y tiene índice por caducidad.
La migración no crea cuentas para Pingu, Nieve u otros registros anteriores. Tampoco modifica sus contraseñas, saldos o IDs: esos registros no tenían credenciales.
Los pedidos anteriores sin propietario se conservan sin asignación arbitraria. Registrar un nombre coincidente con un jugador anterior no concede acceso a ese registro.

## Interfaz

Se reutilizan PixelUI, PixelButton, PixelStyleBox, Pixelify Sans, la resolución 960×600 y el escalado entero. El tema añade campos LineEdit, botones secundarios y errores legibles; no se añadieron fuentes ni imágenes externas.

El formulario oculta contraseñas con `*`, valida confirmación, muestra carga y deshabilita controles durante el envío. Impide varias solicitudes simultáneas y descarta respuestas de ventanas anteriores. Los errores conservan la posibilidad de reintentar o volver al paseo invitado.
Los inputs consumen escritura y el mapa pausa las interacciones mientras la cuenta está abierta. E en un campo no abre comercios ni mueve al personaje. Logout y caducidad cierran paneles privados y actualizan el HUD.
Las sesiones sobreviven cambios de escena mientras el proceso sigue abierto; al cerrar el juego se pierde el token local y hay que iniciar sesión de nuevo. El logout conserva la sesión local si no puede confirmar revocación, mostrando un error de conexión para reintentar.

## Archivos principales

- `proto/penguin/v1/auth.proto`, `platform/gen/penguin/v1/`: contrato y generación.
- `backend/jugadores/auth/`: hashing, sesiones, transacciones y tests.
- `backend/jugadores/migrations/`, `migration.go`: tablas nuevas conservando jugadores.
- `platform/session/`: lectura de Bearer y validación entre servicios.
- `backend/*/rpc/`: permisos reales y restricciones de escrituras antiguas.
- `middleware/api/auth.go`, `api.go`: HTTP, metadatos y errores claros.
- `scripts/ui/AuthPanel.gd`, `scripts/EstadoJuego.gd`, `scripts/Api.gd`: presentación, estado y comunicación.
- `scripts/Mapa.gd`, `scripts/plaza/Plaza.gd`, scripts del personaje y comercios: entrada, HUD e interacción.
- `assets/ui/pixel_theme.tres`: estilos reutilizables.

## Ejecución

```bash
bash setup.sh
godot --path .
```

También se puede abrir project.godot y pulsar F5. Crear cuenta desde la bienvenida; el registro inicia sesión y entra en la plaza. Mi cuenta abre el panel con Cerrar sesión.
La portada de localhost:3000 solo indica cómo abrir el juego; no sustituye las pantallas Godot.

## Pruebas reales

```bash
docker compose build grpcurl
python3 tools/verify_auth.py
python3 tools/run_auth_ui.py --render-auth
python3 tools/verify_grpc.py
bash tools/verify_infra.sh
```

Ejecutar en desarrollo sin otros usuarios conectados. Los verificadores restauran los servicios que detienen y limpian solo cuentas, sesiones y pedidos exclusivos de prueba. No imprimen contraseñas, tokens ni hashes reales.

`go test ./...` y `go vet ./...` pasaron en platform, jugadores, tienda, cafetería y middleware. Se probaron el ciclo de sesiones, errores de credenciales, hashing, normalización y permisos de pedidos.

Backend real: `docs/fase4/auth-validation.log` terminó con `AUTH_VALIDATION failures=0`. Incluye:

- Registro, duplicado y validaciones; saldo inicial impuesto por servidor.
- Hash bcrypt coste 12 y almacenamiento SHA-256 del token, comprobados sin imprimirlos.
- Login válido e inválido, consulta privada y rechazo de tokens inventados.
- Datos ajenos bloqueados y pedidos filtrados por sesión, incluyendo rechazo de pedidos ajenos y sin dueño.
- Escrituras antiguas bloqueadas incluso con sesión válida.
- Dos registros concurrentes con el mismo nombre: una cuenta y un jugador, sin huérfanos.
- Sesión conservada tras reiniciar Jugadores y volver a aplicar la migración.
- Caducidad provocada en PostgreSQL solo para la sesión de prueba; otra sesión permanece válida.
- Logout, repetición y rechazo posterior del token.
- Acceso gRPC directo sin sesión rechazado.
- Jugadores anteriores conservados sin asignación de cuentas.

Godot real: `docs/fase4/ui-validation.log`, `godot-auth.log` y `godot-offline.log`. Se ejecutó con renderizador Compatibility en Intel Arc y Godot 4.7.2.
El registro y login de la prueba realizan llamadas HTTP reales a los servicios; no hay autenticación simulada. Se verificaron confirmación, contraseña corta/larga, usuario duplicado, credenciales inválidas, estado de carga, HUD, logout, caducidad y entrada invitada con Jugadores detenido.

Resultados obtenidos: `AUTH_UI_VALIDATION failures=0` y `AUTH_UI_OFFLINE failures=0`.
El log recoge tamaños reales 1280×720 con escala 1 y 1920×1200 con escala 2, conservando la distribución lógica 960×600. Las capturas reales se guardan en `docs/fase4/ui/` y se revisaron visualmente.
Las cuentas temporales y sus sesiones se eliminaron al terminar; las capturas muestran identidades exclusivas de prueba.

Las regresiones finales quedaron en `plaza-validation.log`, `pixel-ui-validation.log`, `api-validation.log`, `infra-validation.log` y `grpc-validation.log`. Resultados: `PLAZA_VALIDATION failures=0`, `PIXEL_UI_VALIDATION failures=0`, `API_VALIDATION failures=0` y `GRPC_VALIDATION failures=0`; el smoke test conservó rutas y balanceo y comprobó 401 en recursos privados.

Los verificadores de gRPC, API y smoke test se actualizaron a los permisos actuales. La evidencia de escrituras técnicas de fase 3 queda como historial; esas operaciones ya no están permitidas desde clientes.

## Pendiente

Fase 5: intención de compra, validación de precios/saldo/stock en servidor, idempotencia y coordinación distribuida. Después se reactivarán los botones de compra.
Fase 6: chat autenticado. No hay presencia ni movimiento multijugador sincronizados.
Compatibilidad ejecutada con Godot 4.7.2; Godot 4.6 continúa sin verificación directa.
No se realizaron commits ni publicaciones.

## Referencias

- bcrypt Go: https://pkg.go.dev/golang.org/x/crypto/bcrypt
- Gestión de sesiones: https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
