extends Node

var musicians: Array[Node] = []
var target_bpm: float = 120.0
var chaos_level: float = 0.0
var swing_phase: float = 0.0

func register(m: Node) -> void:
	musicians.append(m)

func start_swinging() -> void:
	chaos_level = 0.0
	swing_phase = 0.0

func update_tempo_error(conductor_bpm: float) -> void:
	target_bpm = Conductor.get_current_bpm()
	if target_bpm <= 0.0:
		return
	
	var err: float = abs(conductor_bpm - target_bpm) / target_bpm
	
	# ЩАДЯЩАЯ МЕХАНИКА: Если ошибка меньше 20%, мы ее игнорируем
	if err < 0.20:
		err = 0.0
		
	# Если ошибка больше, хаос растет, но плавно (сглаживание 0.05)
	chaos_level = lerp(chaos_level, clamp(err * 1.5, 0.0, 1.0), 0.05)
	EventBus.tempo_error.emit(err)

func chaos_pulse() -> void:
	chaos_level = 1.0
	for m in musicians:
		m.shake()

func _process(delta: float) -> void:
	if not Conductor.is_playing:
		return
	var effective_bpm: float = target_bpm * (1.0 + (chaos_level - 0.5) * 0.3)
	swing_phase += delta * (effective_bpm / 60.0) * TAU
	for i in musicians.size():
		var m = musicians[i]
		var offset: float = 0.0
		if chaos_level > 0.1:
			offset = sin(swing_phase * 1.7 + i * 1.3) * chaos_level * PI
		
		var swing: float = sin(swing_phase + offset) * lerp(0.10, 0.20, chaos_level)
		m.rotation = swing
		m.position.y = m.base_y + abs(swing) * -4.0
