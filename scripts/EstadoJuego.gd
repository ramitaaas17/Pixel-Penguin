extends Node

signal jugador_seleccionado(id: int, nombre: String, monedas: int)
signal monedas_cambiaron(monedas: int)
signal sessionStarted
signal sessionEnded(expired: bool)

var jugador_id: int = -1
var jugador_nombre: String = ""
var monedas: int = 0
var pendingCoffee: Dictionary = {}
var sessionToken: String = ""
var sessionExpiresAt: int = 0

func _ready() -> void:
    var timer := Timer.new()
    timer.wait_time = 1.0
    timer.timeout.connect(func():
        if not sessionToken.is_empty() and sessionExpiresAt <= int(Time.get_unix_time_from_system()):
            clearSession(true)
    )
    add_child(timer)
    timer.start()

func tiene_jugador() -> bool:
    return not sessionToken.is_empty() and jugador_id > 0 and sessionExpiresAt > int(Time.get_unix_time_from_system())

func acceptSession(data: Dictionary) -> void:
    sessionToken = str(data.get("token", ""))
    sessionExpiresAt = int(data.get("expires_at", 0))
    var player: Dictionary = data.get("jugador", {})
    jugador_id = int(player.get("id", -1))
    jugador_nombre = str(player.get("nombre", ""))
    monedas = int(player.get("monedas", 0))
    if not tiene_jugador():
        clearSession(true)
        return
    jugador_seleccionado.emit(jugador_id, jugador_nombre, monedas)
    monedas_cambiaron.emit(monedas)
    sessionStarted.emit()

func clearSession(expired: bool = false) -> void:
    pendingCoffee = {}
    sessionToken = ""
    sessionExpiresAt = 0
    jugador_id = -1
    jugador_nombre = ""
    monedas = 0
    monedas_cambiaron.emit(0)
    sessionEnded.emit(expired)

func actualizar_monedas(nuevas_monedas: int) -> void:
    monedas = nuevas_monedas
    monedas_cambiaron.emit(monedas)
