extends Node2D

@export var song: SongData

# --- Переменные для детекции взмахов ---
var _prev_y: float = 0.0
var _last_dir: int = 0
var _last_peak_time: float = 0.0
var _bpm_est: float = 120.0
var conductor_bpm: float = 120.0

const MIN_SPEED := 300.0   
const MIN_INTERVAL := 0.25 
const MAX_INTERVAL := 2.0  

# --- Переменные для метронома ---
var _next_beat: float = 0.0

# --- Переменные для какофонии ---
var fatigue: float = 0.0
var cacophony_timer: float = 0.0
var big_cacophony_played: bool = false

@onready var info_label: Label = $UI/InfoLabel
@onready var prompt_label: Label = $UI/PromptLabel
@onready var gesture_label: Label = $UI/GestureLabel
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer # Узел, который ты добавил

var small_cacophony = preload("res://music/cacophony_small.ogg")
var big_cacophony = preload("res://music/cacophony_big.ogg")

func _ready() -> void:
	if song == null:
		push_error("Укажи SongData в инспекторе!")
		return
	Conductor.play_song(song)
	OrchestraManager.start_swinging()
	_bpm_est = song.get_bpm_at(0.0)
	
	gesture_label.text = "Жесты: 1 = FIST, 2 = PALM, 3 = POINT"
	gesture_label.modulate = Color.YELLOW
	gesture_label.modulate.a = 0.5

func _process(delta: float) -> void:
	if not Conductor.is_playing:
		return
	
	_update_bpm_from_mouse(delta)
	OrchestraManager.update_tempo_error(conductor_bpm)
	
	# 1. Меняем скорость музыки
	var original_bpm := Conductor.get_current_bpm()
	if original_bpm > 0:
		var scale := conductor_bpm / original_bpm
		Conductor.set_tempo_scale(scale)
		
	# 2. Обновляем усталость и играем какофонию
	_update_fatigue(delta)
	
	# 3. Проверяем жесты
	_check_gesture_misses()
	
	# 4. UI
	var target_bpm_int: int = int(Conductor.get_current_bpm())
	var my_bpm_int: int = int(conductor_bpm)
	var chaos_int: int = int(OrchestraManager.chaos_level * 100)
	var fatigue_int: int = int(fatigue * 100)
	
	info_label.text = "Твой BPM: %d | Цель: %d | Хаос: %d%% | Усталость: %d%%" % [
		my_bpm_int, target_bpm_int, chaos_int, fatigue_int
	]
	
	_play_metronome()
	_update_prompt()

func _update_bpm_from_mouse(delta: float) -> void:
	var y := get_viewport().get_mouse_position().y
	var vy: float = (y - _prev_y) / max(delta, 0.001)
	_prev_y = y
	
	var dir := 0
	if vy > MIN_SPEED: dir = 1
	elif vy < -MIN_SPEED: dir = -1
	
	var now: float = Time.get_ticks_msec() / 1000.0
	var time_since_peak: float = now - _last_peak_time
	
	if dir != 0 and _last_dir != 0 and dir != _last_dir:
		if time_since_peak >= MIN_INTERVAL and time_since_peak <= MAX_INTERVAL:
			var raw_bpm: float = 60.0 / time_since_peak
			_bpm_est = lerp(_bpm_est, raw_bpm, 0.5) 
		_last_peak_time = now
		
	if dir != 0:
		_last_dir = dir
		
	if time_since_peak > 0.1:
		var implied_bpm: float = 60.0 / time_since_peak
		implied_bpm = clampf(implied_bpm, 30.0, _bpm_est) 
		_bpm_est = lerp(_bpm_est, implied_bpm, 5.0 * delta)
		
	conductor_bpm = _bpm_est

func _update_fatigue(delta: float) -> void:
	if big_cacophony_played:
		return

	# Если хаос больше 40%, оркестр устает
	if OrchestraManager.chaos_level > 0.4:
		fatigue = min(fatigue + delta * 0.2, 1.0)
	else:
		fatigue = max(fatigue - delta * 0.1, 0.0)

	# Мелькание короткой какофонии
	if fatigue > 0.3:
		cacophony_timer -= delta
		if cacophony_timer <= 0 and not sfx_player.playing:
			if small_cacophony != null:
				sfx_player.stream = small_cacophony
				sfx_player.play()
			cacophony_timer = 3.0 # Следующий звук через 3 секунды

	# Финальная точка (полный развал)
	if fatigue >= 1.0:
		_trigger_big_cacophony()

func _trigger_big_cacophony() -> void:
	big_cacophony_played = true
	Conductor.stop()
	Conductor.set_tempo_scale(1.0)
	
	if big_cacophony != null:
		sfx_player.stream = big_cacophony
		sfx_player.play()
		
	info_label.text = "ОРКЕСТР УСТАЛ! ПОЛНЫЙ РАЗВАЛ!"
	OrchestraManager.chaos_pulse()
	
	# Через 4 секунды откат
	await get_tree().create_timer(4.0).timeout
	big_cacophony_played = false
	fatigue = 0.0
	OrchestraManager.chaos_level = 0.0
	Conductor.seek_to(max(0.0, Conductor.song_position - 3.0))

func _play_metronome() -> void:
	var bpm := Conductor.get_current_bpm()
	if bpm > 0.0:
		var beat := 60.0 / bpm
		if Conductor.song_position >= _next_beat:
			info_label.modulate = Color.WHITE
			var tw := create_tween()
			tw.tween_property(info_label, "modulate", Color.GRAY, 0.1)
			_next_beat += beat

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
			break

func _fail_and_rewind() -> void:
	var target: float = max(0.0, Conductor.song_position - 3.0)
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
		if t >= g.time_sec - 0.2 and t <= g.time_sec + 0.4 and g.gesture == gesture_name:
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
