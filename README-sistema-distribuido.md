# Pixel Penguin

Es un juego en Godot con una plaza nevada y tres servicios en Go
Jugadores guarda los jugadores y las cuentas, tienda tiene los productos y cafetería guarda los pedidos
Cada servicio tiene su propia base de datos

## Avances de la entrega

- Actividad 1 usamos Nginx para recibir las peticiones y repartirlas entre los servicios
- Actividad 2 agregamos Consul para encontrar los servicios que están disponibles
- Actividad 3 conectamos los servicios con gRPC
- Fase 4 agregamos registro, inicio de sesión y cierre de sesión
- También tenemos chat y movimiento compartido en la plaza
- En esta entrega agregamos mensajes en segundo plano con Apache Kafka
- El chat en vivo también publica y consume mensajes mediante Kafka
- Minijuego Café del Deshielo: acercarse a la cafetería y pulsar E para recoger ingredientes con clics, completar bebidas, avanzar por cuatro niveles y ganar monedas según los puntos. Tiene música y números pixelados de mayor tamaño. [Instrucciones y pruebas](docs/MINIJUEGO_CAFETERIA.md)

## Cómo iniciarlo

Se necesita Docker con Compose y Godot 4.7.2 con las plantillas para web

```bash
cp .env.example .env
# Cambiar las contraseñas de las bases en .env
bash setup.sh
```

Si ya existe `.env` hay que conservarlo
El juego abre en http://localhost:3000 y la API está en http://localhost:8000
Para abrirlo en Godot se usa `project.godot` y F5

## Mensajes con Kafka

Los servicios y el chat tienen su tópico

| Servicio | Tópico | Qué avisa |
| --- | --- | --- |
| Jugadores | pixelpenguin.jugadores | Cambios en jugadores |
| Tienda | pixelpenguin.tienda | Cambios en productos |
| Cafetería | pixelpenguin.cafeteria | Cambios en pedidos |
| Chat | pixelpenguin.chat | Mensajes en vivo de la plaza |

Los tópicos se crean al levantar Docker. Los tres tópicos de cambios tienen tres particiones cada uno; el chat usa una partición para conservar el orden
Los servicios se conectan a Kafka mediante REST Proxy dentro de la red de Docker
No se agregaron paquetes nuevos a Go

Para los cambios de las bases de datos, cuando se crea, cambia o borra un registro se guarda también un mensaje pendiente en `message_outbox`
Otro proceso del servicio lo manda a Kafka y después lo quita de pendientes
Si Kafka falla el mensaje sigue guardado para intentar después

Cada servicio lee su tópico y guarda lo recibido en `message_inbox`
Las dos instancias de tienda comparten el mismo grupo para repartirse los mensajes
Cada mensaje tiene un ID para evitar guardarlo dos veces si se repite
Solo se envía el ID del registro y el tipo de cambio, sin contraseñas ni sesiones
Esto deja un registro de cambios, todavía no realiza compras entre servicios

Las tablas de mensajes se agregan al iniciar, también en bases que ya tenían datos
Kafka guarda sus datos en el volumen `kafka-data`
Esta entrega usa un solo servidor Kafka para pruebas locales

## Chat en vivo con Kafka

El mensaje sigue esta ruta: Godot → WebSocket → middleware → Kafka REST → tópico `pixelpenguin.chat` → consumidor del middleware → WebSocket → globos sobre los pingüinos.
El servidor obtiene el nombre y el ID de la sesión, valida el texto y limita la frecuencia antes de publicar. El globo aparece después de consumir el mensaje desde Kafka. El movimiento no pasa por Kafka.

No hay botón ni panel de historial. Tampoco se envían mensajes anteriores al entrar. Kafka conserva temporalmente los eventos de transporte, con retención configurada de una hora; esto no agrega historial al juego. A diferencia de los cambios de las bases, el chat no usa outbox/inbox ni entrega a jugadores desconectados.

Si Kafka no está disponible, el chat avisa del fallo y el movimiento sigue funcionando. Se descartan mensajes con más de 15 segundos para evitar globos atrasados. No se garantiza entrega durante una caída y un timeout de publicación puede ser ambiguo.

Detalles y pruebas: [Chat con Kafka](docs/CHAT_KAFKA.md).

## Comprobar la entrega

```bash
docker compose up -d --build --wait
docker compose ps
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list
python3 tools/verify_kafka.py
```

Si Docker dice que no encuentra el socket, en Linux se puede iniciar con `sudo systemctl start docker`
Después hay que comprobar que `docker info` funcione y volver a ejecutar los comandos

La prueba crea registros temporales en los tres servicios y espera que sus mensajes lleguen
También revisa que al cancelar una operación no quede su mensaje pendiente y después borra los registros de prueba
Se debe correr en desarrollo
Los datos que ya existían antes de instalar Kafka no generan mensajes por sí solos
Registrar una cuenta nueva desde el juego permite probar un mensaje de jugadores
Las compras y las escrituras antiguas siguen bloqueadas hasta la siguiente fase

Pasaron las pruebas de Go de los cinco módulos y la revisión del archivo de Compose
La prueba completa se ejecutó el 24 de octubre de 2026 y pasó en los tres servicios

```text
jugadores: mensaje recibido y guardado
tienda: mensaje recibido y guardado
cafeteria: mensaje recibido y guardado
```

## Entregas anteriores

Los detalles y capturas se conservan en estos archivos

- [Actividad 1](docs/FASE_1.md)
- [Actividad 2](docs/FASE_2.md)
- [Actividad 3](docs/FASE_3.md)
- [Cuentas y sesiones](docs/FASE_4.md)
- [Juego web](docs/WEB.md)
- [Chat y presencia](docs/CHAT_Y_PRESENCIA.md)

`docker compose down` conserva los datos
No usar `docker compose down -v` si se quieren guardar las cuentas y los mensajes

Referencias usadas para la conexión [Apache Kafka](https://kafka.apache.org/41/getting-started/docker/) y [REST Proxy](https://docs.confluent.io/platform/current/kafka-rest/api.html)
