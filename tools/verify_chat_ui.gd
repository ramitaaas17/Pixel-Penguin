extends SceneTree

var failures := 0

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    print("PASS " if ok else "FAIL ", message)
    if not ok:
        failures += 1

func settle() -> void:
    await process_frame
    await process_frame

func run() -> void:
    var plaza := load("res://scenes/plaza/Plaza.tscn").instantiate() as Node
    root.add_child(plaza)
    current_scene = plaza
    await settle()
    plaza._pasear()
    await settle()
    var connection: Node = plaza.plazaConnection
    var chat: Control = plaza.chatPanel
    check(connection.socket == null and not connection.online, "Invitado no abre una conexión de presencia")
    check(not chat.panel.visible and chat.send.disabled and not chat.input.editable, "Chat plegado y protegido para invitados")
    chat._toggle()
    await settle()
    check(chat.panel.visible, "El invitado puede consultar el estado del chat")
    check(chat.panel.get_global_rect().end.x <= 960 and chat.panel.get_global_rect().end.y <= 552, "Panel compacto dentro del área de juego")
    chat._toggle()
    connection.online = true
    chat._statusChanged("Vista previa de interfaz")
    chat._toggle()
    await settle()
    check(root.gui_get_focus_owner() == chat.input, "Abrir chat enfoca el campo de texto")
    var initial: Vector2 = plaza.jugador_nodo.global_position
    var key := InputEventKey.new()
    key.keycode = KEY_E
    key.unicode = 101
    key.pressed = true
    Input.parse_input_event(key)
    await settle()
    check(chat.input.text == "e", "Escribir E llega al chat")
    check(plaza.jugador_nodo.global_position == initial and not plaza.jugador_nodo.moviendose, "Escribir no mueve al pingüino")
    for commerce in get_nodes_in_group("commerce"):
        check(commerce.panel_comercio == null, "Escribir no abre " + commerce.name)
    connection.messages.clear()
    connection.messages.append({"sequence":1,"name":"Ángela","text":"¡Hola, pingüino! ¿Tomamos un café?"})
    connection.historyChanged.emit()
    await settle()
    check(chat.history.get_child_count() == 1, "Historial sin filas duplicadas")
    check(chat.history.get_child(0).text.contains("pingüino"), "Historial conserva español y acentos")
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    Input.parse_input_event(escape)
    await settle()
    check(not chat.panel.visible and root.gui_get_focus_owner() != chat.input, "ESC cierra chat y libera teclado")
    for i in range(20):
        chat._toggle()
        chat._toggle()
    check(connection.messageReceived.get_connections().size() == 1, "Abrir y cerrar no duplica señales")
    connection.online = false
    print("CHAT_UI_VALIDATION failures=", failures)
    quit(0 if failures == 0 else 1)
