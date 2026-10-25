extends Node2D

@export var song: SongData
@export var mouse_sensitivity: float = 3.0 

var last_mouse_y: float = 0.0
var conductor_bpm: float = 0.0
var _mouse_started := false

# Переменные для усталости и какофонии
var fatigue: float = 0.0
var cacophony_timer: float = 0.0
var big_cacophony_played: bool = false

@onready var info_label: Label = $UI/InfoLabel
@onready var prompt_label: Label = $UI/PromptLabel
@onready var gesture_label: Label = $UI/GestureLabel

# ВАЖНО: Тебе нужно добавить узел AudioStreamPlayer на сцену и назвать его SFXPlayer
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer 

# ВАЖНО: Тебе нужно положить эти файлы в папку music (или заменить пути на свои)
# Если файлов нет, Godot выдаст ошибку при запуске. Можешь пока закомментировать эти строки.
var cacophony_small: AudioStream = load("res://music/cacophony_small.ogg")
var cacophony_big: AudioStream = load("res://music/cacophony_big.ogg")

func _ready() -> void:
	if song == null:
		push_error("Укажи SongData в инспекторе!")
		return
	Conductor.play_song(song)
	OrchestraManager.start_swinging()
	
	gesture_label.text = "Жесты: 1 = FIST, 2 = PALM, 3 = POINT"
	gesture_label.modulate = Color.YELLOW
	gesture_label.modulate.a = 0.5

func _process(delta: float) -> void:
	if not Conductor.is_playing:
		return
	
	var mp := get_viewport().get_mouse_position()
	if not _mouse_started:
		last_mouse_y = mp.y
		_mouse_started = true
	
	# 1. Сглаживаем скорость мыши
	var instant_v: float = abs(mp.y - last_mouse_y) / max(delta, 0.001)
	last_mouse_y = mp.y
	
	# 2. Считаем BPM
	var target_bpm_calc: float = clampf(instant_v / mouse_sensitivity, 30.0, 200.0)
	conductor_bpm = lerp(conductor_bpm, target_bpm_calc, 0.03)
	
	# 3. Обновляем хаос
	OrchestraManager.update_tempo_error(conductor_bpm)
	
	# 4. МЕНЯЕМ ТЕМП МУЗЫКИ (без тона), если хаос еще не полный
	_update_music_tempo()
	
	# 5. Обновляем усталость и какофонию
	_update_fatigue(delta)
	
	_check_gesture_misses()
	
	# 6. UI
	var target_bpm_int: int = int(Conductor.get_current_bpm())
	var my_bpm_int: int = int(conductor_bpm)
	var chaos_int: int = int(OrchestraManager.chaos_level * 100)
	var fatigue_int: int = int(fatigue * 100)
	
	info_label.text = "Твой BPM: %d | Цель: %d | Хаос: %d%% | Усталость: %d%%" % [
		my_bpm_int, target_bpm_int, chaos_int, fatigue_int
	]
	
	_update_prompt()

func _update_music_tempo() -> void:
	# Если оркестр еще слушается (хаос меньше 50%), музыка подстраивается под руку
	if OrchestraManager.chaos_level < 0.5 and not big_cacophony_played:
		var target_bpm := Conductor.get_current_bpm()
		if target_bpm > 0:
			var ratio: float = conductor_bpm / target_bpm
			# Ограничиваем изменение скорости (от 0.8x до 1.2x), чтобы не звучало как жесть
			ratio = clampf(ratio, 0.8, 1.2) 
			Conductor.set_tempo_scale(ratio)
	else:
		# Если хаос сильный, возвращаем оригинальный темп (пусть трещит)
		Conductor.set_tempo_scale(1.0)

func _update_fatigue(delta: float) -> void:
	if big_cacophony_played:
		return

	# Если хаос больше 40%, оркестр устает
	if OrchestraManager.chaos_level > 0.4:
		fatigue = min(fatigue + delta * 0.2, 1.0)
	else:
		fatigue = max(fatigue - delta * 0.1, 0.0)

	# Мелькание какофонии (если усталость выше 30%)
	if fatigue > 0.3:
		cacophony_timer -= delta
		if cacophony_timer <= 0:
			if cacophony_small != null and not sfx_player.playing:
				sfx_player.stream = cacophony_small
				sfx_player.play()
			cacophony_timer = 3.0 # Следующий звук через 3 секунды

	# Финальная точка
	if fatigue >= 1.0:
		_trigger_big_cacophony()

func _trigger_big_cacophony() -> void:
	big_cacophony_played = true
	Conductor.stop() # Резко останавливаем музыку
	Conductor.set_tempo_scale(1.0)
	
	if cacophony_big != null:
		sfx_player.stream = cacophony_big
		sfx_player.play()
		
	info_label.text = "ОРКЕСТР УСТАЛ! ПОЛНЫЙ РАЗВАЛ!"
	OrchestraManager.chaos_pulse()
	
	# Через 4 секунды откатываем трек на 5 секунд назад и даем шанс исправиться
	await get_tree().create_timer(4.0).timeout
	big_cacophony_played = false
	fatigue = 0.0
	OrchestraManager.chaos_level = 0.0
	Conductor.seek_to(max(0.0, Conductor.song_position - 5.0))

func _update_prompt() -> void:
	prompt_label.text = ""
	for g in song.gestures:
		if g.processed:
			continue
		var dt: float = g.time_sec - Conductor.song_position
		if dt > -0.5 and dt < 3.0:
			prompt_label.text = ">>> ЖЕСТ: %s через %.1fс <<<" % [g.gesture, max(dt, 0.0)]
			break

func _check_gesture_misses() -> void:
	var t := Conductor.song_position
	for g in song.gestures:
		if g.processed:
			continue
		if t > g.time_sec + g.window_sec:
			g.processed = true
			EventBus.gesture_missed.emit(g.gesture)
			_fail_and_rewind()

func _fail_and_rewind() -> void:
	var target: float = max(0.0, Conductor.song_position - 5.0)
	Conductor.seek_to(target)
	OrchestraManager.chaos_pulse()
	for g in song.gestures:
		if g.time_sec >= target:
			g.processed = false
			
	gesture_label.text = "ПРОМАХ ЖЕСТА! Откат назад..."
	gesture_label.modulate = Color.RED
	gesture_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(_reset_feedback_alpha)

const GESTURE_KEYS := {
	KEY_1: "FIST",
	KEY_2: "PALM",
	KEY_3: "POINT",
}

func _input(event: InputEvent) -> void:
	if not Conductor.is_playing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var g: String = GESTURE_KEYS.get(event.keycode, "")
		if g != "":
			_try_gesture(g)

func _try_gesture(gesture_name: String) -> void:
	var t := Conductor.song_position
	for g in song.gestures:
		if g.processed:
			continue
		if t >= g.time_sec and t <= g.time_sec + g.window_sec and g.gesture == gesture_name:
			g.processed = true
			EventBus.gesture_hit.emit(gesture_name)
			_show_gesture_feedback("✓ УСПЕХ: " + gesture_name, Color.GREEN)
			return

func _show_gesture_feedback(text: String, color: Color) -> void:
	gesture_label.text = text
	gesture_label.modulate = color
	gesture_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(gesture_label, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_reset_feedback_alpha)

func _reset_feedback_alpha() -> void:
	gesture_label.text = "Жесты: 1 = FIST, 2 = PALM, 3 = POINT"
	gesture_label.modulate = Color.YELLOW
	gesture_label.modulate.a = 0.3
