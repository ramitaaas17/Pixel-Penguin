# Proyecto Final - Primera Entrega

Este es el sistema distribuido que acompaña al juego del pinguino (el proyecto de Godot esta en la carpeta de siempre, `assets/`, `scenes/`, `scripts/`, `mapaBase.tscn`, etc). Lo que hay aqui abajo es aparte, es el backend/frontend/middleware que pide la materia, tematizado con lo mismo del juego (jugadores, la tienda, la cafeteria).

## Estructura

```
penguin/
├── docker-compose.yml
├── setup.sh
├── frontend/            pagina html + js que le pega al middleware
├── middleware/           gateway con service discovery estatico y load balancing round robin
└── backend/
    ├── jugadores/         servicio de jugadores (postgres propio)
    ├── tienda/            servicio de la tienda (postgres propio, corre con 2 instancias)
    └── cafeteria/          servicio de pedidos de la cafeteria (postgres propio)
```

Cada servicio del backend sigue el mismo patron: un modelo que recibe la conexion a la base de datos por constructor, y un controller que recibe el modelo por constructor. Eso es inyeccion de dependencias, sin usar ningun framework, solo structs con punteros.

El middleware lee `services.json` al arrancar (ahi esta el service discovery estatico) y por cada prefijo reparte las peticiones en round robin entre los targets que tenga. Por eso `tienda` corre con 2 instancias (`tienda-service-1` y `tienda-service-2`), para poder demostrar el load balancing.

## Como correrlo

```bash
./setup.sh
```

o directo:

```bash
docker compose up --build
```

## Como probarlo

```bash
curl http://localhost:8000/jugadores
curl -X POST http://localhost:8000/jugadores -d '{"nombre":"Pingu2","monedas":30}'

curl http://localhost:8000/tienda
curl -X POST http://localhost:8000/tienda -d '{"nombre":"Gorro","precio":90,"stock":10}'

curl http://localhost:8000/cafeteria
curl -X POST http://localhost:8000/cafeteria -d '{"producto":"Chocolate caliente","cantidad":1}'
```

Para ver el load balancing entre las 2 instancias de la tienda, pegale varias veces seguidas y revisa el header `X-Instance-Name`:

```bash
for i in 1 2 3 4; do curl -si http://localhost:8000/tienda | grep X-Instance-Name; done
```

El frontend queda en `http://localhost:3000`.
