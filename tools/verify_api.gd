extends SceneTree
var failures := 0

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var api := root.get_node("Api")
    for route in ["/jugadores", "/tienda", "/cafeteria"]:
        var result: Array = []
        api._peticion(HTTPClient.METHOD_GET, route, null, func(code, data): result.assign([code, data]))
        var deadline := Time.get_ticks_msec() + 12000
        while result.is_empty() and Time.get_ticks_msec() < deadline:
            await process_frame
        if result.size() == 2 and result[0] == (200 if route == "/tienda" else 401) and (result[1] is Array if route == "/tienda" else result[1] is Dictionary):
            print("PASS Godot HTTP y permisos de invitado ", route)
        else:
            failures += 1
            push_error("La API no devolvió una lista válida: " + route)
    print("API_VALIDATION failures=", failures)
    quit(0 if failures == 0 else 1)
