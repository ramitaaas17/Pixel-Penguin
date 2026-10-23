extends Node2D

const SHADOW := preload("res://scripts/plaza/Shadow.gd")
const UI := preload("res://scripts/ui/PixelUI.gd")
var targetPosition := Vector2.ZERO
var sprite: Sprite2D
var moving := false
var clock := 0.0

func setup(template: Sprite2D, player: Dictionary) -> void:
    sprite = template.duplicate() as Sprite2D
    sprite.name = "Sprite2D"
    sprite.frame = 0
    add_child(sprite)
    var shadow := Node2D.new()
    shadow.set_script(SHADOW)
    shadow.size = Vector2(25, 9)
    shadow.position = Vector2(3, 0)
    shadow.z_index = -1
    add_child(shadow)
    var nameLabel := UI.label(str(player.name), "NameLabel")
    nameLabel.theme = UI.THEME
    nameLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    nameLabel.position = Vector2(-120, -62)
    nameLabel.size = Vector2(240, 22)
    add_child(nameLabel)
    applyState(player)
    position = targetPosition

func applyState(player: Dictionary) -> void:
    targetPosition = Vector2(float(player.x), float(player.y))
    moving = bool(player.get("moving", false))
    sprite.flip_h = bool(player.get("left", false))

func _process(delta: float) -> void:
    position = position.move_toward(targetPosition, 180.0 * delta)
    clock += delta
    sprite.frame = int(clock / 0.12) % 4 if moving else 0
