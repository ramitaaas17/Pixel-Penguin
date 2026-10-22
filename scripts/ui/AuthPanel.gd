extends Node
const UI := preload("res://scripts/ui/PixelUI.gd")
signal entered
signal guestRequested

var api: Node
var sessionState: Node
var windowLayer: CanvasLayer
var usernameField: LineEdit
var passwordField: LineEdit
var confirmField: LineEdit
var statusLabel: Label
var submitButton: Button
var mode: String = ""
var busy: bool = false
var generation: int = 0
var buttons: Array[Button] = []

func isOpen() -> bool:
    return is_instance_valid(windowLayer)

func close() -> void:
    generation += 1
    if is_instance_valid(windowLayer):
        windowLayer.queue_free()
    windowLayer = null
    usernameField = null
    passwordField = null
    confirmField = null
    buttons.clear()
    busy = false

func _window(title: String) -> VBoxContainer:
    close()
    var window := UI.modal(self, title, _back)
    windowLayer = window.layer
    windowLayer.name = "AccountWindow"
    for button in windowLayer.find_children("*", "Button", true, false):
        buttons.append(button as Button)
    var body: VBoxContainer = window.body
    body.theme_type_variation = "FormColumn"
    return body

func _button(parent: Control, text: String, action: Callable, secondary: bool = false) -> Button:
    var button := UI.button(text)
    if secondary:
        button.theme_type_variation = "SecondaryButton"
    button.pressed.connect(action)
    parent.add_child(button)
    buttons.append(button)
    return button

func showWelcome(message: String = "") -> void:
    var body := _window("Nos vemos en la plaza")
    mode = "welcome"
    body.add_child(UI.wrapped_label("Nieve, café y un pingüino que puedes llamar tuyo.", "SecondaryLabel"))
    var enter := _button(body, "Entrar", func(): showForm("login"))
    _button(body, "Crear cuenta", func(): showForm("register"), true)
    _button(body, "Pasear como invitado", _guest, true)
    statusLabel = UI.wrapped_label(message if not message.is_empty() else "Puedes explorar sin conexión.", "SecondaryLabel")
    body.add_child(statusLabel)
    enter.grab_focus.call_deferred()

func _field(parent: Control, title: String, placeholder: String, secret: bool = false) -> LineEdit:
    var group := VBoxContainer.new()
    group.theme_type_variation = "TightColumn"
    parent.add_child(group)
    group.add_child(UI.label(title, "SecondaryLabel"))
    var field := LineEdit.new()
    field.placeholder_text = placeholder
    field.secret = secret
    field.secret_character = "*"
    field.max_length = 72 if secret else 20
    field.custom_minimum_size = Vector2(0, 38)
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    group.add_child(field)
    return field

func showForm(nextMode: String) -> void:
    var body := _window("Tu primer paseo" if nextMode == "register" else "Vuelve a la plaza")
    mode = nextMode
    body.add_child(UI.label("Crea tu cuenta y entra con tu pingüino." if mode == "register" else "Tu pingüino te espera.", "SecondaryLabel"))
    usernameField = _field(body, "Usuario", "Tu nombre en la plaza")
    passwordField = _field(body, "Contraseña", "Al menos 8 caracteres", true)
    usernameField.text_submitted.connect(func(_text): passwordField.grab_focus())
    if mode == "register":
        confirmField = _field(body, "Confirmar contraseña", "Escríbela una vez más", true)
        passwordField.text_submitted.connect(func(_text): confirmField.grab_focus())
        confirmField.text_submitted.connect(func(_text): _submit())
    else:
        passwordField.text_submitted.connect(func(_text): _submit())
    statusLabel = UI.wrapped_label("3 a 20 letras, números o guion bajo." if mode == "register" else "", "SecondaryLabel")
    statusLabel.custom_minimum_size.y = 36
    body.add_child(statusLabel)
    submitButton = _button(body, "Crear mi cuenta" if mode == "register" else "Entrar a la plaza", _submit)
    _button(body, "Volver", _back, true)
    usernameField.grab_focus.call_deferred()

func showAccount() -> void:
    var body := _window("Tu rincón en la plaza")
    mode = "account"
    body.add_child(UI.label(sessionState.jugador_nombre, "HeadingLabel"))
    body.add_child(UI.label("Monedas: %d" % sessionState.monedas, "SecondaryLabel"))
    body.add_child(UI.wrapped_label("Has entrado con tu cuenta.", "SecondaryLabel"))
    statusLabel = UI.wrapped_label("", "ErrorLabel")
    body.add_child(statusLabel)
    _button(body, "Volver a la plaza", func(): entered.emit())
    submitButton = _button(body, "Cerrar sesión", _logout, true)

func _setBusy(value: bool) -> void:
    busy = value
    for button in buttons:
        if is_instance_valid(button):
            button.disabled = value
    for field in [usernameField, passwordField, confirmField]:
        if is_instance_valid(field):
            field.editable = not value
    if is_instance_valid(submitButton):
        submitButton.text = "Un momento..." if value else ("Crear mi cuenta" if mode == "register" else ("Cerrar sesión" if mode == "account" else "Entrar a la plaza"))

func _error(message: String) -> void:
    statusLabel.theme_type_variation = "ErrorLabel"
    statusLabel.text = message

func _submit() -> void:
    if busy:
        return
    var username := usernameField.text.strip_edges()
    var password := passwordField.text
    if username.length() < 3 or username.length() > 20:
        _error("Usa entre 3 y 20 caracteres para tu usuario.")
        return
    if mode == "register" and password.length() < 8:
        _error("Usa al menos 8 caracteres para tu contraseña.")
        return
    if mode == "register" and password.to_utf8_buffer().size() > 72:
        _error("La contraseña es demasiado larga. Usa una más corta.")
        return
    if mode == "register" and password != confirmField.text:
        _error("Las contraseñas no coinciden.")
        return
    if password.is_empty():
        _error("Escribe tu contraseña.")
        return
    _setBusy(true)
    statusLabel.theme_type_variation = "SecondaryLabel"
    statusLabel.text = "Preparando tu entrada..."
    var requestGeneration := generation
    var onResponse := func(code, data):
        if requestGeneration != generation or not isOpen():
            return
        _setBusy(false)
        passwordField.clear()
        if is_instance_valid(confirmField):
            confirmField.clear()
        if code in [200, 201] and data is Dictionary and data.has("token") and data.has("jugador"):
            sessionState.acceptSession(data)
            return
        _error(str(data.get("error", "No se pudo entrar. Intenta otra vez.")) if data is Dictionary else "No hay conexión. Puedes volver o pasear como invitado.")
        passwordField.grab_focus()
    if mode == "register":
        api.registerAccount(username, password, onResponse)
    else:
        api.login(username, password, onResponse)

func _logout() -> void:
    if busy:
        return
    _setBusy(true)
    var requestGeneration := generation
    api.logout(func(code, _data):
        if requestGeneration != generation or not isOpen():
            return
        _setBusy(false)
        if code == 200:
            sessionState.clearSession()
        else:
            _error("No se pudo cerrar la sesión. Reintenta con conexión.")
    )

func _guest() -> void:
    if not busy:
        guestRequested.emit()

func _back() -> void:
    if busy:
        return
    if mode in ["login", "register"]:
        showWelcome()
    elif mode == "account":
        entered.emit()
    else:
        _guest()

func _unhandled_key_input(event: InputEvent) -> void:
    if isOpen() and event.is_action_pressed("ui_cancel"):
        _back()
        get_viewport().set_input_as_handled()
