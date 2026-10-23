# Chat y presencia de la plaza

Por petición del usuario se adelantó el chat y la presencia respecto de las compras seguras. Se mantiene el catálogo en consulta. No hay NPC activos: los pingüinos remotos corresponden exclusivamente a sesiones conectadas a la sala.

## Uso

Abrir http://localhost:3000 en dos ventanas y entrar con **cuentas diferentes**. Cada jugador ve el pingüino y el nombre de los demás; sus desplazamientos se comparten. Pulsar **Chat de la plaza** o **Enter** para escribir y Enter/Enviar para enviar. **ESC** pliega el panel; hacer clic fuera del chat permite seguir caminando. Los mensajes recibidos con el panel cerrado muestran un contador.

Los invitados pueden explorar sin red, pero no son miembros de la sala ni pueden conversar. Un mismo jugador tiene una sola conexión activa: abrir la cuenta en otra ventana transfiere la conexión y muestra un aviso en la anterior. **Reconectar** permite recuperarla manualmente, sin un bucle de ventanas expulsándose entre sí.

## Arquitectura

```text
Godot nativo o Web
  └─ WebSocket /plaza → Nginx → middleware/plaza (una sala global)
                                   └─ Auth.GetSession gRPC → Nginx :9090 → jugadores → PostgreSQL
```

Se reutiliza el middleware como adaptador de aplicación y coordinador de la sala. Nginx mantiene proxy y balanceo de las llamadas gRPC existentes y realiza el upgrade WebSocket. La única dependencia nueva de ejecución es `github.com/gorilla/websocket` 1.5.3, para implementar el protocolo y los controles de conexión sin desarrollar manualmente sus tramas.

**Existe una sola instancia del middleware/sala.** Varios clientes y ambas instancias del servicio de tienda funcionan con esa sala común. No se soporta escalar el middleware a varias réplicas: su memoria no se comparte y haría falta un coordinador común antes de hacerlo. Este cambio no afirma sincronización entre varios servidores de chat.

El registro/descubrimiento Consul y el balanceo gRPC de los servicios de negocio se conservan. No se añade una demostración gRPC aislada: la identidad de la conexión se consulta a través del balanceador real.

## Identidad y seguridad

El cliente abre `/plaza` y envía como primera trama `{ "type": "auth", "token": "..." }`. El token permanece en memoria, no aparece en URLs ni registros. Se debe autenticar en cinco segundos. El servidor obtiene ID y nombre desde Auth.GetSession, nunca desde campos libres del mensaje. El origen del navegador debe coincidir con el host público; Nginx conserva el host y el puerto. El cliente nativo puede omitir Origin.

Cada cinco segundos el servidor revalida la sesión por gRPC con timeout de tres segundos. La revocación/caducidad cierra la conexión con código 4001; Godot limpia la sesión. Un fallo de validación por indisponibilidad cierra con 1013 y permite reintentar sin fingir un logout. La transferencia a otra ventana utiliza 4009 y suspende sus reintentos automáticos.

Límites: 128 jugadores, 160 conexiones incluyendo autenticaciones, tramas de 2048 bytes, 30 solicitudes por segundo por conexión. Chat de 1 a 180 caracteres, sin controles ni saltos internos, ráfaga de tres mensajes y recuperación de un mensaje por segundo. Los campos desconocidos se rechazan. Los textos se muestran como `Label`, sin interpretar HTML/BBCode. Las colas de salida están acotadas; una conexión lenta se desconecta en lugar de bloquear al resto. Ping cada 20 segundos, lectura máxima de 60 segundos sin pong y escritura con timeout de tres segundos.

## Mensajes y reconexión

Una sección crítica común asigna secuencia creciente y encola las mismas tramas en el mismo orden para todos los miembros. El servidor confirma al emisor por el mismo canal: el cliente no inserta mensajes locales optimistas. No se reenvían automáticamente mensajes al reconectar, para evitar duplicados o publicaciones inesperadas.

El historial contiene los últimos 50 mensajes en memoria; un `welcome` devuelve historial y snapshot de jugadores. Godot reconstruye ambos, filtra secuencias repetidas y vuelve a suscribirse sin duplicar señales. Los reintentos esperan 1, 2, 4, 8 y como máximo 15 segundos. Un identificador de época distinto permite reconocer un reinicio del servidor en las pruebas.

No se necesita persistir conversaciones para un chat global efímero; por eso no se añadió una tabla. Reiniciar el middleware borra el historial y reinicia las posiciones de la sala, aunque las cuentas y las sesiones continúan en PostgreSQL. Los clientes reconstruyen su presencia y vuelven al punto de entrada cuando la sala ya no conserva su miembro anterior; esto también puede ocurrir tras perder una conexión, sin reiniciar el servidor. No se garantiza entrega de mensajes enviados durante una desconexión.

## Movimiento y límites de alcance

El jugador local conserva A*, colisiones y animación. Publica cambios aproximadamente cada 120 ms. El servidor comprueba coordenadas finitas dentro del contorno de la plaza y desplazamiento compatible con una velocidad máxima más tolerancia; limita la frecuencia y devuelve correcciones ante posiciones inválidas. El cliente remoto interpola hacia posiciones confirmadas y reutiliza el sprite, escala, sombra y tipografía existentes. No tiene IA, colisiones físicas ni realiza compras.

