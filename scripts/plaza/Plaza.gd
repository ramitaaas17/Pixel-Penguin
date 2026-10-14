extends "res://scripts/Mapa.gd"
const PLAYER_SCRIPT := preload("res://scripts/plaza/PlazaPlayer.gd")
const NPC_SCRIPT := preload("res://scripts/plaza/PlazaNPC.gd")
const SHADOW := preload("res://scripts/plaza/Shadow.gd")
const PLAYER_SCENE := preload("res://scenes/personaje/CaminarDerecha.tscn")
const MAX_NPC := 12
const HUD_SCRIPT := preload("res://scripts/ui/PixelHUD.gd")
var ui_hud: Control
var caminos := AStarGrid2D.new()
var bloqueos: Array[Rect2] = []
var aviso: Label
var aviso_timer: Timer
var interfaz: CanvasLayer

func _ready() -> void:
    _preparar_navegacion()
    var player := PLAYER_SCENE.instantiate()
    player.name = "CaminarDerecha"
    player.set_script(PLAYER_SCRIPT)
    player.position = Vector2(-32, 148)
    player.add_to_group("jugador_local")
    _normalizar_personaje(player)
    player.get_node("Camara").enabled = false
    add_child(player)
    _crear_interfaz()
    super._ready()
    if "--plaza-preview" in OS.get_cmdline_user_args():
        _pasear()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--plaza-capture="):
            _capturar.call_deferred(arg.trim_prefix("--plaza-capture="))

func _normalizar_personaje(personaje: Node2D) -> void:
    var dibujo := personaje.get_node("Sprite2D") as Sprite2D
    dibujo.position = Vector2.ZERO
    dibujo.scale = Vector2(0.75, 0.75)
    dibujo.offset = Vector2(-32, -59)
    dibujo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    var collider := personaje.get_node("CollisionShape2D") as CollisionShape2D
    var forma := RectangleShape2D.new()
    forma.size = Vector2(16, 8)
    collider.shape = forma
    collider.position = Vector2(0, -3)
    var sombra := Node2D.new()
    sombra.set_script(SHADOW)
    sombra.size = Vector2(25, 9)
    sombra.position = Vector2(3, 0)
    sombra.z_index = -1
    personaje.add_child(sombra)

func _preparar_navegacion() -> void:
    for obj in get_tree().get_nodes_in_group("obstaculos_plaza"):
        var rect: Rect2 = obj.get_meta("huella", Rect2())
        rect.position += obj.global_position
        bloqueos.append(rect.grow(10))
    caminos.region = Rect2i(-58, -30, 116, 61)
    caminos.cell_size = Vector2(8, 8)
    caminos.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    caminos.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    caminos.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    caminos.update()
    for x in range(-58, 58):
        for y in range(-30, 31):
            var id := Vector2i(x, y)
            var p := Vector2(id) * 8
            var solid := ((p - Vector2(0, 5)) / Vector2(410, 165)).length_squared() > 1.0
            if not solid:
                for rect in bloqueos:
                    if rect.has_point(p):
                        solid = true
                        break
            caminos.set_point_solid(id, solid)

    # Remove tiny pockets trapped between perimeter props and the island edge.
    # Every selectable destination must belong to the same reachable plaza.
    var abiertos: Array[Vector2i] = [Vector2i(-4, 18)]
    var visitados: Dictionary = {Vector2i(-4, 18): true}
    var cursor := 0
    var vecinos: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
    while cursor < abiertos.size():
        var actual := abiertos[cursor]
        cursor += 1
        for paso in vecinos:
            var siguiente := actual + paso
            if not caminos.region.has_point(siguiente) or visitados.has(siguiente):
                continue
            if caminos.is_point_solid(siguiente):
                continue
            visitados[siguiente] = true
            abiertos.append(siguiente)
    for x in range(-58, 58):
        for y in range(-30, 31):
            var id := Vector2i(x, y)
            if not visitados.has(id):
                caminos.set_point_solid(id, true)

func _celda_libre(p: Vector2) -> Vector2i:
    var id := Vector2i((p / 8.0).round())
    id.x = clampi(id.x, -57, 56)
    id.y = clampi(id.y, -29, 29)
    if not caminos.is_point_solid(id):
        return id
    var mejor := Vector2i.ZERO
    var distancia := INF
    # Search the finite plaza; clicks on roofs/outside the island land at its edge.
    for x in range(-52, 53):
        for y in range(-24, 25):
            var c := Vector2i(x, y)
            if caminos.is_point_solid(c):
                continue
            var d := (Vector2(c) * 8).distance_squared_to(p)
            if d < distancia:
                distancia = d
                mejor = c
    return mejor

func ruta_hacia(origen: Vector2, objetivo: Vector2) -> PackedVector2Array:
    return caminos.get_point_path(_celda_libre(origen), _celda_libre(objetivo))

func _crear_interfaz() -> void:
    interfaz = CanvasLayer.new()
    interfaz.name = "InterfazPlaza"
    add_child(interfaz)
    ui_hud = Control.new()
    ui_hud.set_script(HUD_SCRIPT)
    interfaz.add_child(ui_hud)
    aviso = ui_hud.aviso
    ui_hud.elegir.pressed.connect(func():
        if not is_instance_valid(seleccion_ui):
            jugador_nodo.habilitado = false
            jugador_nodo.ruta.clear()
            _mostrar_seleccion_jugador()
    )
    aviso_timer = Timer.new()
    aviso_timer.one_shot = true
    aviso_timer.wait_time = 4
    aviso_timer.timeout.connect(func(): ui_hud.show_notice(""))
    add_child(aviso_timer)

