extends Control
# Original code-native 12x16 pixel arrow. It shares the game's viewport scale.
const PIXELS := [
    "X...........", "XX..........", "XOX.........", "XOOX........",
    "XOOOX.......", "XOOOOX......", "XOOOOOX.....", "XOOOOOOX....",
    "XOOOOOOOX...", "XOOOOXXXXX..", "XOOXOX......", "XOX.XOX.....",
    "XX..XOX.....", "X....XOX....", ".....XOX....", "......X....."
]
func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    top_level = true
    get_window().mouse_exited.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
    get_window().mouse_entered.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_HIDDEN)
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _process(_delta: float) -> void:
    var p := get_viewport().get_mouse_position().floor()
    visible = get_viewport_rect().has_point(p) and get_window().has_focus()
    if visible:
        position = p

func _draw() -> void:
    for y in range(PIXELS.size()):
        for x in range(PIXELS[y].length()):
            var value: String = PIXELS[y][x]
            if value == ".":
                continue
            draw_rect(Rect2(Vector2(x, y), Vector2.ONE), Color("#243d49") if value == "X" else Color("#f3f5ed"))

func _exit_tree() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
