extends SceneTree
const RULES := preload("res://scripts/minigames/CoffeeRules.gd")
var failures := 0
func _initialize() -> void:
    run.call_deferred()
func check(ok: bool, text: String) -> void:
    print("PASS " if ok else "FAIL ", text)
    if not ok:
        failures += 1
func settle() -> void:
    await process_frame
    await process_frame
func press(code: int) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    Input.parse_input_event(event)
func click(control: Control) -> void:
    var point := control.get_global_rect().get_center()
    var motion := InputEventMouseMotion.new()
    motion.position = point
    motion.global_position = point
    Input.parse_input_event(motion)
    for down in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.position = point
        event.global_position = point
        event.pressed = down
        Input.parse_input_event(event)
func pick(game: Node, id: int, at: int) -> void:
    game.started_tick = Time.get_ticks_msec() - at
    game.advanceGame(at)
    await settle()
    for item in game.rain.active:
        if int(item.get_meta("drop").id) == id:
            click(item)
            await settle()
            return
    check(false, "Ingrediente visible para clic " + str(id))
func run() -> void:
    var fixture_path := "res://.tools/coffee-fixture.json"
    check(FileAccess.file_exists(fixture_path), "Fixture de reglas del servidor disponible")
    if FileAccess.file_exists(fixture_path):
        var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
        var replay := RULES.new(fixture.plan)
        var valid := true
        for action in fixture.actions:
            valid = replay.click(int(action.drop_id), int(action.at_ms)) and valid
        replay.advance(60000)
        var result: Dictionary = replay.result()
        var matching := valid
        for key in result:
            matching = matching and int(result[key]) == int(fixture.expected.get(key, -1))
        check(matching, "Godot y Go calculan idénticos puntos, pérdidas, niveles y monedas")
    var plaza: Node = load("res://scenes/plaza/Plaza.tscn").instantiate()
    root.add_child(plaza)
    current_scene = plaza
    await settle()
    plaza._pasear()
    var cafe: Node = plaza.get_node("Cafeteria")
    plaza.jugador_nodo.position = cafe.position + Vector2(0, 30)
    await create_timer(0.15).timeout
    await settle()
    check(cafe.pinguino_cerca, "Proximidad real a cafetería")
    press(KEY_E)
    await settle()
    var game: Node = cafe.panel_comercio
    check(is_instance_valid(game), "E abre el minijuego")
    if not is_instance_valid(game):
        quit(1)
        return
    check(not plaza.jugador_nodo.habilitado and not plaza.chatPanel.visible, "La partida bloquea movimiento y chat")
    var frame: Rect2 = game.frame.get_global_rect()
    check(frame.position.x >= 0 and frame.position.y >= 0 and frame.end.x <= 960 and frame.end.y <= 600 and frame.size.x >= 940, "Ventana ampliada dentro de 960 × 600")
    print("COFFEE_ARENA ", game.rain.get_global_rect(), " SCORE ", game.score_label.get_global_rect())
    check(game.rain.size.y == 448 and game.rain.size.x >= 670, "Área de caída de 448 px de alto, separada del pedido")
    check(game.count_labels[0].GLYPHS.has("0") and game.count_labels[0].pixel_size == 5, "Números con glifos pixelados propios sin rasterizado de fuente")
    check(game.music.stream.get_length() > 10 and game.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Música original cargada con repetición")
    if "--render-coffee" in OS.get_cmdline_user_args():
        await capture("intro")
        root.size = Vector2i(1920, 1200)
        await settle()
        await capture("intro-2x")
        root.size = Vector2i(960, 600)
        await settle()
    click(game.start_button)
    await settle()
    game.set_process(false)
    check(game.state == "playing" and game.practice, "Invitado juega en modo práctica sin cobros ficticios")
    var muted: bool = game.music.muted
    game._toggleMusic()
    check(game.music.muted != muted and (game.music.muted or game.music.playing), "Botón de música controla audio")
    game._toggleMusic()
    await pick(game, 1, 100)
    await pick(game, 0, 120)
    check(game.rules.collected == [1, 1, 0, 0], "Clics reales recogen leche y café sin orden fijo")
    await pick(game, 4, 2700)
    await pick(game, 8, 5300)
    await pick(game, 5, 5400)
    check(game.rules.served == 1 and game.rules.score > 100, "Cantidades completas sirven una bebida y suman puntos")
    if "--render-coffee" in OS.get_cmdline_user_args():
        await capture("served")
    var score: int = game.rules.score
    game._pickDrop(5, 1)
    check(game.rules.score == score, "Clic duplicado no vuelve a pagar el pedido")
    game.advanceGame(6500)
    var lost: int = game.rules.lost
    for drop in game.plan.drops:
        var kind := int(drop.kind)
        if int(drop.until_ms) > game.rules.clock and int(drop.until_ms) < 14000 and game.rules.RECIPES[game.rules.recipe][kind] > 0 and not game.rules.clicked.has(int(drop.id)):
            game.advanceGame(int(drop.until_ms))
            break
    check(game.rules.lost > lost and game.rules.score <= score - 20, "Dejar pasar material necesario resta puntos")
    for at in [15000, 30000, 45000]:
        game.advanceGame(at)
        check(game.rain.speed == RULES.SPEEDS[RULES.levelAt(at) - 1] and game.level_label.text == str(RULES.levelAt(at)), "Velocidad y número de nivel progresivos: " + str(RULES.levelAt(at)))
    if "--render-coffee" in OS.get_cmdline_user_args():
        await capture("playing")
    game.advanceGame(60000)
    await settle()
    check(game.state == "results" and game.rain.active.is_empty() and game.reward == 0, "Fin de práctica muestra resultado sin modificar monedas")
    if "--render-coffee" in OS.get_cmdline_user_args():
        await capture("results")
    click(game.start_button)
    await settle()
    check(game.rules.score == 0 and game.rules.lost == 0 and game.rules.clock < 1000, "Repetir reinicia puntos, pérdidas y nivel")
    press(KEY_ESCAPE)
    await settle()
    check(cafe.panel_comercio == null and plaza.jugador_nodo.habilitado and plaza.chatPanel.visible, "Salir restaura plaza y chat")
    print("COFFEE_VALIDATION failures=", failures)
    quit(0 if failures == 0 else 1)
func capture(stage: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://docs/minigames/coffee-%s.png" % stage)
