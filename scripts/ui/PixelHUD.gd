extends Control
const UI := preload("res://scripts/ui/PixelUI.gd")
var elegir: Button
var aviso: Label
var estado: Label
var notice_panel: PanelContainer

func _ready() -> void:
    theme = UI.THEME
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    UI.full_rect(self)
    var margin := MarginContainer.new()
    margin.theme_type_variation = "ScreenMargin"
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(margin)
    UI.full_rect(margin)
    var column := VBoxContainer.new()
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_child(column)
    var header := HBoxContainer.new()
    header.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(header)
    var plaque := UI.panel("PlaquePanel")
    plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
    plaque.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    header.add_child(plaque)
    var titles := VBoxContainer.new()
    titles.theme_type_variation = "TightColumn"
    titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
    plaque.add_child(titles)
    var heading := UI.label("PLAZA DEL DESHIELO", "HeadingLabel")
    heading.name = "Titulo"
    titles.add_child(heading)
    titles.add_child(UI.label("Un pequeño lugar para encontrarnos.", "SecondaryLabel"))
    estado = UI.label("", "SecondaryLabel")
    estado.visible = false
    titles.add_child(estado)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    header.add_child(spacer)
    elegir = UI.button("Elegir jugador")
    elegir.name = "ElegirJugador"
    elegir.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    header.add_child(elegir)
    var space := Control.new()
    space.size_flags_vertical = Control.SIZE_EXPAND_FILL
    space.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(space)
    var notice_center := CenterContainer.new()
    notice_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(notice_center)
    notice_panel = UI.panel("HintPanel")
    notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    notice_center.add_child(notice_panel)
    aviso = UI.label("")
    notice_panel.add_child(aviso)
    notice_panel.visible = false
    var footer := HBoxContainer.new()
    footer.name = "Instrucciones"
    footer.alignment = BoxContainer.ALIGNMENT_CENTER
    footer.theme_type_variation = "HintRow"
    footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(footer)
    for hint in [["CLIC", "para caminar"], ["E", "junto a una entrada"], ["ESC", "para cerrar"]]:
        var group := HBoxContainer.new()
        group.mouse_filter = Control.MOUSE_FILTER_IGNORE
        footer.add_child(group)
        var key := UI.panel("KeyPanel")
        key.mouse_filter = Control.MOUSE_FILTER_IGNORE
        group.add_child(key)
        key.add_child(UI.label(hint[0], "KeyLabel"))
        group.add_child(UI.label(hint[1], "SecondaryLabel"))

func show_notice(texto: String) -> void:
    aviso.text = texto
    notice_panel.visible = not texto.is_empty()
