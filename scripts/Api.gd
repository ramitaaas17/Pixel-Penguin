extends Node

const BASE_URL := "http://localhost:8000"

func _peticion(metodo: int, ruta: String, cuerpo, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_resultado: int, codigo: int, _encabezados: PackedStringArray, cuerpo_respuesta: PackedByteArray):
		http.queue_free()
		var datos = null
		var texto: String = cuerpo_respuesta.get_string_from_utf8()
		if texto != "":
			var json := JSON.new()
			if json.parse(texto) == OK:
				datos = json.data
		callback.call(codigo, datos)
	)
	var encabezados := ["Content-Type: application/json"]
	var cuerpo_texto := ""
	if cuerpo != null:
		cuerpo_texto = JSON.stringify(cuerpo)
	var error := http.request(BASE_URL + ruta, encabezados, metodo, cuerpo_texto)
	if error != OK:
		http.queue_free()
		callback.call(-1, null)

func jugadores_listar(callback: Callable) -> void:
	_peticion(HTTPClient.METHOD_GET, "/jugadores", null, callback)

func jugador_actualizar_monedas(id: int, monedas: int, callback: Callable) -> void:
	_peticion(HTTPClient.METHOD_PUT, "/jugadores/%d" % id, {"monedas": monedas}, callback)

func tienda_listar(callback: Callable) -> void:
	_peticion(HTTPClient.METHOD_GET, "/tienda", null, callback)

func tienda_actualizar_stock(id: int, stock: int, callback: Callable) -> void:
	_peticion(HTTPClient.METHOD_PUT, "/tienda/%d" % id, {"stock": stock}, callback)

func cafeteria_crear_pedido(producto: String, cantidad: int, callback: Callable) -> void:
	_peticion(HTTPClient.METHOD_POST, "/cafeteria", {"producto": producto, "cantidad": cantidad}, callback)
