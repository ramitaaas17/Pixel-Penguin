# Café del Deshielo

Acercarse a la cafetería de la plaza y pulsar E. El juego ocupa casi todo el lienzo de 960 × 600: pedido y marcadores a la izquierda, zona de caída de 448 px de alto a la derecha. La plaza mantiene su resolución y sus recursos originales.

## Reglas

Un turno dura 60 segundos. Hacer clic en los ingredientes mientras caen y completar las cantidades de la receta en cualquier orden. La primera bebida requiere tres granos de café y dos porciones de leche. Cada contador se pone verde al completarlo; la bebida se sirve automáticamente y aparece otro pedido después de 0,9 segundos.

Hay cuatro niveles de 15 segundos. Las velocidades son 42, 56, 70 y 86 píxeles por segundo; también aceleran los ingredientes que ya estaban cayendo. La separación entre apariciones evita que los objetos de un mismo carril se alcancen al acelerar. Los pedidos tienen 24 segundos de paciencia.

- Material necesario que cruza el borde sin recogerse: −20 puntos y se rompe la racha.
- Los distractores que se dejan caer no penalizan. Tampoco se penaliza material cuya cantidad ya se completó.
- Recoger un tipo ajeno a la receta: −10 puntos y se rompe la racha.
- El puntaje nunca baja de cero.
- Completar una bebida suma 100 puntos, 25 por cada nivel adicional, hasta 125 por racha y 2 por cada segundo completo de paciencia restante.

Al terminar con una cuenta, se otorga una moneda por cada 100 puntos, con un máximo de 50 monedas por partida. Ejemplo: 2945 puntos dan 29 monedas. Los invitados juegan en modo práctica y no reciben monedas. Salir antes de terminar no paga la partida.

El botón Música permite silenciar y restaurar una melodía chiptune original. La preferencia se conserva localmente. La música comienza con la partida y se detiene al cerrar. Salir o ESC devuelve a la plaza y restaura el movimiento y la barra de chat.

## Lectura y arte

PixelDigits.gd dibuja números, signos y la barra de las cantidades en una cuadrícula original de 5 × 7, ampliada por un factor entero de 5: los dígitos tienen 35 píxeles de alto. No depende del rasterizado de una fuente y no introduce fuentes externas. Los títulos y textos conservan Pixelify Sans con alto contraste.

CoffeeArt.gd conserva la estación pixel art original. CoffeeRain.gd dibuja objetivos de 72 × 72 píxeles y deriva sus posiciones del tiempo de partida. El área visible es de al menos 670 × 448 píxeles. Los sprites se amplían por múltiplos enteros y los movimientos se ajustan a píxeles.

assets/audio/coffee_loop.wav es una composición original de 32 pulsos a 104 BPM, sin muestras ni música de terceros. tools/make_coffee_music.py permite regenerarla. CoffeeMusic.gd configura su repetición, volumen suave y silencio persistente.

## Recompensas y servicios

El middleware expone POST /minijuegos/cafe para iniciar y POST /minijuegos/cafe/{run_id}/finalizar para finalizar. Ambas operaciones requieren sesión. El middleware llama por gRPC a StartCoffeeGame y FinishCoffeeGame del servicio de jugadores. Sus contratos están en proto/penguin/v1/players.proto.

Jugadores guarda un plan emitido por el servidor, con ID aleatorio, recetas y apariciones/caducidades de los ingredientes. El cliente registra identificador y tiempo de cada clic, no un puntaje ni una cantidad de monedas. Al finalizar, el servidor reproduce las reglas, las pérdidas, los niveles y los puntos. Rechaza clics inventados, repetidos, fuera de tiempo o durante la entrega, y no paga antes de que hayan transcurrido 60 segundos reales. Una partida sin cobrar expira a los diez minutos y solo puede existir una activa por jugador.

El saldo y el resultado se actualizan en una sola transacción de PostgreSQL bajo bloqueo de la fila del jugador. coffee_runs almacena el resultado y el estado claimed. Reintentar devuelve el resultado guardado y el saldo actual, sin otro abono. Empezar otra partida abandona una anterior no cobrada. Las cuentas y los saldos existentes se conservan mediante la migración 002_coffee_runs.sql.

