@tool
extends Node2D
# Sparse, stable surface marks; no per-frame work and no extra textures.
func _draw() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 7823
    var terrain := get_parent()
    for i in range(420):
        var p := Vector2(rng.randf_range(-412, 412), rng.randf_range(-173, 178)).round()
        if not terrain.contains_ground(p) or terrain.on_path(p):
            continue
        if ((p - Vector2(0, 5)) / Vector2(405, 168)).length_squared() > 1.0:
            continue
        var c := Color("#f6f9f6") if i % 3 else Color("#cddfe5")
        draw_line(p, p + Vector2(rng.randi_range(2, 5), 0), c, 1)
        if i % 5 == 0:
            draw_line(p + Vector2(3, 2), p + Vector2(5, 2), c, 1)
