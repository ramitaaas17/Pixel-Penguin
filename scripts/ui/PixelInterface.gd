extends Node
const CURSOR := preload("res://scripts/ui/PixelCursor.gd")
func _ready() -> void:
    # Below the logical base size integer scaling would crop the UI.
    get_window().min_size = Vector2i(960, 600)
    if DisplayServer.get_name() == "headless":
        return
    var layer := CanvasLayer.new()
    layer.layer = 100
    layer.name = "CursorPixel"
    add_child(layer)
    var cursor := Control.new()
    cursor.set_script(CURSOR)
    layer.add_child(cursor)
