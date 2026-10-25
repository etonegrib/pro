extends Node2D

var base_y: float = 0.0

func _ready() -> void:
	base_y = position.y
	OrchestraManager.register(self)

func shake() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position:x", position.x + 3, 0.04)
	tw.tween_property(self, "position:x", position.x - 3, 0.04)
	tw.tween_property(self, "position:x", position.x, 0.04)
