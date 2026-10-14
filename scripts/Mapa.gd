extends Node2D
const UI := preload("res://scripts/ui/PixelUI.gd")

const ESCENA_NPC := preload("res://scenes/personaje/PinguinoNPC.tscn")
const PUNTO_APARICION := Vector2(-42, 105)

var jugador_nodo: Node2D
var pinguinos_npc: Dictionary = {}
var puntos_comercio: Array = []
var timer_poll: Timer
var hud: CanvasLayer
var hud_label: Label
var seleccion_ui: CanvasLayer
var caja_seleccion: VBoxContainer
var titulo_seleccion: Label

func _ready() -> void:
    jugador_nodo = get_node_or_null("CaminarDerecha")

    var tienda_nodo := get_node_or_null("Tienda")
    if tienda_nodo:
        puntos_comercio.append({"pos": tienda_nodo.global_position, "tipo": "tienda"})
    var cafeteria_nodo := get_node_or_null("Cafeteria")
    if cafeteria_nodo:
        puntos_comercio.append({"pos": cafeteria_nodo.global_position, "tipo": "cafeteria"})

    timer_poll = Timer.new()
    add_child(timer_poll)
    timer_poll.wait_time = 4.0
    timer_poll.autostart = false
    timer_poll.timeout.connect(_actualizar_jugadores)

    EstadoJuego.jugador_seleccionado.connect(func(_id, _nombre, _monedas):
        _crear_hud()
        timer_poll.start()
        _actualizar_jugadores()
    )

    _mostrar_seleccion_jugador()

func _mostrar_seleccion_jugador() -> void:
    var window := UI.modal(self, "Elige tu jugador")
    seleccion_ui = window.layer
    caja_seleccion = UI.list_area(window.body)
    titulo_seleccion = UI.label("Jugadores", "SecondaryLabel")
    caja_seleccion.add_child(titulo_seleccion)
    _cargar_lista_seleccion()

func _cargar_lista_seleccion() -> void:
    for hijo in caja_seleccion.get_children():
        if hijo != titulo_seleccion:
            hijo.queue_free()

    var cargando := UI.label("")
    cargando.name = "cargando_tmp"
    cargando.text = "Cargando jugadores..."
    caja_seleccion.add_child(cargando)

    Api.jugadores_listar(func(codigo, datos):
        if not is_instance_valid(caja_seleccion):
            return
        if is_instance_valid(cargando):
            cargando.queue_free()

        if codigo != 200 or datos == null or datos.size() == 0:
            var vacio := UI.label("")
            vacio.text = "No hay jugadores disponibles.\nPuedes volver a intentarlo."
            caja_seleccion.add_child(vacio)
            var reintentar := UI.button("")
            reintentar.text = "Reintentar"
            reintentar.pressed.connect(_cargar_lista_seleccion)
            caja_seleccion.add_child(reintentar)
            return

        for jugador in datos:
            var boton := UI.button("")
            boton.text = "%s (monedas: %d)" % [jugador["nombre"], jugador["monedas"]]
            boton.pressed.connect(func():
                EstadoJuego.seleccionar_jugador(jugador["id"], jugador["nombre"], jugador["monedas"])
                seleccion_ui.queue_free()
            )
            caja_seleccion.add_child(boton)
    )

func _crear_hud() -> void:
    hud = CanvasLayer.new()
    add_child(hud)
    var margin := MarginContainer.new()
    margin.theme_type_variation = "ScreenMargin"
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud.add_child(margin)
    UI.full_rect(margin)
    var column := VBoxContainer.new()
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_child(column)
    hud_label = UI.label("")
    column.add_child(hud_label)
    _actualizar_hud()
    EstadoJuego.monedas_cambiaron.connect(func(_m): _actualizar_hud())

func _actualizar_hud() -> void:
    hud_label.text = "%s - monedas: %d" % [EstadoJuego.jugador_nombre, EstadoJuego.monedas]

func _actualizar_jugadores() -> void:
    Api.jugadores_listar(func(codigo, datos):
        if codigo != 200 or datos == null:
            return
        for jugador in datos:
            var id: int = int(jugador["id"])
            if id == EstadoJuego.jugador_id:
                continue
            if pinguinos_npc.has(id):
                continue
            _spawn_npc(id, jugador)
    )

func _spawn_npc(id: int, jugador: Dictionary) -> void:
    print("[Mapa] registrado jugador nuevo, agrego pinguino al mapa: id=", id, " nombre=", jugador["nombre"])
    pinguinos_npc[id] = null

    var npc := ESCENA_NPC.instantiate()
    add_child(npc)
    var centro := jugador_nodo.global_position if jugador_nodo else PUNTO_APARICION
    var angulo := randf() * TAU
    var radio := randf_range(60.0, 140.0)
    npc.position = centro + Vector2(cos(angulo), sin(angulo)) * radio
    npc.set_datos(id, str(jugador["nombre"]), int(jugador["monedas"]))
    npc.set_comercios(puntos_comercio)
    pinguinos_npc[id] = npc

    npc.visible = true
