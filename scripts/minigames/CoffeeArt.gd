extends Control
# Original artwork drawn on a two-pixel grid. No imported packs or fonts.
var cup_steps: Array = []
var beat := 0
var celebration := false
const INK := Color("293f48")
const WOOD := Color("ad724e")
const LIGHT := Color("f4edda")
const TEAL := Color("477b80")

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func box(x: float, y: float, w: float, h: float, color: Color) -> void:
    draw_rect(Rect2(x, y, w, h), color)

func outline(x: float, y: float, w: float, h: float, color: Color, edge := INK) -> void:
    box(x, y, w, h, edge)
    box(x + 1, y + 1, w - 2, h - 2, color)

func _draw() -> void:
    draw_set_transform(Vector2.ZERO, 0, Vector2(2, 2))
    var w := floorf(size.x / 2)
    var h := floorf(size.y / 2)
    # Snow-lit window, wallpaper, copper trim and tiny wall tiles.
    box(0, 0, w, h, Color("c8d8cd"))
    for x in range(0, int(w), 12):
        box(x, 0, 1, h - 25, Color("b8ccc1"))
    box(0, 0, w, 4, INK)
    box(0, 4, w, 2, Color("d7a264"))
    _window(w - 112, 12)
    _shelf(18, 19)
    # Alternating striped awning matches the café outside.
    for x in range(0, int(w), 18):
        var color := Color("aa4b45") if (x / 18) % 2 == 0 else LIGHT
        box(x, 6, 18, 7, color)
        box(x + 1, 13, 16, 2, color)
    # Worktop and cabinet fronts.
    box(0, h - 27, w, 5, INK)
    box(0, h - 26, w, 2, Color("d6aa71"))
    box(0, h - 22, w, 22, WOOD)
    for x in range(0, int(w), 52):
        outline(x + 3, h - 19, 46, 17, Color("935c43"))
        box(x + 8, h - 15, 33, 1, Color("b67d54"))
        box(x + 22, h - 13, 8, 2, Color("e1ba7f"))
    for i in range(int(w / 7)):
        var gx := (i * 37) % int(w - 8)
        box(gx, h - 8 + (i % 3) * 2, 5, 1, Color("a86d4b"))
    box(0, h - 2, w, 2, INK)
    _machine(26, h - 73)
    _jar(108, h - 44, Color("785046"))
    _jar(124, h - 48, Color("f1e8d2"))
    _penguin(w - 145, h - 73)
    # Central serving mat and porcelain cup.
    var cx := floorf(w * 0.51)
    box(cx - 29, h - 29, 58, 2, Color("567f7b"))
    box(cx - 25, h - 31, 50, 2, Color("e2d5ae"))
    _cup(cx - 12, h - 55)
    # Order rail, ticket, coffee beans and folded towel.
    outline(w - 54, h - 47, 37, 20, LIGHT)
    box(w - 51, h - 43, 30, 2, Color("aa4b45"))
    for i in range(3):
        box(w - 50, h - 38 + i * 3, 19 - i * 3, 1, Color("8a9c91"))
    box(153, h - 31, 17, 3, Color("e8d8b5"))
    box(154, h - 35, 15, 4, LIGHT)
    box(158, h - 35, 2, 7, Color("aa4b45"))
    if celebration:
        for i in range(9):
            var x := 150 + i * 12
            var y := 20 + ((i * 13 + beat * 5) % 28)
            box(x, y, 2, 3, Color("d8a451") if i % 2 == 0 else Color("f4edda"))

func _window(x: float, y: float) -> void:
    outline(x, y, 95, 43, WOOD)
    outline(x + 3, y + 3, 89, 37, Color("8db9c2"))
    box(x + 5, y + 26, 85, 12, Color("e5f1e9"))
    for i in range(4):
        var tx := x + 13 + i * 20
        box(tx + 4, y + 20, 2, 12, Color("77785e"))
        box(tx + 1, y + 22, 9, 5, Color("477d75"))
        box(tx + 3, y + 17, 5, 7, Color("477d75"))
        box(tx + 3, y + 16, 5, 2, LIGHT)
    for i in range(10):
        box(x + 8 + ((i * 17) % 77), y + 6 + ((i * 11 + beat) % 23), 1, 1, LIGHT)
    box(x + 46, y + 3, 3, 37, WOOD)
    box(x + 3, y + 23, 89, 2, WOOD)
    box(x - 2, y + 41, 99, 3, Color("e1c49a"))

func _shelf(x: float, y: float) -> void:
    box(x, y + 23, 113, 3, INK)
    box(x, y + 23, 113, 1, Color("ca9867"))
    for i in range(5):
        var sx := x + 5 + i * 19
        outline(sx, y + 11, 12, 12, LIGHT)
        outline(sx + 11, y + 14, 4, 6, LIGHT)
        box(sx + 2, y + 12, 8, 2, Color("986449"))
    box(x + 100, y + 16, 10, 7, Color("a65f48"))
    box(x + 103, y + 6, 2, 11, TEAL)
    box(x + 99, y + 8, 5, 3, TEAL)
    box(x + 105, y + 4, 4, 4, TEAL)

