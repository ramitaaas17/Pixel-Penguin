extends Node

signal jugador_seleccionado(id: int, nombre: String, monedas: int)
signal monedas_cambiaron(monedas: int)

var jugador_id: int = -1
var jugador_nombre: String = ""
var monedas: int = 0

func tiene_jugador() -> bool:
	return jugador_id != -1

func seleccionar_jugador(id: int, nombre: String, monedas_iniciales: int) -> void:
	jugador_id = id
	jugador_nombre = nombre
	monedas = monedas_iniciales
	jugador_seleccionado.emit(id, nombre, monedas)

func actualizar_monedas(nuevas_monedas: int) -> void:
	monedas = nuevas_monedas
	monedas_cambiaron.emit(monedas)
