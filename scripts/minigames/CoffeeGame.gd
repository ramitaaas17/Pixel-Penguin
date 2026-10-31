extends CanvasLayer
signal closed
const UI := preload("res://scripts/ui/PixelUI.gd")
const ART := preload("res://scripts/minigames/CoffeeArt.gd")
const RAIN := preload("res://scripts/minigames/CoffeeRain.gd")
const RULES := preload("res://scripts/minigames/CoffeeRules.gd")
const DIGITS := preload("res://scripts/minigames/PixelDigits.gd")
const MUSIC := preload("res://scripts/minigames/CoffeeMusic.gd")
const INGREDIENTS := ["Café", "Leche", "Chocolate", "Crema"]
const RECIPE_NAMES := ["Café con leche", "Chocolate nevado", "Moca del deshielo", "Café nube", "Chocolate doble"]
var state := "intro"
var rules: RefCounted
var plan: Dictionary = {}
var started_tick := 0
var practice := true
var claim_pending := false
var claim_inflight := false
var reward := 0
var closing := false
var rain: Control
var music: AudioStreamPlayer
var music_button: Button
var order_label: Label
var feedback: Label
var feedback_value: Control
var time_label: Control
var score_label: Control
var level_label: Control
var meter: ProgressBar
var cards: Array[PanelContainer] = []
var count_labels: Array[Control] = []
var start_button: Button
var close_button: Button
var frame: PanelContainer
var overlay: CenterContainer
var overlay_title: Label
var overlay_hint: Label
var reward_number: Control
var reward_row: HBoxContainer
var feedback_until := 0
var shown_recipe := -1
var shown_lost := 0
var shown_wrong := 0
var shown_served := 0
var shown_level := 1

func _ready() -> void:
    layer = 30
    name = "CoffeeMinigame"
    var backdrop := ColorRect.new()
    backdrop.color = Color("203744f4")
    backdrop.theme = UI.THEME
    add_child(backdrop)
    UI.full_rect(backdrop)
    var margin := MarginContainer.new()
    margin.theme_type_variation = "CoffeeWideMargin"
    backdrop.add_child(margin)
    UI.full_rect(margin)
    var center := CenterContainer.new()
    margin.add_child(center)
    frame = UI.panel("CoffeeFrame")
    frame.custom_minimum_size = Vector2(944, 584)
    center.add_child(frame)
    var body := VBoxContainer.new()
    body.theme_type_variation = "CoffeeColumn"
    body.alignment = BoxContainer.ALIGNMENT_CENTER
    frame.add_child(body)
    var header := HBoxContainer.new()
    body.add_child(header)
    var title := UI.label("CAFÉ DEL DESHIELO", "CoffeeTitle")
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    music_button = UI.button("Música: sí")
    music_button.theme_type_variation = "CoffeeQuietButton"
    music_button.pressed.connect(_toggleMusic)
    header.add_child(music_button)
    close_button = UI.button("Salir")
    close_button.theme_type_variation = "CoffeeQuietButton"
    close_button.pressed.connect(closeGame)
    header.add_child(close_button)
    var main := HBoxContainer.new()
    body.add_child(main)
    var sidebar := VBoxContainer.new()
    sidebar.custom_minimum_size.x = 218
    sidebar.theme_type_variation = "CoffeeColumn"
    main.add_child(sidebar)
    var top_stats := HBoxContainer.new()
    sidebar.add_child(top_stats)
    time_label = _stat(top_stats, "Tiempo", "60")
    level_label = _stat(top_stats, "Nivel", "1")
    score_label = _stat(sidebar, "Puntos", "0")
    order_label = UI.wrapped_label("Café con leche", "CoffeeSmall")
    order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    sidebar.add_child(order_label)
    for kind in range(4):
        var card := UI.panel("CoffeeRecipeCard")
        sidebar.add_child(card)
        var row := HBoxContainer.new()
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        card.add_child(row)
        var icon := TextureRect.new()
        icon.texture = ART.ingredientIcon(kind)
        icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
        icon.custom_minimum_size = Vector2(40, 40)
        row.add_child(icon)
        var column := VBoxContainer.new()
        column.theme_type_variation = "TightColumn"
        row.add_child(column)
        column.add_child(UI.label(INGREDIENTS[kind], "CoffeeSmall"))
        var count := _number("0/3")
        column.add_child(count)
        cards.append(card)
        count_labels.append(count)
    meter = ProgressBar.new()
    meter.custom_minimum_size.y = 8
    meter.show_percentage = false
    meter.max_value = 1
    meter.value = 1
    meter.theme_type_variation = "CoffeePatience"
    sidebar.add_child(meter)
    rain = RAIN.new()
    rain.custom_minimum_size = Vector2(670, 448)
    rain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rain.ingredient_clicked.connect(_pickDrop)
    main.add_child(rain)
    overlay = CenterContainer.new()
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rain.add_child(overlay)
    UI.full_rect(overlay)
    var modal := UI.panel("CoffeeFrame")
    modal.custom_minimum_size.x = 330
    overlay.add_child(modal)
    var intro := VBoxContainer.new()
    intro.theme_type_variation = "CoffeeColumn"
    modal.add_child(intro)
    overlay_title = UI.label("Atrapa y prepara", "CoffeeText")
    overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    intro.add_child(overlay_title)
    overlay_hint = UI.label("Haz clic en lo que cae.", "CoffeeSmall")
    overlay_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    intro.add_child(overlay_hint)
    reward_row = HBoxContainer.new()
    reward_row.alignment = BoxContainer.ALIGNMENT_CENTER
    intro.add_child(reward_row)
    reward_number = _number("0")
    reward_row.add_child(reward_number)
    reward_row.add_child(UI.label("monedas", "CoffeeSmall"))
    reward_row.hide()
    start_button = UI.button("¡A jugar!")
    start_button.theme_type_variation = "CoffeeButton"
    start_button.pressed.connect(startGame)
    intro.add_child(start_button)
    var footer := HBoxContainer.new()
    footer.alignment = BoxContainer.ALIGNMENT_CENTER
    body.add_child(footer)
    feedback_value = _number("-20")
    feedback_value.theme_type_variation = "CoffeeError"
    footer.add_child(feedback_value)
    feedback = UI.label("por ingrediente necesario perdido", "CoffeeSmall")
    footer.add_child(feedback)
    music = MUSIC.new()
    add_child(music)
    music_button.text = "Música: no" if music.muted else "Música: sí"
    _previewRecipe()
    start_button.grab_focus()
    if not EstadoJuego.pendingCoffee.is_empty() and EstadoJuego.tiene_jugador():
        _recoverPending()

