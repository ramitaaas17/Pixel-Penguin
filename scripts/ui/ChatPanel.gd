extends Control

const UI := preload("res://scripts/ui/PixelUI.gd")
var connection: Node
var panel: PanelContainer
var toggle: Button
var history: VBoxContainer
var scroll: ScrollContainer
var input: LineEdit
var send: Button
var status: Label
var unread := 0

func _ready() -> void:
    theme = UI.THEME
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    offset_left = 24
    offset_right = 444
    offset_top = -340
    offset_bottom = -62
    var column := VBoxContainer.new()
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(column)
    UI.full_rect(column)
    var spacer := Control.new()
    spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(spacer)
    toggle = UI.button("Chat de la plaza")
    toggle.name = "ToggleChat"
    toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    toggle.pressed.connect(_toggle)
    column.add_child(toggle)
    panel = UI.panel()
    panel.name = "ChatPanel"
    column.add_child(panel)
    var body := VBoxContainer.new()
    body.theme_type_variation = "TightColumn"
    panel.add_child(body)
    var header := HBoxContainer.new()
    body.add_child(header)
    status = UI.label(connection.statusText, "SecondaryLabel")
    status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status.clip_text = true
    status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    header.add_child(status)
    var retry := UI.button("Reconectar")
    retry.theme_type_variation = "SecondaryButton"
    retry.pressed.connect(connection.retry)
    header.add_child(retry)
    scroll = ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(0, 98)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    body.add_child(scroll)
    history = VBoxContainer.new()
    history.theme_type_variation = "TightColumn"
    history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(history)
    var row := HBoxContainer.new()
    body.add_child(row)
    input = LineEdit.new()
    input.name = "ChatInput"
    input.placeholder_text = "Escribe aquí..."
    input.max_length = 180
    input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    input.text_submitted.connect(func(_text): _sendMessage())
    row.add_child(input)
    send = UI.button("Enviar")
    send.pressed.connect(_sendMessage)
    row.add_child(send)
    connection.statusChanged.connect(_statusChanged)
    connection.historyChanged.connect(_rebuild)
    connection.messageReceived.connect(_message)
    EstadoJuego.sessionEnded.connect(func(_expired):
        panel.hide()
        input.text = ""
        input.release_focus()
        unread = 0
        toggle.text = "Chat de la plaza"
    )
    _statusChanged(connection.statusText)
    panel.visible = false
    _rebuild()

func _toggle() -> void:
    panel.visible = not panel.visible
    unread = 0
    toggle.text = "Cerrar chat" if panel.visible else "Chat de la plaza"
    if panel.visible and connection.online:
        input.grab_focus()
    else:
        input.release_focus()

func _statusChanged(text: String) -> void:
    status.text = text
    status.tooltip_text = text
    input.editable = connection.online
    send.disabled = not connection.online
    input.placeholder_text = "Escribe aquí..." if connection.online else "Inicia sesión para conversar"

func _rebuild() -> void:
    for child in history.get_children():
        history.remove_child(child)
        child.queue_free()
    for message in connection.messages:
        _addLine(message)
    if connection.messages.is_empty():
        history.add_child(UI.wrapped_label("Saluda a quienes lleguen a la plaza.", "SecondaryLabel"))
    _scrollBottom.call_deferred()

func _addLine(message: Dictionary) -> void:
    var line := UI.wrapped_label("%s: %s" % [str(message.name), str(message.text)], "SecondaryLabel")
    history.add_child(line)

func _message(_messageData: Dictionary) -> void:
    _rebuild()
    if not panel.visible:
        unread += 1
        toggle.text = "Chat de la plaza (%d)" % unread

func _scrollBottom() -> void:
    await get_tree().process_frame
    scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _sendMessage() -> void:
    var text := input.text.strip_edges()
    if not text.is_empty() and connection.sendChat(text):
        input.text = ""
        input.grab_focus()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        var focus := get_viewport().gui_get_focus_owner()
        if event.keycode == KEY_ESCAPE and panel.visible:
            panel.hide()
            input.release_focus()
            toggle.text = "Chat de la plaza"
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_ENTER and not (focus is LineEdit or focus is TextEdit) and connection.online and get_tree().current_scene.canInteract():
            panel.show()
            unread = 0
            toggle.text = "Cerrar chat"
            input.grab_focus()
            get_viewport().set_input_as_handled()
