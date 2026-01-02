extends RigidBody2D

@export var score_value: float = 8.0

func _ready() -> void:
	add_to_group("PowerUps")
	rotation = randf_range(0.0, TAU)
	angular_velocity = randf_range(-2.0, 2.0)

func get_score_value() -> float:
	return score_value

func get_powerup_type() -> StringName:
	return &"MAGNET"
