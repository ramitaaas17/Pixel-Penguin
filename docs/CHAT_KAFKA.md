# Chat en vivo mediante Kafka

## Flujo

```text
Godot → WebSocket /plaza → middleware valida sesión/texto/frecuencia
    → cola acotada → Kafka REST → pixelpenguin.chat, partición 0
    → consumidor del middleware → WebSocket → globo del emisor
```

La identidad siempre procede de la sesión validada por gRPC. Los eventos contienen epoch del proceso, secuencia, ID y nombre del jugador, texto y hora; no contienen tokens ni contraseñas. No se registra el contenido del chat en los logs de la aplicación. Kafka almacena el texto como parte del transporte, con retention.ms=3600000 configurado en el tópico.

No hay historial consultable ni reproducción de mensajes anteriores al entrar. El welcome conserva history vacío por compatibilidad. No se usan las tablas outbox/inbox de los servicios: el chat es efímero, sin promesa de entrega a usuarios desconectados.

## Orden y recuperación

Una sola partición y un productor secuencial conservan el orden en la sala. La cola tiene capacidad para 128 mensajes y no realiza llamadas HTTP con el mutex de la plaza tomado. El consumidor se asigna a la partición 0 y se posiciona al final antes de habilitar publicaciones. Se confirma esa posición inicial y se conserva en memoria el siguiente offset leído para recrear el consumidor REST sin saltar los mensajes pendientes del proceso actual.

Solo los eventos del epoch actual, con secuencia creciente y texto válido, pueden generar globos. Se descartan duplicados y mensajes de más de 15 segundos. Reiniciar el middleware genera otro epoch y empieza al final del tópico. Se mantiene una sola instancia del middleware; esto no implementa presencia compartida entre réplicas.

Si Kafka falla, no hay entrega directa alternativa: el emisor recibe un aviso. Se vacía la cola pendiente y se intenta recuperar el consumidor. El movimiento y la autenticación no dependen de esas llamadas HTTP. No hay garantía de entrega durante caídas; un timeout de publicación puede ocurrir después de que Kafka haya aceptado el mensaje y no se reintenta automáticamente esa publicación.

## Actualizar

Conservar .env y los volúmenes existentes:

```bash
bash tools/export_web.sh
docker compose up -d --build --wait
docker compose exec -T gateway nginx -s reload
```

Compose crea el tópico del chat junto a los tópicos existentes. KAFKA_REST_URL es obligatorio para el middleware. El log `chat Kafka: consumidor listo` indica que terminó el inicio del consumidor; no es un healthcheck continuo de Kafka.

## Pruebas

Pruebas unitarias de ida y vuelta, deduplicación, fallos, cola acotada, recuperación de offset y movimiento independiente:

```bash
go -C middleware test -race ./plaza -run 'TestKafka|TestHub|TestValidation|TestConcurrent'
go -C middleware vet ./...
godot --headless --path . --script res://tools/verify_chat_ui.gd
```

Prueba con Kafka real y dos WebSockets, sin crear cuentas en las bases (usa identidades de prueba en un servidor WebSocket aislado):

```bash
CGO_ENABLED=0 go -C middleware test -c ./plaza -o /tmp/pixel-penguin-plaza.test
docker compose run --rm --no-deps -v /tmp/pixel-penguin-plaza.test:/tmp/plaza.test:ro --entrypoint /tmp/plaza.test middleware -test.v -test.timeout=60s
```

El binario ejecuta toda la suite de plaza y habilita TestKafkaLiveWebSocket cuando existe KAFKA_REST_URL. La prueba real publica mensajes temporales en el tópico del chat, verifica el mismo texto/identidad/secuencia en dos clientes y responde desde el segundo. El epoch aislado impide que se muestren en la sala de producción. No altera cuentas ni detiene Kafka.

Resultados del 30 de octubre de 2026: pruebas unitarias con race correctas; go vet correcto; toda la suite de plaza correcta dentro de Docker, incluida la prueba real bidireccional con Kafka (2,39 s); verificador de chat Godot sin fallos; configuración Compose válida; tópico real con una partición y retención configurada de una hora; middleware construido y saludable. La ejecución nativa de la suite completa no pudo abrir el socket local por el sandbox, por eso se completó dentro de Docker. No se probó esta modificación con dos computadoras físicas ni se realizó una nueva revisión visual.

Referencia del protocolo REST: https://docs.confluent.io/platform/current/kafka-rest/api.html
