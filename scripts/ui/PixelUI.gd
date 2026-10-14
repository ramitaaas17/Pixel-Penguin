extends RefCounted
const THEME := preload("res://assets/ui/pixel_theme.tres")
const BUTTON := preload("res://scenes/ui/PixelButton.tscn")

static func label(texto: String, tipo := "Label") -> Label:
    var result := Label.new()
    result.text = texto
    result.theme_type_variation = tipo
    result.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return result

static func button(texto: String) -> Button:
    var result := BUTTON.instantiate() as Button
    result.text = texto
    return result

static func panel(tipo := "PanelContainer") -> PanelContainer:
    var result := PanelContainer.new()
    result.theme_type_variation = tipo
    return result

static func full_rect(control: Control) -> void:
    control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func modal(parent: Node, titulo: String, close_action: Callable = Callable()) -> Dictionary:
    var layer := CanvasLayer.new()
    layer.layer = 10
    parent.add_child(layer)
    var backdrop := ColorRect.new()
    backdrop.color = Color(0.09, 0.16, 0.20, 0.62)
    backdrop.theme = THEME
    layer.add_child(backdrop)
    full_rect(backdrop)
    var margin := MarginContainer.new()
    margin.theme_type_variation = "ScreenMargin"
    backdrop.add_child(margin)
    full_rect(margin)
    var center := CenterContainer.new()
    margin.add_child(center)
    var frame := panel()
    frame.name = "PixelPanel"
    frame.custom_minimum_size = Vector2(520, 0)
    center.add_child(frame)
    var body := VBoxContainer.new()
    frame.add_child(body)
    var header := HBoxContainer.new()
    body.add_child(header)
    var heading := label(titulo, "TitleLabel")
    heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(heading)
    if close_action.is_valid():
        var close := button("X")
        close.name = "Cerrar"
        close.tooltip_text = "Cerrar · ESC"
        close.pressed.connect(close_action)
        header.add_child(close)
    return {"layer": layer, "body": body, "panel": frame}

static func list_area(parent: Control, height := 144.0) -> VBoxContainer:
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(0, height)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(scroll)
    var list := VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(list)
    return list

static func wrapped_label(texto: String, tipo := "Label") -> Label:
    var result := label(texto, tipo)
    result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return result

static func product_row(parent: Control, texto: String, disabled: bool, action: Callable) -> Button:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var info := wrapped_label(texto)
    row.add_child(info)
    var buy := button("Comprar")
    buy.disabled = disabled
    buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    buy.pressed.connect(action)
    row.add_child(buy)
    return buy