func _machine(x: float, y: float) -> void:
    outline(x, y, 65, 46, Color("a94c46"))
    box(x + 3, y + 3, 59, 2, Color("df9b72"))
    box(x + 2, y + 6, 2, 31, Color("c16853"))
    box(x + 61, y + 5, 2, 34, Color("773e3b"))
    outline(x + 6, y + 8, 53, 12, INK)
    for i in range(3):
        outline(x + 12 + i * 15, y + 11, 7, 6, Color("d6bd87"))
    box(x + 6, y + 22, 53, 19, Color("4a5b59"))
    box(x + 9, y + 23, 47, 2, Color("b4c7bc"))
    for sx in [x + 20, x + 43]:
        box(sx, y + 24, 3, 6, INK)
        box(sx - 3, y + 30, 9, 8, LIGHT)
        box(sx - 2, y + 30, 7, 2, Color("8c6048"))
    box(x + 5, y + 40, 55, 3, INK)
    for i in range(10):
        box(x + 8 + i * 5, y + 40, 2, 1, Color("8ca6a1"))
    box(x + 65, y + 12, 7, 2, INK)
    box(x + 70, y + 13, 2, 20, INK)
    box(x + 69, y + 31, 4, 3, Color("d5bf9b"))
    for i in range(3):
        box(x + 15 + i * 17, y - 4, 10, 4, LIGHT)
        box(x + 17 + i * 17, y - 5, 6, 1, LIGHT)

func _jar(x: float, y: float, color: Color) -> void:
    outline(x, y, 12, 17, color)
    box(x - 1, y - 2, 14, 3, Color("586d69"))
    box(x + 2, y + 5, 8, 6, LIGHT)
    box(x + 4, y + 7, 4, 2, color)

func _penguin(x: float, y: float) -> void:
    # A small café apron, toque and the plaza's navy-blue penguin palette.
    box(x + 8, y + 6, 20, 5, INK)
    box(x + 4, y + 11, 28, 22, INK)
    box(x, y + 29, 35, 19, INK)
    box(x + 6, y + 11, 24, 25, Color("384d8e"))
    box(x + 5, y + 11, 2, 16, Color("5365a3"))
    box(x + 29, y + 12, 2, 19, Color("273c72"))
    box(x + 3, y + 31, 29, 14, Color("384d8e"))
    box(x + 12, y + 15, 16, 20, LIGHT)
    box(x + 9, y + 30, 20, 17, LIGHT)
    box(x + 23, y + 17, 2, 3, INK)
    box(x + 23, y + 17, 1, 1, Color.WHITE)
    outline(x + 27, y + 23, 8, 5, Color("e3b254"))
    box(x + 12, y + 34, 16, 14, TEAL)
    box(x + 17, y + 39, 8, 6, Color("a8c0ad"))
    box(x + 7, y + 5, 23, 6, LIGHT)
    box(x + 5, y, 8, 7, LIGHT)
    box(x + 12, y - 3, 12, 10, LIGHT)
    box(x + 23, y + 1, 8, 7, LIGHT)
    box(x + 8, y + 9, 21, 2, Color("b2c6b7"))

func _cup(x: float, y: float) -> void:
    outline(x + 25, y + 6, 10, 13, LIGHT)
    box(x + 28, y + 9, 4, 7, INK)
    outline(x, y + 1, 27, 23, LIGHT)
    box(x + 2, y + 21, 23, 3, Color("b1c8bb"))
    box(x + 1, y, 25, 3, INK)
    box(x + 3, y + 2, 21, 3, Color("d8ddc8"))
    var colors := [Color("785046"), Color("f0d9a5"), Color("9c6651"), Color("faf0d5")]
    for i in range(cup_steps.size()):
        box(x + 3, y + 17 - i * 4, 21, 4, colors[int(cup_steps[i])])
    box(x + 10, y + 10, 7, 7, TEAL)
    box(x + 12, y + 8, 3, 11, TEAL)
    box(x - 4, y + 24, 35, 2, INK)
    box(x - 2, y + 23, 31, 1, LIGHT)
    if not cup_steps.is_empty():
        for i in range(3):
            var sy := y - 6 - (beat + i * 3) % 8
            box(x + 5 + i * 7, sy, 2, 4, Color("f1f3df"))

static func ingredientIcon(index: int, pixel_scale := 2) -> Texture2D:
    var patterns := [
        ["................", "......####......", "....##bbbb##....", "...#bllbbbbb#...", "..#bllbb#bbbb#..", "..#bbbb#bbbbb#..", "..#bbb#bbbbbb#..", "...#b#bbbbbb#...", "....##bbbb##....", "......####......"],
        ["....########....", "....#wwwwww#....", "....#wwwwww#....", "....#wwwwww#....", "....#wwwwww#....", "....#wwwwww#....", "....#wwwwww#....", ".....#wwww#.....", ".....#tttt#.....", "......####......"],
        ["...##########...", "...#bb#bb#bb#...", "...#bl#bl#bl#...", "...##########...", "...#bb#bb#bb#...", "...#bl#bl#bl#...", "...##########...", "...#ttwwttww#...", "...#wwttwwtt#...", "...##########..."],
        [".......w........", "......www.......", ".....wwwww......", "....wwwww#w.....", "...wwwwwwwww....", "....wwwwwww.....", "...#########....", "....#ttttt#.....", "....#ttttt#.....", ".....#####......"],
    ]
    var palette := {"#": INK, "b": Color("795044"), "l": Color("bd8860"), "w": LIGHT, "t": TEAL}
    var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
    image.fill(Color.TRANSPARENT)
    var pattern: Array = patterns[index]
    for y in range(pattern.size()):
        for x in range(pattern[y].length()):
            var pixel: String = pattern[y][x]
            if palette.has(pixel):
                image.set_pixel(x, y + 3, palette[pixel])
    image.resize(16 * pixel_scale, 16 * pixel_scale, Image.INTERPOLATE_NEAREST)
    return ImageTexture.create_from_image(image)
