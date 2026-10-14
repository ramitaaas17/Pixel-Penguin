extends SceneTree
var fallos := 0
func _initialize() -> void:
    _run.call_deferred()

func check(ok: bool, texto: String) -> void:
    if ok:
        print("PASS ", texto)
    else:
        push_error("FAIL " + texto)
        fallos += 1

func _run() -> void:
    var packed := load("res://scenes/plaza/Plaza.tscn") as PackedScene
    check(packed != null, "La escena carga")
    if packed == null:
        quit(1)
        return
    var plaza := packed.instantiate()
    root.add_child(plaza)
    current_scene = plaza
    await process_frame
    plaza._pasear()
    check(plaza.get_node("Terreno/Nieve").get_used_cells().size() > 500, "Terreno modular construido")
    var bancas := 0
    for child in plaza.get_children():
        if child.scene_file_path == "res://scenes/plaza/Banco.tscn":
            bancas += 1
    check(bancas == 2, "Solo dos bancas en la plaza")
    for nombre in ["Cafeteria", "Tienda", "Club", "Fuente"]:
        check(not plaza.get_node(nombre).has_node("Sombra"), "Sin sombra ovalada en " + nombre)
    var fuente := plaza.get_node("Fuente")
    var frame_inicial: int = fuente.get_node("Sprite2D").frame
    check(not fuente.animado and not fuente.is_processing(), "Fuente sin animación ni proceso")
    var origen := Vector2(-32, 148)
    for nombre in ["Cafeteria", "Tienda", "Club"]:
        var destino: Vector2 = plaza.get_node(nombre + "/Entrada").global_position
        var ruta: PackedVector2Array = plaza.ruta_hacia(origen, destino)
        check(not ruta.is_empty(), "Ruta hacia " + nombre)
        if not ruta.is_empty():
            check(ruta[-1].distance_to(destino) < 12, "Entrada accesible " + nombre)
        for punto in ruta:
            for rect in plaza.bloqueos:
                if rect.has_point(punto):
                    check(false, "Ruta no atraviesa obstáculos")
    var alrededor: PackedVector2Array = plaza.ruta_hacia(Vector2(-100, 20), Vector2(125, 20))
    check(alrededor.size() > 20, "Ruta rodea la fuente")
    var jugador := plaza.get_node("CaminarDerecha")
    var objetivo := Vector2(-120, 105)
    jugador.ir_a(objetivo)
    for i in range(180):
        await physics_frame
    check(jugador.global_position.distance_to(objetivo) < 12, "El personaje llega caminando")
    check(jugador.get_node("Sprite2D").scale.x == jugador.get_node("Sprite2D").scale.y, "Escala uniforme del personaje")
    check(not plaza.get_node("Tienda").pinguino_cerca, "Sin interacción remota")
    for nombre in ["Cafeteria", "Tienda", "Club"]:
        var entrada: Vector2 = plaza.get_node(nombre + "/Entrada").global_position
        jugador.ir_a(entrada)
        for i in range(420):
            await physics_frame
            if not jugador.moviendose:
                break
        check(jugador.global_position.distance_to(entrada) < 12, "Llegada física a " + nombre)
        await physics_frame
        check(plaza.get_node(nombre).pinguino_cerca, "Detección en puerta de " + nombre)
    plaza._spawn_npc(987654, {"nombre": "Prueba", "monedas": 0})
    check(plaza.pinguinos_npc.size() == 1, "NPC compatible con la plaza")
    var npc: Node2D = plaza.pinguinos_npc[987654]
    check(npc.get_node("Sprite2D").scale == Vector2(0.75, 0.75), "Escala del NPC coherente")
    npc.queue_free()
    plaza.pinguinos_npc.clear()
    var limite: PackedVector2Array = plaza.ruta_hacia(jugador.global_position, Vector2(2000, 2000))
    check(not limite.is_empty(), "Clic fuera del mapa termina en suelo transitable")
    plaza._mostrar_seleccion_jugador()
    check(is_instance_valid(plaza.seleccion_ui), "Selección disponible desde el paseo")
    plaza._pasear()
    check(jugador.habilitado, "Paseo local sin cuenta")
    check(fuente.get_node("Sprite2D").frame == frame_inicial, "Fuente conserva el mismo fotograma durante el paseo")
    print("PLAZA_VALIDATION failures=", fallos)
    quit(0 if fallos == 0 else 1)