func _mostrar_seleccion_jugador() -> void:
    var ventana := UI.modal(self, "Nos vemos en la plaza", _pasear)
    seleccion_ui = ventana.layer
    seleccion_ui.name = "SeleccionJugador"
    var content: VBoxContainer = ventana.body
    content.add_child(UI.label("Elige tu pingüino o entra a dar un paseo.", "SecondaryLabel"))
    caja_seleccion = UI.list_area(content, 144)
    titulo_seleccion = UI.label("Jugadores", "SecondaryLabel")
    caja_seleccion.add_child(titulo_seleccion)
    var paseo := UI.button("Pasear por la plaza")
    paseo.name = "Pasear"
    paseo.pressed.connect(_pasear)
    content.add_child(paseo)
    paseo.grab_focus.call_deferred()
    if "--plaza-preview" not in OS.get_cmdline_user_args():
        _cargar_lista_seleccion()

func _unhandled_key_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel") and is_instance_valid(seleccion_ui):
        _pasear()
        get_viewport().set_input_as_handled()

func _cargar_lista_seleccion() -> void:
    var target := caja_seleccion
    for child in target.get_children():
        if child != titulo_seleccion:
            child.queue_free()
    var cargando := UI.label("Buscando jugadores...", "SecondaryLabel")
    target.add_child(cargando)
    Api.jugadores_listar(func(codigo, datos):
        if not is_instance_valid(target):
            return
        if is_instance_valid(cargando):
            cargando.queue_free()
        if codigo != 200 or not datos is Array or datos.is_empty():
            target.add_child(UI.wrapped_label("Puedes pasear mientras no haya jugadores.", "SecondaryLabel"))
            var retry := UI.button("Volver a buscar")
            retry.pressed.connect(_cargar_lista_seleccion)
            target.add_child(retry)
            return
        for registro in datos:
            var boton := UI.button(str(registro.get("nombre", "Pingüino")))
            boton.pressed.connect(func():
                EstadoJuego.seleccionar_jugador(int(registro["id"]), str(registro["nombre"]), int(registro["monedas"]))
                _pasear()
            )
            target.add_child(boton)
    )

func _pasear() -> void:
    if is_instance_valid(seleccion_ui):
        seleccion_ui.queue_free()
    jugador_nodo.habilitado = true

func _crear_hud() -> void:
    hud_label = ui_hud.estado
    hud_label.visible = true
    _actualizar_hud()
    if not EstadoJuego.monedas_cambiaron.is_connected(_monedas_cambiaron):
        EstadoJuego.monedas_cambiaron.connect(_monedas_cambiaron)

func _monedas_cambiaron(_valor: int) -> void:
    _actualizar_hud()

func mostrar_aviso(texto: String) -> void:
    ui_hud.show_notice(texto)
    aviso_timer.start()

func _actualizar_jugadores() -> void:
    Api.jugadores_listar(func(codigo, datos):
        if codigo != 200 or not datos is Array:
            return
        var presentes: Array[int] = []
        for registro in datos:
            var id := int(registro["id"])
            if id == EstadoJuego.jugador_id:
                continue
            presentes.append(id)
        for id in pinguinos_npc.keys():
            if id not in presentes:
                if is_instance_valid(pinguinos_npc[id]):
                    pinguinos_npc[id].queue_free()
                pinguinos_npc.erase(id)
        for registro in datos:
            var id := int(registro["id"])
            if id == EstadoJuego.jugador_id or pinguinos_npc.has(id) or pinguinos_npc.size() >= MAX_NPC:
                continue
            _spawn_npc(id, registro)
    )

func _spawn_npc(id: int, registro: Dictionary) -> void:
    var npc := ESCENA_NPC.instantiate()
    npc.set_script(NPC_SCRIPT)
    _normalizar_personaje(npc)
    var a := float(pinguinos_npc.size()) * 2.39996
    var point := Vector2(cos(a) * 155, 90 + sin(a) * 45)
    npc.position = Vector2(_celda_libre(point)) * 8
    add_child(npc)
    npc.set_datos(id, str(registro["nombre"]), int(registro["monedas"]))
    var comercios: Array = []
    for edificio in [$Tienda, $Cafeteria]:
        comercios.append({"pos": edificio.get_node("Entrada").global_position, "tipo": edificio.tipo_comercio})
    npc.set_comercios(comercios)
    var label := npc.get_node("Nombre") as Label
    label.position = Vector2(-60, -58)
    label.size = Vector2(120, 20)
    label.theme_type_variation = "NameLabel"
    label.remove_theme_color_override("font_color")
    label.remove_theme_font_size_override("font_size")
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    pinguinos_npc[id] = npc

func _capturar(path: String) -> void:
    await get_tree().create_timer(1.0).timeout
    await RenderingServer.frame_post_draw
    var err := get_viewport().get_texture().get_image().save_png(path)
    print("PLAZA_CAPTURE ", path, " status=", err)
    get_tree().quit(0 if err == OK else 1)
