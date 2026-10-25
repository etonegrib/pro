extends Node

var audio_player: AudioStreamPlayer
var current_song: SongData
var song_position: float = 0.0
var is_playing: bool = false
var _skip_pos_update: bool = false

# Плавная смена скорости
var _current_scale: float = 1.0
var _target_scale: float = 1.0

func _ready() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "Music"
	add_child(audio_player)

func play_song(song: SongData, from_sec: float = 0.0) -> void:
	current_song = song
	audio_player.stream = song.audio_file
	
	for g in song.gestures:
		g.processed = false
		
	_current_scale = 1.0
	_target_scale = 1.0
	audio_player.pitch_scale = 1.0
	
	audio_player.play(from_sec)
	song_position = from_sec
	is_playing = true

func stop() -> void:
	audio_player.stop()
	is_playing = false

func seek_to(t: float) -> void:
	audio_player.play(max(0.0, t))
	song_position = t
	_skip_pos_update = true

func _physics_process(_delta: float) -> void:
	if not is_playing or not audio_player.playing:
		return
	if _skip_pos_update:
		_skip_pos_update = false
		return
	song_position = audio_player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()

func get_current_bpm() -> float:
	if current_song == null:
		return 120.0
	return current_song.get_bpm_at(song_position)

func set_tempo_scale(scale: float) -> void:
	_target_scale = clampf(scale, 0.5, 2.0)

func _process(delta: float) -> void:
	if not is_playing:
		return
	_current_scale = lerp(_current_scale, _target_scale, 5.0 * delta)
	
	# ТОЛЬКО МЕНЯЕМ СКОРОСТЬ (Тон поедет вместе с ней - это чисто и без искажений)
	audio_player.pitch_scale = _current_scale