Es una primera sincronización de movimiento para presencia social. **El servidor no simula el mapa ni las colisiones con cada edificio**: los obstáculos siguen comprobándose en el cliente local. No es un motor multijugador autoritativo completo y la posición no habilita operaciones económicas.

## Archivos

- `middleware/plaza/hub.go`: miembros, historial, orden, límites y posiciones.
- `middleware/plaza/socket.go`: autenticación gRPC, conexiones, ping, timeouts y revalidación.
- `middleware/main.go`, `middleware/go.mod`, `middleware/go.sum`: integración y dependencia fijada.
- `nginx/nginx.conf.tmpl`: ruta WebSocket y host público.
- `scripts/plaza/PlazaConnection.gd`: estado de red, reconexión, snapshots y envío.
- `scripts/plaza/RemotePenguin.gd`, `scripts/plaza/Plaza.gd`: personajes remotos reales.
- `scripts/ui/ChatPanel.gd`: panel plegable, historial, foco y estado de conexión.
- `scripts/plaza/PlazaPlayer.gd`: libera el campo de texto al volver a hacer clic en el mundo.

El panel usa el tema y los botones pixel art existentes, contenedores, scroll y fuente autorizada. Se mantiene 960 × 600 y escalado entero; no hay recursos gráficos nuevos. `docs/.gdignore` evita importar las capturas de documentación dentro del juego.

## Ejecutar y actualizar

```bash
bash setup.sh
```

Para actualizar una instalación ya iniciada:

```bash
bash tools/export_web.sh
docker compose up --build --no-deps -d --wait middleware frontend gateway
docker compose exec -T gateway nginx -s reload
```

El juego nativo usa `ws://localhost:8000/plaza`. La Web utiliza su mismo origen y cambia a `wss://` si se sirve mediante HTTPS. El servicio actual es local; no se publicó externamente.

## Pruebas reproducibles

Ejecutarlas en desarrollo: la prueba de navegador reinicia brevemente el middleware para verificar la recuperación. Crea y elimina únicamente sus cuentas de prueba; no imprime tokens ni contraseñas.

```bash
go -C middleware test -race ./...
go -C middleware vet ./...
npm install --prefix .tools/web-test playwright
.tools/web-test/node_modules/.bin/playwright install chromium
node tools/verify_social.cjs
python3 tools/verify_social_native.py
godot --headless --path . --script res://tools/verify_chat_ui.gd
godot --headless --path . --script res://tools/verify_plaza.gd -- --plaza-preview
bash tools/verify_infra.sh
```

El navegador usa dos contextos independientes con el juego Web real y renderizado por software; la prueba de escritorio ejecuta Godot contra los servicios reales. El verificador visual usa datos locales únicamente dentro de la prueba para comprobar tipografía, geometría y foco, sin sustituir ninguna funcionalidad de producción. Para caracteres fuera del teclado estadounidense, el navegador de pruebas envía eventos keyDown/keyUp explícitos, porque `keyboard.type()` utiliza inserción de texto sin esas teclas para acentos en un canvas.

Las pruebas unitarias cubren historial limitado, concurrencia/orden, saturación de envío, reemplazo de conexión, origen externo, campos de suplantación, token inválido y movimiento fuera de límites.

No se realizaron commits automáticos. Las compras seguras siguen siendo la siguiente funcionalidad pendiente.


## Resultados realmente ejecutados

- `docs/social/browser-validation.log`: `SOCIAL_VALIDATION failures=0`. Dos juegos Web independientes; presencia bidireccional; movimiento recibido; mensajes en español con el mismo orden e identidad; escritura sin movimiento; reconexión de ambos tras reiniciar middleware; revocación elimina la presencia; token falso, nombre falsificado, longitud excesiva y teletransporte rechazados; otra ventana no provoca reconexión infinita. Cuentas de prueba eliminadas.
- `docs/social/native-validation.log`: `SOCIAL_NATIVE_VALIDATION failures=0`. Godot 4.7.2 nativo conectado a servicios reales; autenticación, snapshot, chat español, confirmación de posición A* y cierre por revocación. Cuenta temporal eliminada.
- `docs/social/chat-ui-validation.log`: `CHAT_UI_VALIDATION failures=0`. Protección de invitados, geometría del panel, foco, tecla E, ESC, texto español y ausencia de señales duplicadas después de 20 aperturas/cierres.
- `docs/social/go-validation.log`: `go test -race ./...` correcto en middleware, API y plaza. `go vet ./...` sin errores.
- `docs/social/plaza-validation.log`: `PLAZA_VALIDATION failures=0`.
- `docs/social/pixel-ui-validation.log`: `PIXEL_UI_VALIDATION failures=0`.
- `docs/social/infra-validation.log`: frontend, permisos HTTP y balanceo de ambas tiendas correctos.
- Capturas reales inspeccionadas: `two-players.png`, `chat-a.png`, `chat-b.png` y `chat-scale2.png`, a 960 × 600 y 1920 × 1200. El historial previo a reiniciar también contiene saludos de ejecuciones anteriores de las pruebas, porque permanecía en memoria.

Pruebas realizadas en Chromium 156 con WebGL por software y Godot 4.7.2; no se verificó Firefox, teléfonos ni Godot 4.6. Las 11 instancias normales de Compose terminaron saludables. Los archivos de configuración de Nginx pasaron `nginx -t`; `git diff --check` y comprobaciones de sintaxis de verificadores no detectaron errores.
