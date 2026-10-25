extends Node

var audio_player: AudioStreamPlayer
var current_song: SongData
var song_position: float = 0.0
var is_playing: bool = false

# Переменные для изменения темпа без изменения тона
var pitch_shift_effect: AudioEffectPitchShift
var base_pitch_scale: float = 1.0 # 1.0 = оригинальная скорость

func _ready() -> void:
	audio_player = AudioStreamPlayer.new()
	# Отправляем звук в нашу специальную шину Music
	audio_player.bus = "Music" 
	add_child(audio_player)
	
	# Ищем эффект PitchShift на шине Music
	var bus_idx := AudioServer.get_bus_index("Music")
	if bus_idx == -1:
		push_error("Шина 'Music' не найдена! Проверь панель Аудио.")
		return
		
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var effect := AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectPitchShift:
			pitch_shift_effect = effect
			break
			
	if pitch_shift_effect == null:
		push_warning("Эффект PitchShift не найден на шине 'Music'. Смена темпа без тона не сработает.")

func play_song(song: SongData, from_sec: float = 0.0) -> void:
	current_song = song
	audio_player.stream = song.audio_file
	
	for g in song.gestures:
		g.processed = false
		
	# Сбрасываем темп на оригинальный при старте
	set_tempo_scale(1.0) 
	
	audio_player.play(from_sec)
	song_position = from_sec
	is_playing = true

func stop() -> void:
	audio_player.stop()
	is_playing = false

func seek_to(t: float) -> void:
	# При откате мы не сбрасываем pitch_scale, 
	# чтобы игрок продолжал слышать музыку в том же темпе
	audio_player.play(max(0.0, t))
	song_position = t

func _physics_process(_delta: float) -> void:
	if not is_playing or not audio_player.playing:
		return
	# Точная позиция в треке (в секундах)
	song_position = audio_player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()

func get_current_bpm() -> float:
	if current_song == null:
		return 120.0
	return current_song.get_bpm_at(song_position)

# ==========================================
# НОВАЯ ФУНКЦИЯ: Изменение темпа без тона
# ==========================================
# scale = 1.0 (оригинал)
# scale = 1.2 (на 20% быстрее)
# scale = 0.8 (на 20% медленнее)
func set_tempo_scale(scale: float) -> void:
	if pitch_shift_effect == null:
		return
		
	# 1. Меняем скорость воспроизведения (вместе с этим меняется и тон)
	audio_player.pitch_scale = base_pitch_scale * scale
	
	# 2. Компенсируем изменение тона обратным значением
	pitch_shift_effect.pitch_scale = 1.0 / scale
