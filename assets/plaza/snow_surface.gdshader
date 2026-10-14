shader_type canvas_item;
// Keep the atlas diamond, remove the dirt wall from interior snow cells.
void fragment() {
    vec2 local = fract(UV * 8.0);
    float diamond = abs(local.x - 0.5) * 2.0 + abs(local.y - 0.5) * 4.0;
    if (diamond > 1.02) { discard; }
    float detail = dot(COLOR.rgb, vec3(0.333333));
    COLOR = vec4(vec3(0.89, 0.94, 0.95) + vec3(detail * 0.012), 1.0);
}
