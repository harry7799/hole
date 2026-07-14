extends SceneTree

var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var prey_scene := load("res://Scenes/SwallowableObject.tscn") as PackedScene
	_expect(prey_scene != null, "SwallowableObject scene failed to load")
	if prey_scene:
		var prey := prey_scene.instantiate() as RigidBody2D
		_expect(prey != null, "SwallowableObject root is not a RigidBody2D")
		if prey:
			_expect(prey.position.is_zero_approx(), "prey root must be centered at the origin")
			var textures = prey.get("textures")
			_expect(textures is Array and textures.size() == 5, "prey scene must expose exactly five textures")
			if textures is Array:
				for texture in textures:
					_expect(texture is Texture2D, "prey texture failed to load")
					if texture is Texture2D:
						_expect((texture as Texture2D).get_size() == Vector2(256, 256), "prey texture must be 256 x 256")
			var collider := prey.get_node_or_null("CollisionShape2D") as CollisionShape2D
			_expect(collider != null, "prey collider is missing")
			if collider:
				_expect(collider.position.is_zero_approx(), "prey collider must be centered")
				_expect(collider.shape is CircleShape2D, "prey collider must be circular")
				if collider.shape is CircleShape2D:
					_expect(is_equal_approx((collider.shape as CircleShape2D).radius, 52.0), "prey collider radius must be 52 px")
			prey.free()

	var projectile_scene := load("res://EnemyProjectile.tscn") as PackedScene
	_expect(projectile_scene != null, "EnemyProjectile scene failed to load")
	if projectile_scene:
		var projectile := projectile_scene.instantiate() as Area2D
		_expect(projectile != null, "EnemyProjectile root is not an Area2D")
		if projectile:
			_expect(projectile.has_method("set_motion"), "EnemyProjectile.set_motion is missing")
			if projectile.has_method("set_motion"):
				projectile.call("set_motion", Vector2.UP * 400.0)
				_expect(is_equal_approx(projectile.rotation, -PI * 0.5), "projectile nose does not follow upward velocity")
				projectile.call("set_motion", Vector2.LEFT * 400.0)
				_expect(is_equal_approx(absf(projectile.rotation), PI), "projectile nose does not follow leftward velocity")
			projectile.free()

	var main_scene_text := FileAccess.get_file_as_string("res://Scenes/MainScene.tscn")
	_expect(not main_scene_text.contains("instance=ExtResource(\"2_nhkr4\")"), "MainScene still contains authored startup prey instances")

	if _failures.is_empty():
		print("ASSET MERGE SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ASSET MERGE SMOKE: FAIL (%d)" % _failures.size())
	quit(1)
