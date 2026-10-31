# Chat entre computadoras sin publicar el juego

En el servidor, iniciar Docker y ejecutar desde la raíz del proyecto:

```bash
bash tools/export_web.sh
docker compose up -d --build --wait
```

Conservar el .env existente. Los invitados solo necesitan un navegador. En el servidor se puede abrir http://localhost:3000. Desde otra computadora, esta exportación exige un origen HTTPS con certificado confiable: usar un túnel HTTPS con WebSocket al puerto 3000 o configurar HTTPS en la red local. Compartir una IP por HTTP no basta.

Usar cuentas diferentes: los invitados no pueden conversar y la misma cuenta en dos ventanas transfiere la conexión. El servidor debe permanecer encendido.

Si no abre, comprobar localhost:3000 en el servidor, permitir TCP 3000 en el firewall de la red privada y comprobar que Wi-Fi no aísle los clientes. Localhost en otro equipo apunta a ese otro equipo.

Desde redes diferentes se requiere una red privada virtual compartida o un túnel HTTPS con soporte WebSocket hacia el puerto 3000. No hace falta publicar PostgreSQL, Consul ni Kafka.

## Comprobación manual

1. Entrar desde dos equipos con cuentas distintas.
2. Comprobar presencia y movimiento en ambas pantallas.
3. Enviar mensajes en ambas direcciones con acentos, ñ, ¿ y ¡.
4. Comprobar el globo sobre el emisor en ambas pantallas.
5. Comprobar desaparición del globo y que escribir no mueva al personaje.

## Cambios y límites

Solo el chat usa ChatLabel a 20 px con mayor interlineado y contraste y ChatInput a 22 px. Se conserva Pixelify Sans. Los globos siguen a cada personaje y duran entre 4 y 14 segundos; otro mensaje del mismo personaje reemplaza el anterior. Solo los mensajes nuevos confirmados generan globos; el historial inicial no los genera.

El chat es en vivo y pasa por Kafka. No se envían mensajes anteriores al entrar ni hay historial visible. Kafka debe estar disponible para conversar.

Pasaron las pruebas headless de chat e interfaz pixel art y la exportación Web. Falta verificar dos clientes reales: Docker no estaba activo. No se pudo revisar visualmente por las restricciones del entorno gráfico. El verificador de chat admite --render-chat para capturas a escalas 1 y 2 en un entorno gráfico disponible.

La entrada del chat es una barra inferior de una sola fila, sin botón ni panel de historial. Los mensajes solo se muestran en globos temporales sobre los pingüinos. Enter enfoca el campo y ESC libera el teclado. Las instrucciones de movimiento se colocan arriba de la barra.

## Requisito del navegador comprobado

La exportación actual de Godot exige un contexto seguro. localhost funciona con HTTP para probar en el propio servidor, pero una IP de la red local por HTTP puede mostrar Secure Context missing. Para abrir el juego desde otras computadoras, usar HTTPS con un certificado confiable o un túnel HTTPS que soporte WebSocket al puerto 3000. Compartir solo http://IP:3000 no basta para esta exportación.
