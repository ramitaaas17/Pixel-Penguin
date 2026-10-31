extends Node2D
const UI := preload("res://scripts/ui/PixelUI.gd")
const AUTH_PANEL := preload("res://scripts/ui/AuthPanel.gd")

var jugador_nodo: Node2D
var hud: CanvasLayer
var hud_label: Label
var seleccion_ui: CanvasLayer
var authPanel: Node

func _ready() -> void:
    jugador_nodo = get_node_or_null("CaminarDerecha")
    authPanel = AUTH_PANEL.new()
    authPanel.api = Api
    authPanel.sessionState = EstadoJuego
    authPanel.entered.connect(_pasear)
    authPanel.guestRequested.connect(_pasear)
    add_child(authPanel)
    EstadoJuego.sessionStarted.connect(_onSessionStarted)
    EstadoJuego.sessionEnded.connect(_onSessionEnded)
    _crear_hud()
    if EstadoJuego.tiene_jugador():
        _pasear()
    else:
        _mostrar_seleccion_jugador()

func _mostrar_seleccion_jugador() -> void:
    jugador_nodo.setInputEnabled(false)
    if EstadoJuego.tiene_jugador():
        authPanel.showAccount()
    else:
        authPanel.showWelcome()
    seleccion_ui = authPanel.windowLayer

func _pasear() -> void:
    if is_instance_valid(authPanel):
        authPanel.close()
    seleccion_ui = null
    jugador_nodo.setInputEnabled(true)
    _actualizar_hud()

func canInteract() -> bool:
    if is_instance_valid(authPanel) and authPanel.isOpen():
        return false
    for commerce in get_tree().get_nodes_in_group("commerce"):
        if is_instance_valid(commerce.panel_comercio):
            return false
    return true

func _onSessionStarted() -> void:
    _pasear()

func _onSessionEnded(expired: bool) -> void:
    for commerce in get_tree().get_nodes_in_group("commerce"):
        commerce._cerrar_panel()
    jugador_nodo.setInputEnabled(false)
    _actualizar_hud()
    authPanel.showWelcome("Tu sesión terminó. Vuelve a entrar." if expired else "Sesión cerrada. ¡Hasta pronto!")
    seleccion_ui = authPanel.windowLayer

func _crear_hud() -> void:
    hud = CanvasLayer.new()
    add_child(hud)
    var margin := MarginContainer.new()
    margin.theme_type_variation = "ScreenMargin"
    hud.add_child(margin)
    UI.full_rect(margin)
    hud_label = UI.label("")
    margin.add_child(hud_label)
    _actualizar_hud()
    EstadoJuego.monedas_cambiaron.connect(func(_value): _actualizar_hud())

func _actualizar_hud() -> void:
    hud_label.text = "%s · Monedas: %d" % [EstadoJuego.jugador_nombre, EstadoJuego.monedas] if EstadoJuego.tiene_jugador() else "Invitado · Paseo libre"
