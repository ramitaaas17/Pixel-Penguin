extends Node

const BASE_URL := "http://localhost:8000"

func getBaseUrl() -> String:
    if OS.has_feature("web"):
        return str(JavaScriptBridge.eval("window.location.origin"))
    return BASE_URL

func _peticion(metodo: int, ruta: String, cuerpo, callback: Callable) -> void:
    var requestToken := EstadoJuego.sessionToken
    var http := HTTPRequest.new()
    http.timeout = 10.0
    add_child(http)
    http.request_completed.connect(func(_resultado: int, codigo: int, _encabezados: PackedStringArray, cuerpo_respuesta: PackedByteArray):
        http.queue_free()
        var datos = null
        var texto: String = cuerpo_respuesta.get_string_from_utf8()
        if texto != "":
            var json := JSON.new()
            if json.parse(texto) == OK:
                datos = json.data
        if codigo == 401 and ruta not in ["/auth/login", "/auth/register", "/auth/logout"] and not requestToken.is_empty() and requestToken == EstadoJuego.sessionToken:
            EstadoJuego.clearSession(true)
        if callback.is_valid():
            callback.call(codigo, datos)
    )
    var encabezados := ["Content-Type: application/json"]
    if not requestToken.is_empty():
        encabezados.append("Authorization: Bearer " + requestToken)
    var cuerpo_texto := ""
    if cuerpo != null:
        cuerpo_texto = JSON.stringify(cuerpo)
    var error := http.request(getBaseUrl() + ruta, encabezados, metodo, cuerpo_texto)
    if error != OK:
        http.queue_free()
        if callback.is_valid():
            callback.call(-1, null)

func jugadores_listar(callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_GET, "/jugadores", null, callback)

func jugador_actualizar_monedas(id: int, monedas: int, callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_PUT, "/jugadores/%d" % id, {"monedas": monedas}, callback)

func tienda_listar(callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_GET, "/tienda", null, callback)

func tienda_actualizar_stock(id: int, stock: int, callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_PUT, "/tienda/%d" % id, {"stock": stock}, callback)

func cafeteria_crear_pedido(producto: String, cantidad: int, callback: Callable, playerId: int = 0) -> void:
    _peticion(HTTPClient.METHOD_POST, "/cafeteria", {"producto": producto, "cantidad": cantidad, "jugador_id": playerId}, callback)

func registerAccount(username: String, password: String, callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_POST, "/auth/register", {"username": username, "password": password}, callback)

func login(username: String, password: String, callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_POST, "/auth/login", {"username": username, "password": password}, callback)

func sessionInfo(callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_GET, "/auth/session", null, callback)

func logout(callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_POST, "/auth/logout", null, callback)

func startCoffeeGame(callback: Callable) -> void:
    _peticion(HTTPClient.METHOD_POST, "/minijuegos/cafe", {}, callback)

func finishCoffeeGame(run_id: String, actions: Array, callback: Callable) -> void:
    var owner_token := EstadoJuego.sessionToken
    _peticion(HTTPClient.METHOD_POST, "/minijuegos/cafe/%s/finalizar" % run_id, {"actions":actions}, func(code: int, data):
        if code == 200 and data is Dictionary and owner_token == EstadoJuego.sessionToken:
            EstadoJuego.actualizar_monedas(int(data.balance))
            if str(EstadoJuego.pendingCoffee.get("run_id", "")) == run_id:
                EstadoJuego.pendingCoffee = {}
        if callback.is_valid():
            callback.call(code, data)
    )
