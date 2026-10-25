class_name SongData
extends Resource

@export var audio_file: AudioStream
@export var display_name: String = "Untitled"
@export var tempo_map: Array[TempoMarker] = []
@export var gestures: Array[GestureEvent] = []

func get_bpm_at(t: float) -> float:
	var bpm := 120.0
	for m in tempo_map:
		if t >= m.time_sec:
			bpm = m.bpm
		else:
			break
	return bpm
