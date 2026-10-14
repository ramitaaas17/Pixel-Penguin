@tool
extends Node2D
@export var size := Vector2(40, 14):
    set(value):
        size = value
        queue_redraw()
@export var tint := Color(0.20, 0.29, 0.40, 0.18)
func _draw() -> void:
    var points := PackedVector2Array()
    for i in range(24):
        var angle := TAU * float(i) / 24.0
        points.append((Vector2(cos(angle), sin(angle)) * size * 0.5).round())
    draw_colored_polygon(points, tint)
