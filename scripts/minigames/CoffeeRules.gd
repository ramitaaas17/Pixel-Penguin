extends RefCounted
# Kept in parity with platform/coffeegame/rules.go. Server replays the same log.
const DURATION := 60000
const SPEEDS := [42, 56, 70, 86]
const RECIPES := [[3, 2, 0, 0], [0, 2, 3, 1], [2, 2, 2, 0], [3, 1, 0, 2], [0, 2, 4, 0]]
var plan: Dictionary
var score := 0
var served := 0
var lost := 0
var wrong := 0
var combo := 0
var missed_orders := 0
var collected: Array = [0, 0, 0, 0]
var recipe_position := 0
var recipe := 0
var clock := 0
var deadline := 24000
var cooldown := 0
var expired := 0
var expirations: Array = []
var clicked: Dictionary = {}
var drops: Dictionary = {}
var actions: Array = []

static func levelAt(at: int) -> int:
    return mini(4, int(at / 15000) + 1)

static func distanceAt(at: int) -> int:
    var total := 0
    for i in range(4):
        var span := maxi(0, mini(15000, at - i * 15000)) if i < 3 else maxi(0, at - 45000)
        total += span * SPEEDS[i]
    return total

static func practicePlan() -> Dictionary:
    var recipes: Array = [0]
    for i in range(63):
        var next := randi_range(0, 3)
        if next >= int(recipes[-1]):
            next += 1
        recipes.append(next)
    var items: Array = []
    for i in range(93):
        var at := 0 if i < 4 else i * 650
        if at >= DURATION:
            break
        var target := distanceAt(at) + 338000
        var until := 0
        for stage in range(4):
            if target <= distanceAt((stage + 1) * 15000) or stage == 3:
                until = stage * 15000 + int(ceilf(float(target - distanceAt(stage * 15000)) / SPEEDS[stage]))
                break
        items.append({"id":i, "kind":i % 4, "at_ms":at, "until_ms":until})
    return {"run_id":"", "duration_ms":DURATION, "recipes":recipes, "drops":items}

func _init(data: Dictionary) -> void:
    plan = data
    recipe = int(plan.recipes[0])
    expirations = plan.drops.duplicate()
    expirations.sort_custom(func(a: Dictionary, b: Dictionary):
        return int(a.id) < int(b.id) if int(a.until_ms) == int(b.until_ms) else int(a.until_ms) < int(b.until_ms)
    )
    for drop in plan.drops:
        drops[int(drop.id)] = drop

func _nextOrder() -> void:
    recipe_position += 1
    recipe = int(plan.recipes[recipe_position % plan.recipes.size()])
    collected = [0, 0, 0, 0]
    deadline = clock + 24000
    cooldown = 0

func advance(to: int) -> void:
    to = mini(DURATION, maxi(to, clock))
    while true:
        var next: int = cooldown if cooldown > 0 else deadline
        if expired < expirations.size():
            next = mini(next, int(expirations[expired].until_ms))
        if next > to:
            break
        clock = next
        if cooldown > 0 and next == cooldown:
            _nextOrder()
        if cooldown == 0 and next == deadline:
            missed_orders += 1
            combo = 0
            _nextOrder()
        while expired < expirations.size() and int(expirations[expired].until_ms) == next:
            var drop: Dictionary = expirations[expired]
            expired += 1
            var kind := int(drop.kind)
            if not clicked.has(int(drop.id)) and cooldown == 0 and int(collected[kind]) < int(RECIPES[recipe][kind]):
                score = maxi(0, score - 20)
                lost += 1
                combo = 0
    clock = to

func click(id: int, at: int) -> bool:
    if at < clock or at < 0 or at >= DURATION:
        return false
    advance(at)
    if not drops.has(id) or clicked.has(id) or cooldown > 0:
        return false
    var drop: Dictionary = drops[id]
    if at < int(drop.at_ms) or at >= int(drop.until_ms):
        return false
    clicked[id] = true
    actions.append({"drop_id":id, "at_ms":at})
    var kind := int(drop.kind)
    var needed: Array = RECIPES[recipe]
    if int(collected[kind]) >= int(needed[kind]):
        if int(needed[kind]) == 0:
            score = maxi(0, score - 10)
            wrong += 1
            combo = 0
        return true
    collected[kind] = int(collected[kind]) + 1
    if collected == needed:
        combo += 1
        served += 1
        score += 100 + (levelAt(clock) - 1) * 25 + mini(combo - 1, 5) * 25 + int(maxi(0, deadline - clock) / 1000) * 2
        cooldown = clock + 900
    return true

func result() -> Dictionary:
    return {"balance":0, "score":score, "coins":mini(50, int(score / 100)), "served":served, "lost":lost, "wrong":wrong, "level":levelAt(clock)}
