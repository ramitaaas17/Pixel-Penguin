extends Control

signal ingredient_clicked(drop_id: int, kind: int)
const UI := preload("res://scripts/ui/PixelUI.gd")
const RULES := preload("res://scripts/minigames/CoffeeRules.gd")
const ART := preload("res://scripts/minigames/CoffeeArt.gd")
var backdrop: Control
var active: Array[Button] = []
var effects: Array[Dictionary] = []
var icons: Array[Texture2D] = []
var required: Array = [3, 2, 0, 0]
var plan_drops: Array = []
var spawn_index := 0
var clock := 0
var accepting := false
var rng := RandomNumberGenerator.new()
var running := false
var spawn_clock := 0.0
var art_clock := 0.0
var speed := 46.0
var serial := 0

func _ready() -> void:
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_STOP
    rng.randomize()
    backdrop = ART.new()
    add_child(backdrop)
    UI.full_rect(backdrop)
    for kind in range(4):
        icons.append(ART.ingredientIcon(kind, 4))
    showDemo()

func showDemo() -> void:
    clearItems()
    running = false
    for kind in range(4):
        var item := spawnIngredient(kind)
        item.position.y = 32 + (kind % 2) * 44
        item.disabled = true
        item.modulate = Color.WHITE

func startPlan(plan: Dictionary) -> void:
    clearItems()
    plan_drops = plan.drops
    spawn_index = 0
    clock = 0
    running = true
    advanceTo(0, true)

func advanceTo(at: int, can_pick: bool) -> void:
    clock = at
    accepting = can_pick
    speed = RULES.SPEEDS[RULES.levelAt(at) - 1]
    while spawn_index < plan_drops.size() and int(plan_drops[spawn_index].at_ms) <= at:
        var drop: Dictionary = plan_drops[spawn_index]
        spawn_index += 1
        if int(drop.until_ms) > at:
            spawnIngredient(int(drop.kind), drop)
    for i in range(active.size() - 1, -1, -1):
        var item := active[i]
        var drop: Dictionary = item.get_meta("drop")
        if at >= int(drop.until_ms):
            active.remove_at(i)
            remove_child(item)
            item.queue_free()
        else:
            var distance := float(RULES.distanceAt(at) - RULES.distanceAt(int(drop.at_ms))) / 1000.0
            item.position.y = roundf((30 + distance) / 2) * 2
            item.disabled = not can_pick
    queue_redraw()

func clearItems() -> void:
    for item in active:
        if is_instance_valid(item):
            remove_child(item)
            item.queue_free()
    active.clear()
    effects.clear()

func setMissing(counts: Array) -> void:
    required = counts.duplicate()

func spawnIngredient(kind: int, drop: Dictionary = {}) -> Button:
    var item := UI.button("")
    item.theme_type_variation = "CoffeeDrop"
    item.name = "FallingIngredient%d" % serial
    serial += 1
    item.icon = icons[kind]
    item.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    item.custom_minimum_size = Vector2(72, 72)
    item.size = Vector2(72, 72)
    item.focus_mode = Control.FOCUS_NONE
    item.tooltip_text = ["Grano de café", "Leche", "Chocolate", "Crema"][kind]
    item.set_meta("kind", kind)
    item.set_meta("drop", drop)
    item.set_meta("fall_y", 30.0)
    item.set_meta("picked", false)
    var lane := size.x / 4.0
    item.position = Vector2(roundf(lane * (kind + 0.5) - 36 + rng.randi_range(-12, 12)), 30)
    item.pressed.connect(_pick.bind(item))
    add_child(item)
    active.append(item)
    return item

func _pick(item: Button) -> void:
    if not running or not accepting or not is_instance_valid(item) or bool(item.get_meta("picked")):
        return
    item.set_meta("picked", true)
    var kind := int(item.get_meta("kind"))
    var id := int(item.get_meta("drop").id)
    effects.append({"kind":kind, "from":item.position + Vector2(4, 4), "age":0.0, "accepted":int(required[kind]) > 0})
    active.erase(item)
    remove_child(item)
    item.queue_free()
    ingredient_clicked.emit(id, kind)
    queue_redraw()

func _process(delta: float) -> void:
    art_clock += delta
    if art_clock >= 0.2:
        art_clock = 0
        backdrop.beat += 1
        backdrop.queue_redraw()
    for i in range(effects.size() - 1, -1, -1):
        effects[i].age += delta
        if effects[i].age >= 0.35:
            effects.remove_at(i)
    queue_redraw()

func _draw() -> void:
    for effect in effects:
        var target := Vector2(size.x * 0.51 - 32, size.y - 120)
        var progress := minf(1, floorf(float(effect.age) / 0.05) * 0.05 / 0.3)
        var point: Vector2 = effect.from.lerp(target, progress) if effect.accepted else effect.from
        point = (point / 2).round() * 2
        if effect.accepted:
            draw_texture(icons[int(effect.kind)], point)
        else:
            for step in range(5):
                draw_rect(Rect2(point + Vector2(step * 4, step * 4), Vector2(4, 4)), Color("a34c42"))
                draw_rect(Rect2(point + Vector2(16 - step * 4, step * 4), Vector2(4, 4)), Color("a34c42"))
