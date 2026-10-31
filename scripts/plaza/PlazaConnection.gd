extends Node

signal statusChanged(text: String)
signal rosterChanged
signal messageReceived(message: Dictionary)
signal historyChanged

var localPlayer: Node2D
var socket: WebSocketPeer
var online := false
var players: Dictionary = {}
var messages: Array[Dictionary] = []
var statusText := "Entra con tu cuenta para conversar."
var reconnectAt := 0.0
var retryDelay := 1.0
var authSent := false
var blocked := false
var openedAt := 0.0
var lastSequence := 0
var moveClock := 0.0
var lastPosition := Vector2.INF
var lastMoving := false
var lastLeft := false

func _ready() -> void:
    EstadoJuego.sessionStarted.connect(_start)
    EstadoJuego.sessionEnded.connect(_end)
    if EstadoJuego.tiene_jugador():
        _start()

func _exit_tree() -> void:
    _disconnect()

func _status(text: String) -> void:
    statusText = text
    statusChanged.emit(text)

func _disconnect() -> void:
    if socket != null:
        socket.close(1000, "Hasta pronto")
    socket = null
    online = false
    authSent = false
    players.clear()
    rosterChanged.emit()

func _start() -> void:
    _disconnect()
    messages.clear()
    historyChanged.emit()
    blocked = false
    retryDelay = 1.0
    reconnectAt = 0.0
    _connect()

func _end(_expired: bool) -> void:
    _disconnect()
    messages.clear()
    historyChanged.emit()
    _status("Entra con tu cuenta para conversar.")

func retry() -> void:
    if EstadoJuego.tiene_jugador():
        blocked = false
        _disconnect()
        _connect()

func _connect() -> void:
    var url := Api.getBaseUrl().replace("https://", "wss://").replace("http://", "ws://") + "/plaza"
    socket = WebSocketPeer.new()
    socket.inbound_buffer_size = 131072
    socket.outbound_buffer_size = 8192
    authSent = false
    openedAt = Time.get_ticks_msec() / 1000.0
    _status("Conectando con la plaza...")
    if socket.connect_to_url(url) != OK:
        _lost(-1)

func _lost(code: int) -> void:
    _disconnect()
    if code == 4001:
        blocked = true
        EstadoJuego.clearSession(true)
        return
    if code == 4009:
        blocked = true
        _status("Tu cuenta está en otra ventana. Pulsa Reconectar.")
        return
    reconnectAt = Time.get_ticks_msec() / 1000.0 + retryDelay
    retryDelay = minf(retryDelay * 2.0, 15.0)
    _status("Sin conexión. Intentando reconectar...")

func _process(delta: float) -> void:
    if not EstadoJuego.tiene_jugador() or blocked:
        return
    var now := Time.get_ticks_msec() / 1000.0
    if socket == null:
        if now >= reconnectAt:
            _connect()
        return
    socket.poll()
    var state := socket.get_ready_state()
    if state == WebSocketPeer.STATE_CLOSED:
        _lost(socket.get_close_code())
        return
    if not online and now - openedAt > 10.0:
        _lost(-1)
        return
    if state != WebSocketPeer.STATE_OPEN:
        return
    if not authSent:
        authSent = true
        _send({"type": "auth", "token": EstadoJuego.sessionToken})
    while socket != null and socket.get_available_packet_count() > 0:
        var data = JSON.parse_string(socket.get_packet().get_string_from_utf8())
        if data is Dictionary:
            _receive(data)
    if not online:
        return
    moveClock += delta
    if moveClock >= 0.12 and is_instance_valid(localPlayer):
        moveClock = 0.0
        var position := localPlayer.global_position
        var moving: bool = localPlayer.moviendose
        var left: bool = localPlayer.sprite.flip_h
        if position.distance_squared_to(lastPosition) > 0.25 or moving != lastMoving or left != lastLeft:
            _send({"type":"move", "x":position.x, "y":position.y, "moving":moving, "left":left})
            lastPosition = position
            lastMoving = moving
            lastLeft = left

func _send(data: Dictionary) -> bool:
    return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.send_text(JSON.stringify(data)) == OK

func sendChat(text: String) -> bool:
    return online and _send({"type":"chat", "text":text})

func _receive(data: Dictionary) -> void:
    match str(data.get("type", "")):
        "welcome":
            if int(data.get("selfId", -1)) != EstadoJuego.jugador_id:
                _lost(4001)
                return
            players.clear()
            for player in data.get("players", []):
                players[int(player.id)] = player
            messages.clear()
            lastSequence = 0
            for message in data.get("history", []):
                _appendMessage(message)
            online = true
            retryDelay = 1.0
            lastPosition = Vector2.INF
            var own: Dictionary = players.get(EstadoJuego.jugador_id, {})
            if not own.is_empty():
                _correctPosition(own)
            _status("En línea · %d en la plaza" % players.size())
            rosterChanged.emit()
            historyChanged.emit()
        "joined", "moved":
            var player: Dictionary = data.get("player", {})
            players[int(player.id)] = player
            rosterChanged.emit()
            if str(data.type) == "joined":
                _status("En línea · %d en la plaza" % players.size())
        "left":
            players.erase(int(data.get("playerId", -1)))
            rosterChanged.emit()
            _status("En línea · %d en la plaza" % players.size())
        "chat":
            var message: Dictionary = data.get("message", {})
            if _appendMessage(message):
                messageReceived.emit(message)
        "correction":
            _correctPosition(data.get("player", {}))
        "error":
            var notice := str(data.get("text", "No se pudo enviar el mensaje."))
            _status(notice)
            var scene := get_tree().current_scene
            if scene.has_method("mostrar_aviso"):
                scene.mostrar_aviso(notice)

func _correctPosition(player: Dictionary) -> void:
    if is_instance_valid(localPlayer):
        localPlayer.ruta.clear()
        localPlayer.global_position = Vector2(float(player.get("x", -32)), float(player.get("y", 148)))
        localPlayer.moviendose = false

func _appendMessage(message: Dictionary) -> bool:
    var sequence := int(message.get("sequence", 0))
    if sequence <= lastSequence:
        return false
    lastSequence = sequence
    messages.append(message)
    if messages.size() > 50:
        messages.pop_front()
    return true
