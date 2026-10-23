# Juego en el navegador

La dirección http://localhost:3000 redirige a `/game/` y ejecuta la misma escena `scenes/plaza/Plaza.tscn` mediante WebAssembly y WebGL 2. El frontend no contiene otro juego ni formularios separados.

## Ejecución reproducible

Instalar Godot 4.7.2 y sus plantillas oficiales de la misma versión desde **Editor → Administrar plantillas de exportación**. En este entorno se instalaron las variantes Web del paquete oficial https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable en `~/.local/share/godot/export_templates/4.7.2.stable/`.

Con Docker iniciado y `.env` configurado:

```bash
bash setup.sh
```

Ese comando exporta el proyecto y construye/inicia Docker Compose. Para actualizar únicamente el juego después de modificar Godot:

```bash
bash tools/export_web.sh
docker compose up --build --no-deps -d --wait frontend
docker compose exec -T gateway nginx -s reload
```

La recarga del gateway renueva la resolución del contenedor frontend si cambió su IP. `GODOT_BIN` permite elegir otro ejecutable compatible. La exportación generada en `frontend/game/` se ignora en Git; debe regenerarse antes de construir el frontend en otra máquina. Los recursos originales se conservan.

## Configuración

- `export_presets.cfg`: perfil Web, sin hilos ni GDExtension, sin PWA/service worker. Incluye los recursos Godot para conservar preloads, herencia y tema; excluye backend, documentación, configuración y herramientas.
- `scripts/Api.gd`: navegador usa su propio origen; escritorio conserva `http://localhost:8000`. No se utiliza el localhost del visitante como dirección fija del servidor.
- `frontend/nginx.conf`: archivos Web con MIME de WASM, compresión y revalidación de caché; redirección relativa conserva el puerto público. El gateway mantiene las rutas de autenticación y negocio.
- `setup.sh` y `tools/export_web.sh`: importación, exportación y arranque. No descargan plantillas automáticamente.
- `.dockerignore`: evita enviar secretos y herramientas temporales al contexto de construcción del backend.

Se mantiene la resolución base 960 × 600, escalado entero y tema pixel art. Usar un navegador con WebGL 2 y una ventana de al menos 960 × 600 para la distribución existente. No se ha adaptado el diseño a teléfonos. El modo sin hilos evita requerir SharedArrayBuffer/aislamiento entre orígenes: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html.

Las sesiones siguen en memoria: recargar la pestaña requiere iniciar sesión nuevamente. Chat y presencia de otros jugadores ya están integrados; véase `CHAT_Y_PRESENCIA.md`. Las compras seguras siguen pendientes. Para publicar fuera del equipo se necesita HTTPS y configurar el servidor; esta entrega activa únicamente el servicio local existente.

## Verificación

```bash
npm install --prefix .tools/web-test playwright
.tools/web-test/node_modules/.bin/playwright install chromium
node tools/verify_web.cjs
bash tools/verify_infra.sh
```

La prueba de navegador utiliza Chromium con renderizado WebGL por software y guarda capturas en `docs/web/`. Comprueba credenciales inválidas, exploración y movimiento, y crea una cuenta temporal para validar registro y login reales. Elimina únicamente esa cuenta y su jugador al terminar; no imprime contraseñas ni tokens.

### Resultados ejecutados

Verificación realizada con Godot 4.7.2 y Chromium 156 en este entorno:

- `docs/web/validation.log`: `WEB_VALIDATION failures=0`. Carga WASM sin errores del motor, login inválido 401, registro 201 con 100 monedas y login 200 tras recarga. Cuenta temporal eliminada.
- `docs/web/infra-validation.log`: rutas protegidas, frontend y ambas instancias de tienda correctas.
- `docs/web/native-api-validation.log`: `API_VALIDATION failures=0`.
- `docs/web/plaza-validation.log`: `PLAZA_VALIDATION failures=0`.
- Capturas inspeccionadas: `welcome.png`, `authenticated.png`, `guest.png` y `guest-after-click.png`; conservan el tema y muestran el desplazamiento del personaje.
- `git diff --check`, sintaxis Bash y JavaScript: sin errores.

No se verificaron otros navegadores ni teléfonos. No se realizaron commits ni publicación externa. La siguiente etapa del proyecto sigue siendo compras seguras.
