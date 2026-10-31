extends AudioStreamPlayer
var muted := false
func _ready() -> void:
    var settings := ConfigFile.new()
    if settings.load("user://coffee_settings.cfg") == OK:
        muted = bool(settings.get_value("audio", "muted", false))
    var tune := preload("res://assets/audio/coffee_loop.wav").duplicate() as AudioStreamWAV
    tune.loop_mode = AudioStreamWAV.LOOP_FORWARD
    tune.loop_begin = 0
    tune.loop_end = int(tune.get_length() * tune.mix_rate)
    stream = tune
    volume_db = -16
func startTune() -> void:
    if not muted and not playing:
        play()
func toggleMute() -> void:
    muted = not muted
    if muted:
        stop()
    else:
        startTune()
    var settings := ConfigFile.new()
    settings.set_value("audio", "muted", muted)
    settings.save("user://coffee_settings.cfg")
