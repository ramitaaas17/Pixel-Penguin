extends SceneTree

var failures := 0

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    print("PASS " if ok else "FAIL ", message)
    if not ok:
        failures += 1

func run() -> void:
    var session = JSON.parse_string(OS.get_environment("SOCIAL_TEST_SESSION"))
    if not session is Dictionary:
        push_error("Ejecuta esta prueba con tools/verify_social_native.py")
        quit(1)
        return
    var plaza := load("res://scenes/plaza/Plaza.tscn").instantiate() as Node
    root.add_child(plaza)
    current_scene = plaza
    await process_frame
    var state := root.get_node("EstadoJuego")
    state.acceptSession(session)
    var connection: Node = plaza.plazaConnection
    var deadline := Time.get_ticks_msec() + 15000
    while not connection.online and Time.get_ticks_msec() < deadline:
        await process_frame
    check(connection.online, "Godot nativo autentica el WebSocket real")
    if not connection.online:
        quit(1)
        return
    check(connection.players.has(state.jugador_id), "Snapshot contiene la identidad autenticada")
    var text := "¡Hola desde Godot nativo, pingüino!"
    check(connection.sendChat(text), "Godot nativo envía chat")
    deadline = Time.get_ticks_msec() + 5000
    while connection.messages.all(func(message): return message.text != text) and Time.get_ticks_msec() < deadline:
        await process_frame
    check(connection.messages.any(func(message): return message.text == text and int(message.playerId) == state.jugador_id), "Servidor confirma mensaje español con identidad real")
    plaza.jugador_nodo.ir_a(Vector2(-96, 136))
    await create_timer(1.5).timeout
    var own: Dictionary = connection.players.get(state.jugador_id, {})
    check(float(own.get("x", -32)) < -60, "Posición recorrida por A* confirmada por el servidor")
    var done := [false]
    root.get_node("Api").logout(func(code, _data):
        check(code == 200, "Logout real confirma revocación")
        done[0] = true
    )
    deadline = Time.get_ticks_msec() + 12000
    while state.tiene_jugador() and Time.get_ticks_msec() < deadline:
        await process_frame
    check(done[0] and not state.tiene_jugador() and not connection.online, "Servidor desconecta la sesión revocada y Godot limpia su identidad")
    print("SOCIAL_NATIVE_VALIDATION failures=", failures)
    quit(0 if failures == 0 else 1)