func _number(text: String) -> Control:
    var number := DIGITS.new()
    number.text = text
    number.theme_type_variation = "CoffeeNumber"
    number.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    return number

func _stat(parent: Control, caption: String, value: String) -> Control:
    var plaque := UI.panel("ChatBubblePanel")
    plaque.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(plaque)
    var column := VBoxContainer.new()
    column.theme_type_variation = "TightColumn"
    plaque.add_child(column)
    var label := UI.label(caption, "CoffeeSmall")
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(label)
    var number := _number(value)
    column.add_child(number)
    return number

func _previewRecipe() -> void:
    for kind in range(4):
        cards[kind].visible = kind < 2
        count_labels[kind].text = "0/%d" % int(RULES.RECIPES[0][kind])

func startGame() -> void:
    if state in ["playing", "starting"] or claim_inflight:
        return
    if claim_pending:
        _claimReward()
        return
    practice = not EstadoJuego.tiene_jugador()
    if practice:
        _begin(RULES.practicePlan())
    else:
        state = "starting"
        start_button.disabled = true
        overlay_hint.text = "Preparando tu turno..."
        var weak: WeakRef = weakref(self)
        Api.startCoffeeGame(func(code: int, data):
            var game = weak.get_ref()
            if game == null or game.closing:
                return
            if code == 201 and data is Dictionary:
                game._begin(data)
            else:
                game.state = "intro"
                game.start_button.disabled = false
                game.overlay_hint.text = "No se pudo iniciar. Reintenta."
        )

func _begin(data: Dictionary) -> void:
    plan = data
    rules = RULES.new(data)
    state = "playing"
    shown_recipe = -1
    shown_lost = 0
    shown_wrong = 0
    shown_served = 0
    shown_level = 1
    reward = 0
    started_tick = Time.get_ticks_msec()
    rain.startPlan(plan)
    overlay.hide()
    start_button.disabled = false
    start_button.release_focus()
    music.startTune()
    _notice("Haz clic para completar el pedido.")
    _sync()

func elapsedNow() -> int:
    return mini(RULES.DURATION, maxi(rules.clock, Time.get_ticks_msec() - started_tick))

func advanceGame(at: int) -> void:
    if state != "playing":
        return
    rules.advance(at)
    rain.advanceTo(rules.clock, rules.cooldown == 0)
    _sync()
    if rules.clock >= RULES.DURATION:
        finishGame()

func _process(_delta: float) -> void:
    if state == "playing":
        advanceGame(elapsedNow())

func _pickDrop(id: int, _kind: int) -> void:
    if state != "playing":
        return
    if rules.click(id, elapsedNow()):
        rain.advanceTo(rules.clock, rules.cooldown == 0)
        _sync()

func _notice(text: String, error := false, value := "") -> void:
    feedback.text = text
    feedback.theme_type_variation = "CoffeeError" if error else "CoffeeSmall"
    feedback_value.text = value
    feedback_value.visible = not value.is_empty()
    feedback_value.theme_type_variation = "CoffeeError" if error else "CoffeeNumber"
    feedback_until = (rules.clock if rules != null else 0) + 1800

