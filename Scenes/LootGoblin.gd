extends RigidBody2D
## LootGoblin — 稀有逃跑型獵物 (Phase 4D)
## 不被引力吸引，反而會逃離黑洞。吞噬後獲得大量獎勵。
## 有存活時間限制，超時後消失。

@export var flee_speed: float = 280.0       ## 逃跑速度
@export var flee_accel: float = 600.0       ## 逃跑加速度
@export var lifetime: float = 12.0          ## 存活秒數
@export var score_value: float = 80.0       ## 被吞噬時給予的分數
@export var stability_bonus: float = 30.0   ## 被吞噬時回復的穩定度
@export var detection_range: float = 500.0  ## 偵測黑洞的範圍（超過此距離不逃跑）

var _target: Node2D = null    ## 黑洞參考
var _age: float = 0.0
var _dying: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("Prey")
	add_to_group("Swallowables")
	add_to_group("LootGoblins")
	gravity_scale = 0.0
	# 金色光暈效果
	if sprite:
		sprite.modulate = Color(1.0, 0.85, 0.2, 1.0)
		# 使用固定大小使其突出
		sprite.scale = Vector2.ONE * 1.8
	if collision_shape and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = 60.0
	# 隨機旋轉
	rotation = randf() * TAU
	angular_velocity = randf_range(-3.0, 3.0)
	# 開始閃爍動畫（讓玩家注意到）
	_start_glow_anim()


func set_target(t: Node2D) -> void:
	_target = t


func get_score_value() -> float:
	return score_value


func get_stability_bonus() -> float:
	return stability_bonus


func is_loot_goblin() -> bool:
	return true


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_age += delta
	# 存活時間到 → 淡出消失
	if _age >= lifetime:
		_despawn()
		return
	# 臨近超時時加速閃爍
	if _age >= lifetime - 3.0 and sprite:
		var blink: float = 1.0 if fmod(_age * 6.0, 1.0) > 0.5 else 0.4
		sprite.modulate.a = blink
	# 逃離黑洞
	if _target and is_instance_valid(_target):
		var dir_away: Vector2 = global_position - _target.global_position
		var dist: float = dir_away.length()
		if dist < detection_range and dist > 1.0:
			var flee_dir: Vector2 = dir_away.normalized()
			apply_central_force(flee_dir * flee_accel)
			# 限制最大速度
			if linear_velocity.length() > flee_speed:
				linear_velocity = linear_velocity.normalized() * flee_speed
		else:
			# 超出偵測範圍：隨機漂移
			var drift := Vector2.RIGHT.rotated(randf() * TAU) * 40.0
			apply_central_force(drift)
	# 阻尼（防止無限加速）
	linear_velocity *= 0.98


func _start_glow_anim() -> void:
	if not sprite:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(sprite, "modulate", Color(1.0, 1.0, 0.5, 1.0), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sprite, "modulate", Color(1.0, 0.75, 0.1, 1.0), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _despawn() -> void:
	if _dying:
		return
	_dying = true
	# 縮小淡出
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * 0.1, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	tw.finished.connect(queue_free)
