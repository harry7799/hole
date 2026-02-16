extends RigidBody2D
## ShieldItem — grants temporary damage immunity when swallowed.

@export var score_value: float = 12.0

func _ready() -> void:
	add_to_group("PowerUps")
	rotation = randf_range(0.0, TAU)
	angular_velocity = randf_range(-1.5, 1.5)

func get_score_value() -> float:
	return score_value

func get_powerup_type() -> StringName:
	return &"SHIELD"
