#!/bin/bash

echo "checking docker..."
if ! command -v docker &> /dev/null
then
    echo "docker no esta instalado, instalalo antes de seguir"
    exit 1
fi

echo "descargando y compilando las imagenes..."
docker compose build

echo "levantando los contenedores..."
docker compose up -d

echo "listo, el frontend deberia estar en http://localhost:3000"
echo "el middleware esta en http://localhost:8000"
