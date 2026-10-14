extends "res://scripts/PinguinoNPC.gd"
var ruta := PackedVector2Array()
var ultimo_destino := Vector2(INF, INF)
func _physics_process(_delta: float) -> void:
    if esperando:
        velocity = Vector2.ZERO
        return
    var plaza := get_tree().current_scene
    if destino != ultimo_destino and plaza != null and plaza.has_method("ruta_hacia"):
        ultimo_destino = destino
        ruta = plaza.ruta_hacia(global_position, destino)
    while not ruta.is_empty() and global_position.distance_to(ruta[0]) < 4.0:
        ruta.remove_at(0)
    if ruta.is_empty():
        _llegar_y_reprogramar()
        animacion.stop()
        sprite.frame = 0
        return
    velocity = global_position.direction_to(ruta[0]) * velocidad
    if absf(velocity.x) > 2.0:
        sprite.flip_h = velocity.x < 0.0
    if not animacion.is_playing():
        animacion.play("caminar")
    move_and_slide()
