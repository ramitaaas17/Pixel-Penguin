extends PanelContainer

const UI := preload("res://scripts/ui/PixelUI.gd")
var target: Node2D
var textLabel: Label
var remaining := 0.0

func _ready() -> void:
    theme = UI.THEME
    theme_type_variation = "ChatBubblePanel"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = 20
    custom_minimum_size = Vector2(48, 0)
    textLabel = UI.label("", "ChatBubbleLabel")
    textLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(textLabel)
    hide()

func showMessage(text: String) -> void:
    # Medir líneas explícitas evita el ciclo entre autowrap y el mínimo del panel.
    var font := textLabel.get_theme_font("font")
    var fontSize := textLabel.get_theme_font_size("font_size")
    var lines := PackedStringArray()
    var line := ""
    for word in text.split(" ", false):
        var candidate := word if line.is_empty() else line + " " + word
        if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x <= 168:
            line = candidate
            continue
        if not line.is_empty():
            lines.append(line)
        line = ""
        for character in word:
            if not line.is_empty() and font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize).x > 168:
                lines.append(line)
                line = ""
            line += character
    if not line.is_empty():
        lines.append(line)
    textLabel.text = "\n".join(lines)
    remaining = clampf(3.0 + text.length() * 0.07, 4.0, 14.0)
    reset_size()
    reset_size.call_deferred()
    show()

func _process(delta: float) -> void:
    if not is_instance_valid(target):
        queue_free()
        return
    if not visible:
        return
    remaining -= delta
    if remaining <= 0.0:
        hide()
        return
    var head := target.get_global_transform_with_canvas() * Vector2(0, -48)
    var bounds := get_viewport_rect().size
    position = Vector2(clampf(head.x - size.x / 2.0, 8, maxf(8, bounds.x - size.x - 8)), clampf(head.y - size.y, 8, maxf(8, bounds.y - size.y - 8))).round()
