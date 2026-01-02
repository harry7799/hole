extends StaticBody2D

@export var objective_id: StringName = &"golden_core"
@export var required_level: int = 10

func is_core_objective() -> bool:
	return true

func get_objective_id() -> StringName:
	return objective_id

func get_required_level() -> int:
	return required_level