func _sync() -> void:
    time_label.text = str(int(ceilf(float(RULES.DURATION - rules.clock) / 1000)))
    score_label.text = str(rules.score)
    level_label.text = str(RULES.levelAt(rules.clock))
    order_label.text = RECIPE_NAMES[rules.recipe]
    var missing: Array = []
    var layers: Array = []
    for kind in range(4):
        var needed: int = RULES.RECIPES[rules.recipe][kind]
        var count := int(rules.collected[kind])
        cards[kind].visible = needed > 0
        count_labels[kind].text = "%d/%d" % [count, needed]
        cards[kind].theme_type_variation = "CoffeeRecipeDone" if count == needed else "CoffeeRecipeCard"
        missing.append(maxi(0, needed - count))
        if count > 0:
            layers.append(kind)
    rain.setMissing(missing)
    rain.backdrop.cup_steps = layers
    rain.backdrop.celebration = rules.cooldown > 0
    rain.backdrop.queue_redraw()
    meter.value = float(maxi(0, rules.deadline - rules.clock)) / 24000
    if rules.lost > shown_lost:
        _notice("Ingrediente perdido", true, "-20")
    elif rules.wrong > shown_wrong:
        _notice("Ese ingrediente no va", true, "-10")
    elif rules.served > shown_served:
        _notice("¡Bebida servida!")
    elif RULES.levelAt(rules.clock) > shown_level:
        _notice("¡Sube la velocidad!")
    elif rules.recipe_position != shown_recipe and shown_recipe >= 0:
        _notice("¡Nuevo pedido!")
    elif rules.clock > feedback_until:
        _notice("Haz clic para completar el pedido.")
    shown_lost = rules.lost
    shown_wrong = rules.wrong
    shown_served = rules.served
    shown_recipe = rules.recipe_position
    shown_level = RULES.levelAt(rules.clock)

func finishGame() -> void:
    if state != "playing":
        return
    rules.advance(RULES.DURATION)
    state = "results"
    rain.running = false
    rain.accepting = false
    rain.clearItems()
    _sync()
    overlay.show()
    overlay.move_to_front()
    overlay_title.text = "¡Turno terminado!"
    reward_row.show()
    reward_number.text = "0"
    start_button.text = "Otra partida"
    if practice:
        overlay_hint.text = "Con tu cuenta ganas monedas."
        _notice("Turno de práctica")
    else:
        EstadoJuego.pendingCoffee = {"run_id":plan.run_id, "actions":rules.actions.duplicate(true), "plan":plan}
        claim_pending = true
        _claimReward()
    start_button.grab_focus()

func _claimReward() -> void:
    if claim_inflight:
        return
    claim_inflight = true
    start_button.disabled = true
    overlay_hint.text = "Guardando recompensa..."
    var pending := EstadoJuego.pendingCoffee
    var weak: WeakRef = weakref(self)
    Api.finishCoffeeGame(str(pending.run_id), pending.actions, func(code: int, data):
        var game = weak.get_ref()
        if game != null and not game.closing:
            game._claimResult(code, data)
    )

func _claimResult(code: int, data) -> void:
    claim_inflight = false
    start_button.disabled = false
    if code == 200 and data is Dictionary:
        claim_pending = false
        reward = int(data.coins)
        reward_number.text = str(reward)
        rules.score = int(data.score)
        _sync()
        overlay_hint.text = "¡Recompensa guardada!"
        start_button.text = "Otra partida"
        _notice("Saldo actualizado")
    elif code in [400, 403, 404, 409]:
        claim_pending = false
        EstadoJuego.pendingCoffee = {}
        overlay_hint.text = "Este premio no está disponible."
        start_button.text = "Otra partida"
    else:
        overlay_hint.text = "No se guardó. Puedes reintentar."
        start_button.text = "Reintentar premio"

func _recoverPending() -> void:
    var pending := EstadoJuego.pendingCoffee
    practice = false
    plan = pending.plan
    rules = RULES.new(plan)
    for action in pending.actions:
        rules.click(int(action.drop_id), int(action.at_ms))
    rules.advance(RULES.DURATION)
    state = "results"
    rain.clearItems()
    _sync()
    overlay_title.text = "¡Turno terminado!"
    reward_row.show()
    claim_pending = true
    _claimReward()

func _toggleMusic() -> void:
    music.toggleMute()
    music_button.text = "Música: no" if music.muted else "Música: sí"

func closeGame() -> void:
    if closing:
        return
    closing = true
    state = "closed"
    music.stop()
    closed.emit()
    queue_free()

func _input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode == KEY_TAB:
        var buttons: Array[Button] = [music_button, close_button]
        if overlay.visible and not start_button.disabled:
            buttons.append(start_button)
        var current := buttons.find(get_viewport().gui_get_focus_owner())
        buttons[posmod(current + (-1 if event.shift_pressed else 1), buttons.size())].grab_focus()
    elif event.keycode == KEY_ESCAPE:
        closeGame()
    else:
        return
    get_viewport().set_input_as_handled()
