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
    check(chat.panel.visible and chat.send.disabled and not chat.input.editable, "Barra visible y envío protegido para invitados")
    check(chat.find_child("ToggleChat", true, false) == null and chat.find_child("ChatHistory", true, false) == null, "Sin botón ni panel de historial")
    check(chat.panel.get_global_rect().end.x <= 960 and chat.panel.get_global_rect().end.y <= 600 and chat.panel.size.y <= 50, "Barra compacta dentro del área de juego")
    connection.online = true
    chat._statusChanged("Vista previa de interfaz")
    chat.input.grab_focus()
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
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    Input.parse_input_event(escape)
    await settle()
    check(chat.panel.visible and root.gui_get_focus_owner() != chat.input, "ESC libera teclado conservando la barra")
    check(connection.messageReceived.get_connections().size() == 1, "Los mensajes solo se muestran en globos")
    var message := {"playerId": root.get_node("EstadoJuego").jugador_id, "text": "¡Hola! ¿Cómo están, pingüinos?"}
    connection.messageReceived.emit(message)
    await settle()
    var bubble: Control = plaza.chatBubbles[root.get_node("EstadoJuego").jugador_id]
    check(bubble.visible and bubble.textLabel.text.replace("\n", " ") == message.text, "Mensaje confirmado aparece sobre el pingüino")
    check(bubble.get_global_rect().position.y >= 0 and bubble.get_global_rect().end.x <= 960, "Globo dentro del viewport")
    connection.players[root.get_node("EstadoJuego").jugador_id] = {}
    connection.players[123] = {"id":123,"name":"Ángela","x":90,"y":100}
    connection.rosterChanged.emit()
    connection.messageReceived.emit({"playerId":123,"text":"¡Hola desde otro pingüino!"})
    await settle()
    check(plaza.chatBubbles[123].visible, "Mensaje remoto aparece sobre su propio pingüino")
    if "--render-chat" in OS.get_cmdline_user_args():
        chat.panel.show()
        for scale in [1, 2]:
            root.size = Vector2i(960, 600) * scale
            await create_timer(0.3).timeout
            await RenderingServer.frame_post_draw
            root.get_texture().get_image().save_png("res://docs/social/chat-bubbles-%d.png" % scale)
    bubble.showMessage("Un mensaje bastante largo para comprobar que el globo crece con las líneas necesarias y después vuelve a su tamaño compacto.")
    await settle()
    check(bubble.size.x <= 180, "Globo largo respeta ancho máximo")
    bubble.showMessage("hola")
    await settle()
    check(bubble.size.x <= 60 and bubble.size.y <= 30, "Hola ocupa un globo pequeño sin altura sobrante")
    bubble._process(0.0)
    var head: Vector2 = plaza.jugador_nodo.get_global_transform_with_canvas() * Vector2(0, -48)
    check(absf(bubble.position.y + bubble.size.y - head.y) <= 1, "Globo junto a la cabeza")
    bubble._process(15.0)
    check(not bubble.visible, "Globo desaparece al terminar su tiempo")
    connection.online = false
    print("CHAT_UI_VALIDATION failures=", failures)
    quit(0 if failures == 0 else 1)
