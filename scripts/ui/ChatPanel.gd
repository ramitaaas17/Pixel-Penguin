extends Control

const UI := preload("res://scripts/ui/PixelUI.gd")
var connection: Node
var panel: PanelContainer
var input: LineEdit
var send: Button
var retry: Button

func _ready() -> void:
    theme = UI.THEME
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    offset_left = 24
    offset_right = -24
    offset_top = -54
    offset_bottom = -8
    panel = UI.panel("ChatBubblePanel")
    panel.name = "ChatBar"
    add_child(panel)
    UI.full_rect(panel)
    var row := HBoxContainer.new()
    panel.add_child(row)
    input = LineEdit.new()
    input.name = "ChatInput"
    input.theme_type_variation = "ChatInput"
    input.placeholder_text = "Escribe aquí..."
    input.max_length = 180
    input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    input.text_submitted.connect(func(_text): _sendMessage())
    row.add_child(input)
    send = UI.button("Enviar")
    send.pressed.connect(_sendMessage)
    row.add_child(send)
    retry = UI.button("Reconectar")
    retry.pressed.connect(connection.retry)
    row.add_child(retry)
    connection.statusChanged.connect(_statusChanged)
    EstadoJuego.sessionEnded.connect(func(_expired):
        input.text = ""
        input.release_focus()
    )
    _statusChanged(connection.statusText)
    panel.visible = true

func _statusChanged(text: String) -> void:
    panel.tooltip_text = text
    retry.visible = not connection.online and EstadoJuego.tiene_jugador()
    input.editable = connection.online
    send.disabled = not connection.online
    input.placeholder_text = "Escribe aquí..." if connection.online else "Inicia sesión para conversar"

func _sendMessage() -> void:
    var text := input.text.strip_edges()
    if not text.is_empty() and connection.sendChat(text):
        input.text = ""
        input.grab_focus()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        var focus := get_viewport().gui_get_focus_owner()
        if event.keycode == KEY_ESCAPE and focus == input:
            input.release_focus()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_ENTER and not (focus is LineEdit or focus is TextEdit) and connection.online and get_tree().current_scene.canInteract():
            input.grab_focus()
            get_viewport().set_input_as_handled()