La actualización de monedas usa el mecanismo outbox/Kafka ya existente de jugadores; no se mueve dinero desde el cliente ni desde el consumidor del chat. Se eligió jugadores para guardar partida y saldo en una misma transacción. Los pedidos comerciales de cafetería y las compras de tienda conservan sus restricciones anteriores.

Si falla la respuesta de cobro, la interfaz permite reintentar. La partida pendiente queda en memoria durante esa sesión y se recupera al volver a abrir el minijuego. Recargar el navegador pierde ese registro local; un premio ya abonado permanece en la cuenta. El registro de clics validado no demuestra que haya jugado una persona ni detecta automatización.

## Verificación reproducible

Reglas y coincidencia entre Go y Godot:

```bash
COFFEE_FIXTURE_PATH="$PWD/.tools/coffee-fixture.json" go -C platform test ./coffeegame -count=1
go -C platform test -race ./coffeegame
godot --headless --fixed-fps 60 --path . --script res://tools/verify_coffee.gd
godot --headless --path . --script res://tools/verify_pixel_ui.gd -- --plaza-preview
```

El verificador de Godot compara el resultado exacto de un registro de acciones con el motor de Go. También comprueba proximidad, E, clics reales, pérdida de puntos, cuatro velocidades, ventana ampliada, reinicio, música, cierre y modo práctica. --render-coffee en una ejecución gráfica genera capturas.

Cobro real con HTTP → gRPC → PostgreSQL (crea y elimina exclusivamente sus jugadores/cuentas temporales):

```bash
CGO_ENABLED=0 go -C backend/jugadores test -c ./coffee -o /tmp/pixel-penguin-coffee.test
docker compose run --rm --no-deps -e COFFEE_DB_TEST=1 -e COFFEE_HTTP_TEST=1 -v /tmp/pixel-penguin-coffee.test:/tmp/coffee.test:ro --entrypoint /tmp/coffee.test jugadores-service -test.v -test.timeout=120s
```

La prueba HTTP espera el minuto real del turno y verifica un premio persistente y un reintento. La prueba de base de datos comprueba 16 cobros concurrentes, titular de la partida, cobro adelantado, acciones falsas y abandono.

Navegador con Playwright ya instalado en .tools/web-test:

```bash
node tools/verify_coffee_web.cjs
node tools/verify_coffee_web.cjs --rewards
```

La prueba básica recorre la plaza, abre con E, detecta audio real, silencia/restaura la música y recoge ingredientes con clics. --rewards añade una cuenta temporal y una partida real de un minuto, valida el premio y reintenta el cobro. El usuario y el ID de limpieza se guardan sin credenciales en .tools/coffee-ui-test.json. El finally ejecuta tools/cleanup_coffee_ui.py; si se ejecuta dentro de un contenedor sin Docker, usar COFFEE_TEST_SKIP_CLEANUP=1 y ejecutar después ese helper desde el host.

## Actualizar

```bash
bash tools/export_web.sh
docker compose up -d --build --wait
docker compose exec -T gateway nginx -s reload
```

Se actualizan jugadores, middleware, gateway y frontend; no se borran volúmenes. Abrir http://localhost:3000 y recargar con Ctrl + Shift + R. Desde otras computadoras, la exportación actual exige HTTPS.

## Resultados del 30 de octubre de 2026

Reglas con race y go vet correctos. Go y Godot coincidieron en puntaje, pérdidas, niveles y monedas. Verificación de minijuego y UI sin fallos; capturas revisadas en Godot 4.7.2 con renderizado OpenGL por software. La prueba real de API obtuvo 2945 puntos, 29 monedas y saldo 129; el reintento conservó el saldo. Dieciséis cobros concurrentes de otra partida dieron un solo abono. Las cuentas de esas pruebas se eliminaron.

La prueba completa de Chromium con una cuenta obtuvo 1089 puntos, mostró 10 monedas en la pantalla de recompensa y dejó saldo persistente de 110. Repetir el cobro no modificó el saldo. Se detectó audio real con Web Audio y se verificó silencio/restauración mediante el botón. La cuenta temporal de interfaz se eliminó después de comprobar el resultado. Captura revisada: docs/minigames/web-reward.png.
