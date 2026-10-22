extends "res://scripts/EdificioAnimado.gd"
@export var titulo := ""
@export var fotogramas := 1
@export var fps := 6.0
@export var animado := false
var reloj := 0.0

func _ready() -> void:
    super._ready()
    $Indicacion.size = $Indicacion.get_combined_minimum_size()
    $Indicacion.position = Vector2(-floorf($Indicacion.size.x / 2.0), 12)
    $Indicacion.visible = false
    set_process(animado)

func _process(delta: float) -> void:
    reloj += delta
    $Sprite2D.frame = int(reloj * fps) % fotogramas

func _on_body_entered(body: Node2D) -> void:
    if not body.is_in_group("jugador_local"):
        return
    pinguino_cerca = true
    $Indicacion.visible = not titulo.is_empty()

func _on_body_exited(body: Node2D) -> void:
    if not body.is_in_group("jugador_local"):
        return
    pinguino_cerca = false
    $Indicacion.visible = false
    _cerrar_panel()

func _actualizar_animacion() -> void:
    # Keep building colors steady; feedback belongs at the entrance.
    pass

func _unhandled_key_input(event: InputEvent) -> void:
    var scene := get_tree().current_scene
    var focusOwner := get_viewport().gui_get_focus_owner()
    if focusOwner is LineEdit or focusOwner is TextEdit:
        return
    if scene.has_method("canInteract") and not scene.canInteract():
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and pinguino_cerca:
        if tipo_comercio != "" and EstadoJuego.tiene_jugador():
            _abrir_panel()
        else:
            var plaza := get_tree().current_scene
            if plaza.has_method("mostrar_aviso"):
                plaza.mostrar_aviso("Entra con tu cuenta para consultar el comercio." if tipo_comercio != "" else "Un lugar para encontrarnos.")
        get_viewport().set_input_as_handled()
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        _cerrar_panel()

func _abrir_panel() -> void:
    if panel_comercio != null:
        return
    super._abrir_panel()
    var jugador := get_tree().current_scene.get_node_or_null("CaminarDerecha")
    if jugador:
        jugador.ruta.clear()

