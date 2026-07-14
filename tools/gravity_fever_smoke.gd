extends SceneTree

var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var main_scene := load("res://Scenes/MainScene.tscn") as PackedScene
	_expect(main_scene != null, "MainScene failed to load")
	if not main_scene:
		_finish()
		return

	var main := main_scene.instantiate() as Node2D
	_expect(main != null, "MainScene root is not Node2D")
	if not main:
		_finish()
		return
	root.add_child(main)
	paused = false
	await process_frame
	await physics_frame

	var black_hole := main.find_child("BlackHole", true, false)
	_expect(black_hole != null, "BlackHole node is missing")
	if not black_hole:
		main.queue_free()
		_finish()
		return

	_expect(is_equal_approx(float(black_hole.get("fever_duration_sec")), 8.0), "FEVER duration must be 8 seconds")
	_expect(not bool(black_hole.get("fever_legacy_ring_enabled")), "legacy full FEVER ring must stay disabled")
	_expect(is_equal_approx(float(black_hole.get("gravity_wave_strength")), 0.185), "gravity wave strength must be 0.185")
	_expect(is_equal_approx(float(black_hole.get("gravity_wave_frequency")), 19.5), "gravity wave frequency must be 19.5")
	_expect(is_equal_approx(float(black_hole.get("gravity_wave_speed")), 1.45), "gravity wave speed must be 1.45")

	var lens_material := black_hole.get("full_screen_distort_material") as ShaderMaterial
	_expect(lens_material != null, "full-screen lens material was not initialized")
	if lens_material:
		_expect(is_equal_approx(float(lens_material.get_shader_parameter("gravity_wave_strength")), 0.185), "runtime lens strength is out of sync")
		_expect(is_equal_approx(float(lens_material.get_shader_parameter("gravity_wave_frequency")), 19.5), "runtime lens frequency is out of sync")
		_expect(is_equal_approx(float(lens_material.get_shader_parameter("gravity_wave_speed")), 1.45), "runtime lens speed is out of sync")
		black_hole.call("set_reduced_motion", true)
		_expect(is_zero_approx(float(lens_material.get_shader_parameter("motion_scale"))), "reduced motion must retain a static lens")
		black_hole.call("set_reduced_motion", false)

	var score_events: Array[int] = []
	black_hole.object_swallowed.connect(func(value: int) -> void: score_events.append(value))
	black_hole.call("start_fever")
	await physics_frame
	_expect(bool(black_hole.call("is_fever_active")), "FEVER did not activate")
	var spawn_manager = main.get("_spawn_mgr")
	_expect(spawn_manager != null and bool(spawn_manager.get("fever_active")), "SpawnManager did not enter FEVER pacing")

	var stability_before := float(black_hole.get("current_stability"))
	black_hole.call("apply_damage", 25.0)
	_expect(is_equal_approx(float(black_hole.get("current_stability")), stability_before), "FEVER must prevent damage")

	var enemy_scene := load("res://Scenes/Enemy.tscn") as PackedScene
	_expect(enemy_scene != null, "Enemy scene failed to load")
	if enemy_scene:
		var enemy := enemy_scene.instantiate() as Area2D
		main.add_child(enemy)
		enemy.call("set_stage", 3)
		enemy.call("set_target", black_hole)
		enemy.global_position = black_hole.global_position + Vector2(160.0, 0.0)
		enemy.call("set_edible", true)
		await physics_frame
		await physics_frame
		_expect(not is_instance_valid(enemy) or bool(enemy.call("is_consumed")), "FEVER enemy was not atomically swallowed")
		_expect(score_events.size() == 1 and score_events[0] == 360, "stage 3 FEVER swallow must emit one 360-point event")

	black_hole.call("_end_fever", false)
	await process_frame
	_expect(not bool(black_hole.call("is_fever_active")), "FEVER did not end")
	_expect(spawn_manager == null or not bool(spawn_manager.get("fever_active")), "SpawnManager did not restore normal pacing")

	main.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("GRAVITY + FEVER SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("GRAVITY + FEVER SMOKE: FAIL (%d)" % _failures.size())
	quit(1)
