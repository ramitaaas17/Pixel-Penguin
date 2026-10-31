extends Control
# Original 5×7 numeric glyphs: integer rectangles, no font rasterization.
const GLYPHS := {
    "0":["01110","10011","10101","10101","11001","10001","01110"],
    "1":["00100","01100","00100","00100","00100","00100","01110"],
    "2":["01110","10001","00001","00010","00100","01000","11111"],
    "3":["11110","00001","00001","01110","00001","00001","11110"],
    "4":["10010","10010","10010","11111","00010","00010","00010"],
    "5":["11111","10000","10000","11110","00001","00001","11110"],
    "6":["01110","10000","10000","11110","10001","10001","01110"],
    "7":["11111","00001","00010","00100","01000","01000","01000"],
    "8":["01110","10001","10001","01110","10001","10001","01110"],
    "9":["01110","10001","10001","01111","00001","00001","01110"],
    "/":["00001","00001","00010","00100","01000","10000","10000"],
    "-":["00000","00000","00000","11111","00000","00000","00000"],
    "+":["00000","00100","00100","11111","00100","00100","00000"],
}
var pixel_size := 5
var text := "0":
    set(value):
        text = value
        update_minimum_size()
        queue_redraw()
func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
func _get_minimum_size() -> Vector2:
    return Vector2(maxi(1, text.length()) * pixel_size * 6 - pixel_size, pixel_size * 7)
func _draw() -> void:
    var color := get_theme_color("font_color", "CoffeeError" if theme_type_variation == "CoffeeError" else "CoffeeNumber")
    var x := 0
    for character in text:
        if GLYPHS.has(character):
            var glyph: Array = GLYPHS[character]
            for row in range(7):
                for col in range(5):
                    if glyph[row][col] == "1":
                        draw_rect(Rect2(x + col * pixel_size, row * pixel_size, pixel_size, pixel_size), color)
        x += pixel_size * 6
