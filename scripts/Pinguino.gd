extends CharacterBody2D

@export var velocidad: float = 120.0

var destino: Vector2
var moviendose: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var animacion: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	destino = global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		destino = get_global_mouse_position()
		moviendose = true

func _physics_process(_delta: float) -> void:
	var direccion := destino - global_position
	if moviendose and direccion.length() > 4.0:
		direccion = direccion.normalized()
		velocity = direccion * velocidad
		sprite.flip_h = direccion.x < 0.0
		if not animacion.is_playing() or animacion.current_animation != "caminar":
			animacion.play("caminar")
	else:
		moviendose = false
		velocity = Vector2.ZERO
		if animacion.is_playing():
			animacion.stop()
		sprite.frame = 0
	move_and_slide()
