# Regla global de arte
Todo el videojuego, incluida la interfaz, pertenece al mismo lenguaje pixel-art.
No mezclar tipografía de sistema ni elementos web con los sprites.
La regla incluye cualquier futuro inventario, chat, configuración, diálogo e icono.

## Tema y componentes
- Tema global: assets/ui/pixel_theme.tres; registrado en project.godot.
- Botón reutilizable: scenes/ui/PixelButton.tscn. NORMAL, HOVER, PRESSED, DISABLED y foco de teclado.
- PixelStyleBox.gd dibuja bordes de 2 px y esquinas escalonadas con rectángulos enteros.
  Los centros se expanden sin estirar los bordes, como un 9-slice; no requiere una textura nueva.
- Pulsación: desplazamiento visual de 2 px, sin cambiar el mínimo del control ni mover sus vecinos.
- PixelUI.gd centraliza ventanas, listas, filas de comercio y creación de botones.
- PixelHUD.gd usa MarginContainer, VBoxContainer, HBoxContainer y anclajes de pantalla.
- Variaciones: TitleLabel, HeadingLabel, SecondaryLabel, WorldHint, NameLabel y KeyLabel.
- Colores y tamaños se cambian en el Theme, no mediante overrides aislados de cada Label.
- No hay tweens, desenfoque ni redibujado continuo de paneles; el cursor sigue el ratón en píxeles enteros.

## Tipografía autorizada
Pixelify Sans, autorizada por el usuario en esta conversación.
Fuente: https://github.com/google/fonts/tree/main/ofl/pixelifysans
Autor: https://github.com/eifetx/Pixelify-Sans
Licencia SIL Open Font License 1.1, incluida en assets/ui/fonts/OFL.txt.
Archivo: assets/ui/fonts/PixelifySans.ttf
SHA256: 9BA86CD010A4DE309D263CEFF8E8044092C9DB7EFDA869620CB9FF1C4389E8A5
No se modifica el archivo original de la fuente.
Rasterizado: antialiasing OFF, hinting OFF, subpixel OFF, oversampling 1,
mipmaps OFF, MSDF OFF, fallback de sistema OFF, avance de glifos redondeado.
Tamaños centralizados: cuerpo/botones 20; secundario/nombres/teclas 16;
título de plaza 24 y ventanas 28. No escalar controles de texto individualmente.
Se comprueban glifos de español, números, puntuación y símbolos presentes.

## Paleta
Texto principal #243D49; secundario #334C57.
Panel claro #F3F5ED; placas #EAF1EC; bordes #355563.
Botón #355968, hover #416D7A, pulsado #294B59.
Texto de botón #F3F5ED. Disabled #B8C6C8 con texto #3B535E.
Foco visible #B07134. Sombras duras #203744, sin blur.

## Resolución
Lienzo lógico fijo 960×600. Stretch viewport, aspecto keep y escala integer.
Mundo y UI se rasterizan juntos antes de ampliar: no hay UI de alta resolución encima de un mapa pixelado.
Filtrado nearest, pixel snapping de transformaciones y controles; cámara sin zoom fraccionario.
Ventana mínima 960×600 para impedir el recorte que produciría una ventana inferior a la base.
En tamaños que no admiten el siguiente múltiplo entero se usan márgenes, sin estirar píxeles.
960×600 -> 1×; 1280×720 -> 1× con márgenes; 1920×1080 -> 1× con márgenes;
1920×1200 -> 2×. Esta estrategia prioriza nitidez sobre llenar toda la pantalla.
Las interfaces usan contenedores y listas con scroll, sin posiciones absolutas de pantalla.
Las posiciones relativas de nombres sobre personajes sí pertenecen al espacio del mundo.

## Revisión
tools/verify_pixel_ui.gd comprueba caracteres, fuente sin fallback, estados y clics,
colocación, tamaño lógico y escala entera. Con --render-ui produce capturas en docs/ui.
Las fichas de tienda de la galería son datos locales de prueba, sin compras ni cambios de servidor.
El backend y las reglas de compra originales se conservan.
Los iconos futuros deben usar una cuadrícula y paleta compatibles; no añadir packs vectoriales modernos.
La actual flecha es un dibujo de píxeles definido en código, sin dependencias.

## Alcance del arte heredado
No se redibujan las imágenes del mapa en este cambio de UI.
Los pinos y edificios originales conservan diferentes niveles de detalle y los rótulos dibujados
dentro de sus PNG. El filtrado y el viewport son comunes; una homogeneización artística completa
de esos detalles requiere revisar los sprites originales por separado.
No afirmar que esos PNG han sido remasterizados.

## Copias
Los archivos de código/configuración y escenas modificados se respaldan en .ui-backup.
Los PNG originales del juego permanecen intactos.

## Autenticación integrada
AuthPanel.gd reutiliza los paneles y botones existentes para bienvenida, login, registro y cuenta.
El tema incluye LineEdit sin suavizado, contraseña con asteriscos, SecondaryButton y ErrorLabel.
No se añadieron recursos gráficos ni tipografía. Capturas reales en docs/fase4/ui.
Los campos y modales capturan entrada; no se admiten interacciones de comercio mientras están abiertos.
Los comercios quedan en consulta hasta completar las compras seguras de la fase 5.


## Chat y presencia real

ChatPanel.gd reutiliza PixelUI, el tema y PixelButton; panel plegable a la izquierda, historial de 50 mensajes con scroll, campo de 180 caracteres y estado con tooltip. Enter enfoca y ESC pliega. Los invitados no publican mensajes. RemotePenguin.gd reutiliza sprite, escala, sombra y NameLabel del juego, sin NPC ni recursos gráficos nuevos. Capturas verificables y pruebas: docs/social y docs/CHAT_Y_PRESENCIA.md.
