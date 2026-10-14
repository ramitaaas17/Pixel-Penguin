extends Area2D
const UI := preload("res://scripts/ui/PixelUI.gd")
var conexion_monedas := Callable()

@export var tipo_comercio: String = ""  # "tienda", "cafeteria" o "" (sin comercio)

const MENU_CAFETERIA := [
	{"producto": "Café", "precio": 15},
	{"producto": "Chocolate caliente", "precio": 20},
	{"producto": "Medialuna", "precio": 10},
]

var raton_encima: bool = false
var pinguino_cerca: bool = false
var panel_comercio: CanvasLayer = null

@onready var animacion: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_mouse_entered() -> void:
	raton_encima = true
	_actualizar_animacion()

func _on_mouse_exited() -> void:
	raton_encima = false
	_actualizar_animacion()

func _on_body_entered(body: Node2D) -> void:
	pinguino_cerca = true
	_actualizar_animacion()
	if tipo_comercio != "":
		print("[", name, "] cuerpo cerca: ", body.name, " | tiene_jugador=", EstadoJuego.tiene_jugador())
		if EstadoJuego.tiene_jugador():
			_abrir_panel()

func _on_body_exited(_body: Node2D) -> void:
	pinguino_cerca = false
	_actualizar_animacion()
	_cerrar_panel()

func _actualizar_animacion() -> void:
	if raton_encima or pinguino_cerca:
		if not animacion.is_playing():
			animacion.play("activar")
	else:
		animacion.stop()
		animacion.seek(0.0, true)

func _abrir_panel() -> void:
	if panel_comercio != null:
		return
	var window := UI.modal(get_tree().current_scene, "Tienda" if tipo_comercio == "tienda" else "Cafetería", _cerrar_panel)
	panel_comercio = window.layer
	panel_comercio.name = "Comercio"
	var caja: VBoxContainer = window.body
	var monedas_label := UI.label("Tus monedas: %d" % EstadoJuego.monedas, "SecondaryLabel")
	caja.add_child(monedas_label)
	conexion_monedas = func(m):
		if is_instance_valid(monedas_label):
			monedas_label.text = "Tus monedas: %d" % m
	EstadoJuego.monedas_cambiaron.connect(conexion_monedas)
	var lista := UI.list_area(caja, 220)
	if tipo_comercio == "tienda":
		_cargar_productos_tienda(lista)
	else:
		_cargar_menu_cafeteria(lista)

func _cerrar_panel() -> void:
	if conexion_monedas.is_valid() and EstadoJuego.monedas_cambiaron.is_connected(conexion_monedas):
		EstadoJuego.monedas_cambiaron.disconnect(conexion_monedas)
	conexion_monedas = Callable()
	if is_instance_valid(panel_comercio):
		panel_comercio.queue_free()
	panel_comercio = null

func _cargar_productos_tienda(lista: VBoxContainer) -> void:
	for hijo in lista.get_children():
		hijo.queue_free()
	lista.add_child(UI.label("Cargando...", "SecondaryLabel"))
	Api.tienda_listar(func(codigo, datos):
		if not is_instance_valid(lista):
			return
		for hijo in lista.get_children():
			hijo.queue_free()
		if codigo != 200 or not datos is Array or datos.is_empty():
			lista.add_child(UI.label("No hay productos todavía.", "SecondaryLabel"))
			return
		for producto in datos:
			var texto := "%s · $%s · Stock: %d" % [producto["nombre"], str(producto["precio"]), producto["stock"]]
			UI.product_row(lista, texto, producto["stock"] <= 0 or EstadoJuego.monedas < producto["precio"],
				func(): _comprar_producto(producto, lista))
	)

func _comprar_producto(producto: Dictionary, lista: VBoxContainer) -> void:
	var nuevas_monedas: int = EstadoJuego.monedas - int(producto["precio"])
	var nuevo_stock: int = int(producto["stock"]) - 1
	print("[", name, "] comprando ", producto["nombre"], " jugador_id=", EstadoJuego.jugador_id)
	Api.jugador_actualizar_monedas(EstadoJuego.jugador_id, nuevas_monedas, func(codigo_j, _datos_j):
		print("[", name, "] respuesta actualizar monedas codigo=", codigo_j)
		if codigo_j != 200:
			return
		EstadoJuego.actualizar_monedas(nuevas_monedas)
		Api.tienda_actualizar_stock(producto["id"], nuevo_stock, func(_codigo_p, _datos_p):
			if is_instance_valid(lista):
				_cargar_productos_tienda(lista)
		)
	)

func _cargar_menu_cafeteria(lista: VBoxContainer) -> void:
	for hijo in lista.get_children():
		hijo.queue_free()
	for item in MENU_CAFETERIA:
		UI.product_row(lista, "%s · $%d" % [item["producto"], item["precio"]],
			EstadoJuego.monedas < item["precio"], func(): _comprar_cafeteria(item, lista))

func _comprar_cafeteria(item: Dictionary, lista: VBoxContainer) -> void:
	var nuevas_monedas: int = EstadoJuego.monedas - int(item["precio"])
	print("[", name, "] comprando ", item["producto"], " jugador_id=", EstadoJuego.jugador_id)
	Api.jugador_actualizar_monedas(EstadoJuego.jugador_id, nuevas_monedas, func(codigo_j, _datos_j):
		print("[", name, "] respuesta actualizar monedas codigo=", codigo_j)
		if codigo_j != 200:
			return
		EstadoJuego.actualizar_monedas(nuevas_monedas)
		Api.cafeteria_crear_pedido(item["producto"], 1, func(_codigo_p, _datos_p):
			if is_instance_valid(lista):
				_cargar_menu_cafeteria(lista)
		)
	)
