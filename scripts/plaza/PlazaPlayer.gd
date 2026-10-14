extends "res://scripts/Pinguino.gd"
var ruta := PackedVector2Array()
var habilitado := false
func _unhandled_input(event: InputEvent) -> void:
    if not habilitado:
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        ir_a(get_global_mouse_position())

func ir_a(punto: Vector2) -> void:
    var plaza := get_tree().current_scene
    if plaza != null and plaza.has_method("ruta_hacia"):
        ruta = plaza.ruta_hacia(global_position, punto)
        if not ruta.is_empty() and global_position.distance_to(ruta[0]) < 6.0:
            ruta.remove_at(0)
        destino = punto
        moviendose = not ruta.is_empty()

func _physics_process(_delta: float) -> void:
    if not habilitado:
        velocity = Vector2.ZERO
        return
    while not ruta.is_empty() and global_position.distance_to(ruta[0]) < 3.0:
        ruta.remove_at(0)
    if ruta.is_empty():
        velocity = Vector2.ZERO
        moviendose = false
        animacion.stop()
        sprite.frame = 0
    else:
        velocity = global_position.direction_to(ruta[0]) * velocidad
        if absf(velocity.x) > 2.0:
            sprite.flip_h = velocity.x < 0
        if animacion.current_animation != "caminar" or not animacion.is_playing():
            animacion.play("caminar")
    move_and_slide()
