extends SceneTree
var failures := 0
var plaza: Node
var render: bool = false
var offlineOnly: bool = false

func _initialize() -> void:
    render = "--render-auth" in OS.get_cmdline_user_args()
    offlineOnly = "--offline-auth" in OS.get_cmdline_user_args()
    run.call_deferred()

func check(value: bool, message: String) -> void:
    if value:
        print("PASS ", message)
    else:
        failures += 1
        push_error(message)

func settle() -> void:
    await process_frame
    await process_frame

func waitUntil(predicate: Callable, timeout: int = 12000) -> bool:
    var deadline := Time.get_ticks_msec() + timeout
    while not predicate.call() and Time.get_ticks_msec() < deadline:
        await process_frame
    return predicate.call()

func capture(name: String) -> void:
    if not render:
        return
    await settle()
    await RenderingServer.frame_post_draw
    var error := root.get_texture().get_image().save_png("res://docs/fase4/ui/" + name + ".png")
    check(error == OK, "Captura " + name)

func controlsFit(node: Node) -> bool:
    if node is Control and node.is_visible_in_tree() and (node is Label or node is Button or node is LineEdit):
        if not Rect2(Vector2.ZERO, Vector2(960, 600)).grow(1).encloses(node.get_global_rect()):
            return false
    for child in node.get_children():
        if not controlsFit(child):
            return false
    return true

func run() -> void:
    plaza = load("res://scenes/plaza/Plaza.tscn").instantiate()
    root.add_child(plaza)
    current_scene = plaza
    await settle()
    var panel: Node = plaza.authPanel
    var state: Node = root.get_node("EstadoJuego")
    check(panel.isOpen() and panel.mode == "welcome", "Bienvenida sin selector libre de jugadores")
    await capture("welcome")
    panel.showForm("login")
    await settle()
    check(panel.passwordField.secret and panel.passwordField.secret_character == "*", "Contraseña oculta con glifo propio")
    await capture("login")
    panel.usernameField.grab_focus()
    var event := InputEventKey.new()
    event.keycode = KEY_E
    event.unicode = 101
    event.pressed = true
    root.push_input(event, true)
    await settle()
    check(panel.usernameField.text.contains("e") and plaza.jugador_nodo.ruta.is_empty() and not plaza.canInteract(), "Escribir E no mueve ni activa comercios")
    if offlineOnly:
        panel.usernameField.text = "offline_test"
        panel.passwordField.text = "OfflineTest123"
        panel._submit()
        check(await waitUntil(func(): return not panel.busy), "Carga termina cuando el servicio no está disponible")
        check(panel.statusLabel.theme_type_variation == "ErrorLabel" and not panel.statusLabel.text.is_empty(), "Error de conexión visible sin bloquear la pantalla")
        await capture("offline")
        panel.showWelcome()
        panel._guest()
        check(plaza.jugador_nodo.habilitado and not state.tiene_jugador(), "Invitado puede pasear sin servicio de cuentas")
        print("AUTH_UI_OFFLINE failures=", failures)
        quit(0 if failures == 0 else 1)
        return
    panel.showForm("register")
    await settle()
    check(controlsFit(panel), "Registro cabe en 960 x 600")
    await capture("register")
    panel.usernameField.text = "PruebaÑandú"
    panel.passwordField.text = "corta"
    panel.confirmField.text = "corta"
    panel._submit()
    check(not panel.busy and panel.statusLabel.text.contains("8"), "Contraseña corta rechazada antes de enviar")
    panel.passwordField.text = "ñ".repeat(40)
    panel.confirmField.text = "ñ".repeat(40)
    panel._submit()
    check(not panel.busy and panel.statusLabel.text.contains("larga"), "Contraseña larga rechazada sin truncarla")
    panel.passwordField.text = "Invierno123"
    panel.confirmField.text = "OtraClave123"
    panel._submit()
    check(not panel.busy and panel.statusLabel.text.contains("no coinciden"), "Confirmación rechazada antes de enviar")
    await capture("confirmation-error")
    if render:
        for size in [Vector2i(1280, 720), Vector2i(1920, 1200)]:
            root.size = size
            await settle()
            var scale := root.get_screen_transform().get_scale()
            print("AUTH_WINDOW requested=", size, " actual=", root.size, " scale=", scale)
            check(is_equal_approx(scale.x, roundf(scale.x)) and controlsFit(panel), "Formulario y escala entera " + str(size))
        root.size = Vector2i(960, 600)
        await settle()
    var crypto := Crypto.new()
    var username := "gd_" + crypto.generate_random_bytes(8).hex_encode()
    var password := crypto.generate_random_bytes(18).hex_encode()
    var fixture := FileAccess.open("res://.tools/godot-auth-fixture.json", FileAccess.WRITE)
    fixture.store_string(JSON.stringify({"username": username}))
    fixture.close()
    panel.usernameField.text = username
    panel.passwordField.text = password
    panel.confirmField.text = password
    panel.submitButton.pressed.emit()
    check(panel.busy and panel.submitButton.disabled and not panel.usernameField.editable, "Envío único con campos y botones bloqueados")
    var registered := await waitUntil(func(): return state.tiene_jugador())
    check(registered, "Registro real entra a la plaza")
    if not registered:
        print("AUTH_UI_VALIDATION failures=", failures)
        quit(1)
        return
    var playerId: int = state.jugador_id
    check(state.jugador_nombre == username and state.monedas == 100 and plaza.jugador_nodo.habilitado and not panel.isOpen(), "Identidad confirmada y HUD con monedas del servidor")
    await capture("authenticated-plaza")
    plaza._mostrar_seleccion_jugador()
    await settle()
    await capture("account")
    panel._logout()
    check(await waitUntil(func(): return state.sessionToken.is_empty() and panel.mode == "welcome"), "Logout real vuelve a bienvenida")
    panel.showForm("register")
    panel.usernameField.text = username
    panel.passwordField.text = password
    panel.confirmField.text = password
    panel._submit()
    check(await waitUntil(func(): return not panel.busy), "Registro duplicado termina su estado de carga")
    check(panel.statusLabel.text.contains("ocupado") and not state.tiene_jugador(), "Nombre ocupado muestra un error claro")
    await capture("duplicate-user")
    panel.showForm("login")
    panel.usernameField.text = username
    panel.passwordField.text = "Incorrecta123"
    panel._submit()
    check(await waitUntil(func(): return not panel.busy), "Login inválido termina su estado de carga")
    check(panel.statusLabel.text.contains("contraseña") and not state.tiene_jugador(), "Credenciales inválidas muestran mensaje claro")
    await capture("invalid-login")
    panel.passwordField.text = password
    panel._submit()
    check(await waitUntil(func(): return state.tiene_jugador()), "Login real recupera la misma cuenta")
    check(state.jugador_id == playerId and state.monedas == 100, "Datos recuperados sin crear otro jugador")
    state.sessionExpiresAt = int(Time.get_unix_time_from_system()) - 1
    check(await waitUntil(func(): return state.sessionToken.is_empty()), "Caducidad local limpia la identidad")
    check(panel.mode == "welcome" and panel.isOpen(), "Sesión caducada permite volver a entrar o pasear")
    panel._guest()
    check(plaza.jugador_nodo.habilitado and not state.tiene_jugador(), "Paseo de invitado al finalizar")
    print("AUTH_UI_VALIDATION failures=", failures)
    quit(0 if failures == 0 else 1)
