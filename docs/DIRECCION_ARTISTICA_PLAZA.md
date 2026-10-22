# Plaza del Deshielo
## Guía implementada
Plaza invernal isométrica 2:1. Regiones de atlas 32×32, celdas de suelo 32×16.
Nieve clara, piedra cálida, vegetación verde oscura y acentos propios de cada comercio.
Luz superior izquierda; sombras cortas hacia abajo/derecha. Siluetas despejadas.
Personaje a escala uniforme 0.75; contorno y transparencia sin suavizado.
Resolución lógica 960×600 para encuadrar los tres comercios con los recursos existentes.
La resolución de 640×360 de la propuesta era provisional: este encuadre evita reducir más los edificios.
Cámara fija de plaza social; nearest e integer scaling para mantener la lectura del píxel.

## Organización
- Escena principal: res://scenes/plaza/Plaza.tscn
- Cada edificio, pino, banco, arbusto y farol es una escena reutilizable editable.
- Terrain.gd construye TileMapLayer con el atlas original; no hay una imagen gigante de fondo.
- Los recorridos se ajustan en Terrain.gd (WALKS); las posiciones se editan en Plaza.tscn.
- Las huellas de colisión y metadata/huella deben mantenerse sincronizadas.
- El movimiento usa una cuadrícula de navegación de 8 px, con margen de 10 px alrededor de obstáculos.
- Sombra reutilizable mediante Shadow.gd; shader de recorte para halos alfa sin alterar las imágenes.
- Se reutilizan exclusivamente los PNG originales; no se generaron imágenes mediante IA.
- Animaciones: bandera del club; la fuente permanece estática. La tienda usa una variante nevada fija.

## Uso
Clic para caminar. E junto a tienda/cafetería para comprar con un jugador seleccionado.
Pasear por la plaza permite explorar sin iniciar el backend y sin hacer compras.
Elegir jugador conserva la conexión al sistema existente.
Los NPC automáticos fueron retirados. Los registros de jugadores no representan presencia conectada.
La presencia de jugadores reales queda pendiente; no hay movimiento multijugador sincronizado.

## Validación
Godot: importar en headless; abrir la escena; comprobar rutas rodeando la fuente,
entradas accesibles, colisiones y capturas reales con el renderizador Compatibility.
No se afirma un objetivo de FPS sin medirlo en el equipo de destino.

## Originales y reversión
mapaBase.tscn, scenes/edificios, scenes/personaje y todos los PNG se conservan.
Se modifica project.godot y se reparan únicamente las rutas de recursos en las cinco escenas antiguas de la raíz (Cafeteria, CaminarDerecha, Club, Fuente y Tienda).
Sus copias anteriores se guardan en .plaza-backup/*.original; los diseños originales siguen intactos.
Para regresar al mapa anterior, cambiar run/main_scene a res://mapaBase.tscn.

## Controles de acabado
Nieve continua: snow_surface.gdshader elimina los laterales de tierra que no deben repetirse dentro del suelo.
SnowDetails.gd añade marcas discretas deterministas; no se regenera cada frame.
Captura real: docs/plaza-preview.png.
Validación reproducible: Godot --headless --path <proyecto> --script res://tools/verify_plaza.gd -- --plaza-preview.
