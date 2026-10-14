shader_type canvas_item;
// Original PNGs remain intact. Discard extraction halos at render time.
void fragment() {
    vec4 pixel = COLOR;
    if (pixel.a < 0.45) { discard; }
    COLOR = vec4(pixel.rgb, 1.0);
}
