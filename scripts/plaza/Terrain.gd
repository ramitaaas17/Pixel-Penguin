@tool
extends Node2D
# Reusable atlas tiles. A logical diamond is 32x16, stored in a 32x32 region.
const ATLAS := preload("res://assets/sprites/tileSet.png")
const RADIUS := Vector2(442, 190)
const CENTER := Vector2(0, 5)
const WALKS := [
    [Vector2(-328, -36), Vector2(-248, 4), Vector2(-142, 36), Vector2(-55, 65), Vector2(40, 76), Vector2(155, 42), Vector2(260, 2), Vector2(325, -36)],
    [Vector2(0, -143), Vector2(12, -80), Vector2(-8, -24), Vector2(-16, 52)],
    [Vector2(-20, 75), Vector2(-36, 129), Vector2(-12, 181), Vector2(18, 215)]
]
func _ready() -> void:
    _build()

func _build() -> void:
    for child in get_children():
        child.free()
    var tiles := TileSet.new()
    tiles.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
    tiles.tile_size = Vector2i(32, 16)
    var atlas := TileSetAtlasSource.new()
    atlas.texture = ATLAS
    atlas.texture_region_size = Vector2i(32, 32)
    for coord in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(5, 0)]:
        atlas.create_tile(coord)
    tiles.add_source(atlas, 0)
    var snow := TileMapLayer.new()
    snow.name = "Nieve"
    snow.tile_set = tiles
    snow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    var snow_material := ShaderMaterial.new()
    snow_material.shader = preload("res://assets/plaza/snow_surface.gdshader")
    snow.material = snow_material
    add_child(snow)
    var paving := TileMapLayer.new()
    paving.name = "Senderos"
    paving.tile_set = tiles
    paving.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(paving)
    for x in range(-32, 33):
        for y in range(-32, 33):
            var coord := Vector2i(x, y)
            var point := snow.map_to_local(coord)
            if not contains_ground(point):
                continue
            var snow_tile := Vector2i(2, 0)
            snow.set_cell(coord, 0, snow_tile)
            if on_path(point):
                paving.set_cell(coord, 0, Vector2i(5, 0))
    var details := Node2D.new()
    details.set_script(preload("res://scripts/plaza/SnowDetails.gd"))
    add_child(details)
    queue_redraw()

func contains_ground(point: Vector2) -> bool:
    var q := (point - CENTER) / RADIUS
    var ripple := 0.018 * sin(point.x * 0.027) + 0.012 * cos(point.y * 0.049)
    return q.length_squared() < 1.0 + ripple

func on_path(point: Vector2) -> bool:
    if ((point - Vector2(12, 50)) / Vector2(139, 78)).length_squared() < 1.0:
        return true
    for walk in WALKS:
        for i in range(walk.size() - 1):
            if Geometry2D.get_closest_point_to_segment(point, walk[i], walk[i + 1]).distance_to(point) < 35.0:
                return true
    return false

func _outline(offset: Vector2, expand: Vector2) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(96):
        var a := TAU * float(i) / 96.0
        var radius := RADIUS + expand
        var p := CENTER + Vector2(cos(a) * radius.x, sin(a) * radius.y) + offset
        points.append((p / 4.0).round() * 4.0)
    return points

func _draw() -> void:
    draw_colored_polygon(_outline(Vector2(10, 26), Vector2(10, 5)), Color("#769ba9"))
    draw_colored_polygon(_outline(Vector2(0, 15), Vector2(3, 2)), Color("#7eacbe"))
    draw_colored_polygon(_outline(Vector2(0, 6), Vector2(3, 2)), Color("#adcdd6"))
    draw_colored_polygon(_outline(Vector2.ZERO, Vector2(-2, -2)), Color("#e5f0f2"))
