extends SceneTree
const UI := preload("res://scripts/ui/PixelUI.gd")
const REQUIRED := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 áéíóúÁÉÍÓÚñÑüÜ¿?¡!.,:;()[]+-/$%·"
var failures := 0
var plaza: Node
var render := false
var fixture_layer: CanvasLayer
var buttons: Array[Button] = []

func _initialize() -> void:
    render = "--render-ui" in OS.get_cmdline_user_args()
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    if ok:
        print("PASS ", message)
    else:
        failures += 1
        push_error("FAIL " + message)

func settle() -> void:
    await process_frame
    await process_frame

func capture(file: String) -> void:
    if not render:
        return
    await settle()
    await RenderingServer.frame_post_draw
    var err := root.get_texture().get_image().save_png("res://docs/ui/" + file)
    check(err == OK, "Captura " + file)

func run() -> void:
    var font := UI.THEME.default_font as FontFile
    check(font != null, "Fuente propia en el tema global")
    var missing := ""
    for character in REQUIRED:
        if not font.has_char(character.unicode_at(0)):
            missing += character
    check(missing.is_empty(), "Español completo sin fallback: " + missing)
    check(font.antialiasing == TextServer.FONT_ANTIALIASING_NONE, "Fuente sin antialiasing")
    check(font.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED, "Sin posicionamiento subpixel")
    check(not font.allow_system_fallback, "Sin sustitución silenciosa por fuente del sistema")
    check(is_equal_approx(font.oversampling, 1), "Rasterizado a resolución nativa")
    check(ProjectSettings.get_setting("display/window/stretch/mode") == "viewport", "Viewport compartido por mundo y UI")
    check(ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer", "Escalado entero")
    var normal: StyleBox = UI.THEME.get_stylebox("normal", "Button")
    var hover: StyleBox = UI.THEME.get_stylebox("hover", "Button")
    var pressed: StyleBox = UI.THEME.get_stylebox("pressed", "Button")
    var disabled: StyleBox = UI.THEME.get_stylebox("disabled", "Button")
    check(normal.fill != hover.fill and hover.fill != pressed.fill and disabled.fill != normal.fill, "Cuatro estados visuales distintos")
    check(pressed.shift == 2 and pressed.depth == 0, "Pulsación discreta de dos píxeles")
    check(normal.get_minimum_size() == pressed.get_minimum_size(), "Pulsación sin saltos de layout")
    var packed := load("res://scenes/plaza/Plaza.tscn") as PackedScene
    plaza = packed.instantiate()
    root.add_child(plaza)
    current_scene = plaza
    await settle()
    plaza._pasear()
    await settle()
    await capture("plaza-pixel.png")
    # These direct state assignments only populate a local visual fixture.
    # No purchase callback is invoked and no account is selected on the server.
    root.get_node("EstadoJuego").jugador_nombre = "Pingüino Ñandú"
    root.get_node("EstadoJuego").monedas = 18
    plaza._crear_hud()
    plaza.mostrar_aviso("¡Hola, pingüino! ¿Tomamos un café?")
    await capture("hud-espanol.png")
    plaza.get_node("Cafeteria")._on_body_entered(plaza.jugador_nodo)
    check(plaza.get_node("Cafeteria/Indicacion").get_theme_font("font").get_font_name() == font.get_font_name(), "Indicadores con la fuente global")
    plaza.get_node("Cafeteria")._on_body_exited(plaza.jugador_nodo)
    plaza.ui_hud.show_notice("")
    plaza._mostrar_seleccion_jugador()
    await settle()
    plaza.authPanel.showForm("register")
    plaza.authPanel.usernameField.text = "Ángela"
    await capture("selector-pixel.png")
    plaza._pasear()
    await settle()
    var cafe := plaza.get_node("Cafeteria")
    cafe._abrir_panel()
    await settle()
    var buy_buttons: Array[Button] = []
    collect_buttons(cafe.panel_comercio, buy_buttons)
    var disabled_count := 0
    for button in buy_buttons:
        if button.disabled:
            disabled_count += 1
    check(cafe.panel_comercio.name == "CoffeeMinigame" and cafe.panel_comercio.state == "intro" and cafe.panel_comercio.rain.active.size() == 4, "Cafetería abre demostración visual antes de comenzar")
    await capture("cafeteria-pixel.png")
    cafe._cerrar_panel()
    await settle()
    # Display the shop using the same shared component without contacting the API.
    var shop := UI.modal(plaza, "Tienda")
    var body: VBoxContainer = shop.body
    body.add_child(UI.label("Tus monedas: 18", "SecondaryLabel"))
    var list := UI.list_area(body, 180)
    UI.product_row(list, "Bufanda de invierno · $15 · Stock: 3", false, func(): pass)
    UI.product_row(list, "Gorro azul · $25 · Stock: 0", true, func(): pass)
    await capture("tienda-componentes.png")
    shop.layer.queue_free()
    await settle()
    make_fixture()
    await settle()
    var activations := [0]
    buttons[3].pressed.connect(func(): activations[0] += 1)
    await click(buttons[3])
    check(activations[0] == 0, "Disabled no activa acciones")
    buttons[0].pressed.connect(func(): activations[0] += 1)
    await click(buttons[0])
    check(activations[0] == 1, "Botón normal activa una sola vez")
    var motion := InputEventMouseMotion.new()
    motion.position = buttons[1].get_global_rect().get_center()
    root.push_input(motion)
    await settle()
    await capture("componentes-pixel.png")
    var sizes := [Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1920, 1200)] if render else [Vector2i(960, 600)]
    for size in sizes:
        if render:
            root.size = size
        await settle()
        var scale := root.get_screen_transform().get_scale()
        check(is_equal_approx(scale.x, roundf(scale.x)) and is_equal_approx(scale.y, roundf(scale.y)), "Escala entera " + str(size))
        var logical: Vector2 = root.get_visible_rect().size
        check(logical.is_equal_approx(Vector2(960, 600)), "Lienzo lógico estable " + str(size))
        check(controls_fit(fixture_layer, Rect2(Vector2.ZERO, logical)), "Controles sin recortes " + str(size))
        print("WINDOW requested=", size, " actual=", root.size, " logical=", logical, " scale=", scale)
    if render:
        root.size = Vector2i(960, 600)
        await settle()
    var samples: Array[float] = []
    for i in range(30):
        await process_frame
        samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
    var total := 0.0
    for sample in samples:
        total += sample
    print("UI_PROFILE with_panel_average_process_ms=", total / samples.size(), " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
    fixture_layer.hide()
    plaza.interfaz.hide()
    await settle()
    total = 0.0
    for i in range(30):
        await process_frame
        total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
    print("UI_PROFILE world_only_average_process_ms=", total / 30.0, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
    print("PIXEL_UI_VALIDATION failures=", failures)
    quit(0 if failures == 0 else 1)

func collect_buttons(node: Node, result: Array[Button]) -> void:
    if node is Button:
        result.append(node)
    for child in node.get_children():
        collect_buttons(child, result)

func controls_fit(node: Node, rect: Rect2) -> bool:
    if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
        if not rect.grow(1).encloses(node.get_global_rect()):
            return false
        if node.get_theme_font("font").get_font_name() != UI.THEME.default_font.get_font_name():
            return false
    for child in node.get_children():
        if not controls_fit(child, rect):
            return false
    return true

func click(button: Button) -> void:
    await settle()
    var point := button.get_global_rect().get_center()
    var motion := InputEventMouseMotion.new()
    motion.position = point
    motion.global_position = point
    root.push_input(motion, true)
    var hovered := root.gui_get_hovered_control()
    print("CLICK_TARGET text=", button.text, " matched=", hovered == button)
    # A synthetic click is atomic. Yielding between press/release lets real OS
    # mouse motion cancel it while the hidden visual-review window is running.
    for down in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
        event.position = point
        event.global_position = point
        event.pressed = down
        root.push_input(event, true)
    await process_frame

func make_fixture() -> void:
    var window := UI.modal(plaza, "Componentes pixel-art")
    fixture_layer = window.layer
    var body: VBoxContainer = window.body
    body.add_child(UI.label("ÁÉÍÓÚ  áéíóú  Ññ  Üü  ¿?  ¡!"))
    body.add_child(UI.label("Mayúsculas, minúsculas y números: 0123456789"))
    body.add_child(UI.label("¡Hola, pingüino! ¿Tomamos un café?", "SecondaryLabel"))
    var row := HBoxContainer.new()
    body.add_child(row)
    for text in ["Normal", "Hover", "Pulsado", "Inactivo"]:
        var button := UI.button(text)
        button.focus_mode = Control.FOCUS_NONE
        row.add_child(button)
        buttons.append(button)
    buttons[2].toggle_mode = true
    buttons[2].button_pressed = true
    buttons[3].disabled = true
    body.add_child(UI.label("Bordes de 2 px · sombras duras · sin transiciones", "SecondaryLabel"))
