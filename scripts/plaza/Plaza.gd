extends "res://scripts/Mapa.gd"
const PLAYER_SCRIPT := preload("res://scripts/plaza/PlazaPlayer.gd")
const SHADOW := preload("res://scripts/plaza/Shadow.gd")
const PLAYER_SCENE := preload("res://scenes/personaje/CaminarDerecha.tscn")
const HUD_SCRIPT := preload("res://scripts/ui/PixelHUD.gd")
const PLAZA_CONNECTION := preload("res://scripts/plaza/PlazaConnection.gd")
const CHAT_PANEL := preload("res://scripts/ui/ChatPanel.gd")
const CHAT_BUBBLE := preload("res://scripts/ui/ChatBubble.gd")
const REMOTE_PENGUIN := preload("res://scripts/plaza/RemotePenguin.gd")
var plazaConnection: Node
var chatPanel: Control
var remotePlayers: Dictionary = {}
var chatBubbles: Dictionary = {}
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
    plazaConnection = PLAZA_CONNECTION.new()
    plazaConnection.localPlayer = player
    plazaConnection.rosterChanged.connect(_updateRemotePlayers)
    plazaConnection.messageReceived.connect(_showChatBubble)
    add_child(plazaConnection)
    chatPanel = CHAT_PANEL.new()
    chatPanel.connection = plazaConnection
    interfaz.add_child(chatPanel)
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
            _mostrar_seleccion_jugador()
    )
    aviso_timer = Timer.new()
    aviso_timer.one_shot = true
    aviso_timer.wait_time = 4
    aviso_timer.timeout.connect(func(): ui_hud.show_notice(""))
    add_child(aviso_timer)

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

func _capturar(path: String) -> void:
    await get_tree().create_timer(1.0).timeout
    await RenderingServer.frame_post_draw
    var err := get_viewport().get_texture().get_image().save_png(path)
    print("PLAZA_CAPTURE ", path, " status=", err)
    get_tree().quit(0 if err == OK else 1)

func _actualizar_hud() -> void:
    super._actualizar_hud()
    ui_hud.elegir.text = "Mi cuenta" if EstadoJuego.tiene_jugador() else "Entrar"

func _updateRemotePlayers() -> void:
    for id in chatBubbles.keys():
        if not plazaConnection.players.has(id):
            if is_instance_valid(chatBubbles[id]):
                chatBubbles[id].queue_free()
            chatBubbles.erase(id)
    for id in remotePlayers.keys():
        if not plazaConnection.players.has(id):
            remotePlayers[id].queue_free()
            remotePlayers.erase(id)
    for id in plazaConnection.players:
        if id == EstadoJuego.jugador_id:
            continue
        var data: Dictionary = plazaConnection.players[id]
        if not remotePlayers.has(id):
            var remote := REMOTE_PENGUIN.new()
            remote.name = "RemotePlayer%d" % id
            remote.setup(jugador_nodo.get_node("Sprite2D"), data)
            add_child(remote)
            remotePlayers[id] = remote
        else:
            remotePlayers[id].applyState(data)

func _showChatBubble(message: Dictionary) -> void:
    var id := int(message.get("playerId", -1))
    var target: Node2D = jugador_nodo if id == EstadoJuego.jugador_id else remotePlayers.get(id)
    if not is_instance_valid(target):
        return
    if not is_instance_valid(chatBubbles.get(id)):
        var bubble := CHAT_BUBBLE.new()
        bubble.target = target
        interfaz.add_child(bubble)
        chatBubbles[id] = bubble
    chatBubbles[id].showMessage(str(message.get("text", "")))
