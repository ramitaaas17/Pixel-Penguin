extends CharacterBody2D

@export var velocidad: float = 50.0
@export var radio_paseo: float = 60.0

const COLORES := [
	Color(1.0, 0.55, 0.55),
	Color(0.55, 0.7, 1.0),
	Color(0.6, 1.0, 0.6),
	Color(1.0, 0.85, 0.4),
	Color(0.85, 0.55, 1.0),
	Color(1.0, 0.65, 0.3),
	Color(0.4, 0.9, 0.9),
	Color(1.0, 0.55, 0.8),
]

const MENU_CAFETERIA := [
	{"producto": "Café", "precio": 15},
	{"producto": "Chocolate caliente", "precio": 20},
	{"producto": "Medialuna", "precio": 10},
]

var jugador_id: int = -1
var monedas: int = 0
var puntos_comercio: Array = []

var punto_base: Vector2
var destino: Vector2
var esperando: bool = true
var yendo_a_comprar: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var animacion: AnimationPlayer = $AnimationPlayer
@onready var etiqueta: Label = $Nombre
@onready var timer_paseo: Timer = Timer.new()
@onready var timer_compra: Timer = Timer.new()

var distancia_ventana: float = 0.0
var tiempo_ventana: float = 0.0

func set_datos(id: int, nombre: String, monedas_iniciales: int) -> void:
	jugador_id = id
	monedas = monedas_iniciales
	etiqueta.text = nombre
	sprite.modulate = COLORES[randi() % COLORES.size()]

func set_comercios(puntos: Array) -> void:
	puntos_comercio = puntos

func _ready() -> void:
	punto_base = position
	destino = position

	add_child(timer_paseo)
	timer_paseo.one_shot = true
	timer_paseo.timeout.connect(_elegir_destino)
	timer_paseo.start(randf_range(1.0, 4.0))

	add_child(timer_compra)
	timer_compra.one_shot = true
	timer_compra.timeout.connect(_ir_a_comprar)
	timer_compra.start(randf_range(6.0, 15.0))

func _elegir_destino() -> void:
	if yendo_a_comprar:
		return
	var angulo := randf() * TAU
	var radio := randf_range(15.0, radio_paseo)
	destino = punto_base + Vector2(cos(angulo), sin(angulo)) * radio
	esperando = false

func _ir_a_comprar() -> void:
	if puntos_comercio.is_empty() or jugador_id == -1 or yendo_a_comprar:
		timer_compra.start(randf_range(10.0, 20.0))
		return
	var elegido: Dictionary = puntos_comercio[randi() % puntos_comercio.size()]
	yendo_a_comprar = true
	destino = elegido["pos"] + Vector2(randf_range(-25.0, 25.0), randf_range(-10.0, 10.0))
	esperando = false

func _physics_process(delta: float) -> void:
	var direccion := destino - global_position
	if not esperando and direccion.length() > 6.0:
		direccion = direccion.normalized()
		velocity = direccion * velocidad
		sprite.flip_h = direccion.x < 0.0
		if not animacion.is_playing() or animacion.current_animation != "caminar":
			animacion.play("caminar")
	else:
		_llegar_y_reprogramar()

	var posicion_antes := global_position
	move_and_slide()

	if not esperando:
		distancia_ventana += posicion_antes.distance_to(global_position)
		tiempo_ventana += delta
		if tiempo_ventana >= 0.6:
			if distancia_ventana < 8.0:
				yendo_a_comprar = false
				_llegar_y_reprogramar()
			distancia_ventana = 0.0
			tiempo_ventana = 0.0

func _llegar_y_reprogramar() -> void:
	if not esperando:
		esperando = true
		distancia_ventana = 0.0
		tiempo_ventana = 0.0
		if yendo_a_comprar:
			yendo_a_comprar = false
			_realizar_compra()
		timer_paseo.start(randf_range(2.0, 5.0))
		timer_compra.start(randf_range(15.0, 30.0))
	velocity = Vector2.ZERO
	if animacion.is_playing():
		animacion.stop()
	sprite.frame = 0

func _realizar_compra() -> void:
	if jugador_id == -1:
		return
	if randf() < 0.5:
		_comprar_en_tienda()
	else:
		_comprar_en_cafeteria()

func _comprar_en_tienda() -> void:
	Api.tienda_listar(func(codigo, datos):
		if not is_instance_valid(self) or codigo != 200 or datos == null:
			return
		var candidatos: Array = datos.filter(func(p): return p["stock"] > 0 and p["precio"] <= monedas)
		if candidatos.is_empty():
			return
		var producto: Dictionary = candidatos[randi() % candidatos.size()]
		var nuevas_monedas: int = monedas - int(producto["precio"])
		var nuevo_stock: int = int(producto["stock"]) - 1
		Api.jugador_actualizar_monedas(jugador_id, nuevas_monedas, func(codigo_j, _datos_j):
			if codigo_j != 200 or not is_instance_valid(self):
				return
			monedas = nuevas_monedas
			Api.tienda_actualizar_stock(producto["id"], nuevo_stock, func(_cp, _dp): pass)
		)
	)

func _comprar_en_cafeteria() -> void:
	var candidatos: Array = MENU_CAFETERIA.filter(func(item): return item["precio"] <= monedas)
	if candidatos.is_empty():
		return
	var item: Dictionary = candidatos[randi() % candidatos.size()]
	var nuevas_monedas: int = monedas - int(item["precio"])
	Api.jugador_actualizar_monedas(jugador_id, nuevas_monedas, func(codigo_j, _datos_j):
		if codigo_j != 200 or not is_instance_valid(self):
			return
		monedas = nuevas_monedas
		Api.cafeteria_crear_pedido(item["producto"], 1, func(_cp, _dp): pass)
	)
