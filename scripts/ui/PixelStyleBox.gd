@tool
extends StyleBox
# Code-native pixel UI: fixed-width corners/borders, stretchable center.
# Equivalent to a 9-slice without importing or filtering a texture.
@export var fill := Color("#f3f5ed")
@export var border := Color("#294653")
@export var highlight := Color("#ffffff")
@export var shadow := Color("#203744")
@export var border_width := 2
@export var corner := 3
@export var depth := 2
@export var shift := 0
@export var focus_only := false

func _get_draw_rect(rect: Rect2) -> Rect2:
    return Rect2(rect.position, rect.size + Vector2(0, depth + shift))

func _draw(canvas: RID, rect: Rect2) -> void:
    var r := Rect2(rect.position.round(), rect.size.round())
    if focus_only:
        var color := border
        for p in [r.position, Vector2(r.end.x - 6, r.position.y), Vector2(r.position.x, r.end.y - 6), r.end - Vector2(6, 6)]:
            RenderingServer.canvas_item_add_rect(canvas, Rect2(p, Vector2(6, 2)), color)
            RenderingServer.canvas_item_add_rect(canvas, Rect2(p, Vector2(2, 6)), color)
        return
    if depth > 0:
        _pixel_rect(canvas, Rect2(r.position + Vector2(0, depth), r.size), corner, shadow)
    r.position.y += shift
    _pixel_rect(canvas, r, corner, border)
    var inside := r.grow(-border_width)
    _pixel_rect(canvas, inside, maxi(0, corner - border_width), fill)
    if highlight.a > 0:
        RenderingServer.canvas_item_add_rect(canvas, Rect2(inside.position + Vector2(corner, 0), Vector2(maxf(0, inside.size.x - corner * 2), 1)), highlight)

func _pixel_rect(canvas: RID, rect: Rect2, cut: int, color: Color) -> void:
    if color.a == 0 or rect.size.x <= 0 or rect.size.y <= 0:
        return
    var c := mini(cut, int(minf(rect.size.x, rect.size.y) / 2))
    RenderingServer.canvas_item_add_rect(canvas, Rect2(rect.position + Vector2(0, c), rect.size - Vector2(0, c * 2)), color)
    if c > 0:
        RenderingServer.canvas_item_add_rect(canvas, Rect2(rect.position + Vector2(c, 0), Vector2(rect.size.x - c * 2, c)), color)
        RenderingServer.canvas_item_add_rect(canvas, Rect2(rect.position + Vector2(c, rect.size.y - c), Vector2(rect.size.x - c * 2, c)), color)
