extends Area2D

const FEVER_SCORE_BY_STAGE: Array[float] = [120.0, 180.0, 260.0, 360.0, 480.0, 650.0]
const FEVER_STABILITY_BY_STAGE: Array[float] = [8.0, 10.0, 12.0, 14.0, 17.0, 20.0]
const FEVER_GROWTH_BY_STAGE: Array[int] = [2, 2, 3, 3, 4, 4]

# ----------------------------------------------------
# 遊玩數值常數
# ----------------------------------------------------
const MELEE_HIT_RADIUS: float = 140.0

# ----------------------------------------------------
# 資源與節點引用
# ----------------------------------------------------
@export var move_speed: float = 150.0
@export_range(0.1, 2.0, 0.05) var melee_hit_cooldown: float = 0.65
@export_range(80.0, 360.0, 5.0) var edible_capture_radius: float = 190.0
@export_range(0.1, 1.0, 0.05) var edible_move_speed_scale: float = 0.52
@export var edible_tint: Color = Color("#78f5ff")
@export var damage: float = 10.0 # 撞到黑洞扣多少能量 (近戰傷害)

# 近戰撞擊時的「蒸發」效果（縮小/噴裝）
@export var shrink_amount: float = 8.0
@export var eject_count: int = 4

# 【請務必在編輯器拖入 EnemyProjectile.tscn】
@export var projectile_scene: PackedScene 

# 依通緝等級(=stage)切換敵人本體圖案：在 Inspector 填入 0~5 共 6 張。
# 若未提供，會沿用 Enemy.tscn 的 Sprite2D 預設貼圖。
@export var stage_enemy_textures: Array[Texture2D] = []

# 效能保護：避免後期子彈暴增導致頓挫
@export var max_global_projectiles: int = 90

# 難度參數（由 Main.gd 依通緝等級設定）
var stage: int = 0
var shoot_interval: float = 2.0
var projectile_speed: float = 400.0
var projectile_damage: float = 5.0
var burst_count: int = 1
var spread_degrees: float = 0.0
var projectile_texture: Texture2D = null

var target: Node2D = null
var _frozen: bool = false
var _pending_destroy: bool = false
var _edible: bool = false
var _consumed: bool = false
var _contact_cooldown_left: float = 0.0
var _fever_visual_time: float = 0.0
var _orbit_sign: float = 1.0
var _base_sprite_modulate: Color = Color.WHITE
var _base_sprite_scale: Vector2 = Vector2.ONE
var _base_scale: Vector2 = Vector2.ONE

@onready var _sprite := get_node_or_null("Sprite2D") as Sprite2D
@onready var _collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
var _default_enemy_texture: Texture2D = null

@export var telegraph_enabled: bool = true
@export var telegraph_stage_min: int = 2
@export var telegraph_time: float = 0.5
var _telegraph_line: Line2D = null
var _telegraphing: bool = false


func is_enemy() -> bool:
	return true


func get_score_value() -> float:
	# Used by BlackHole swallow logic (especially in Fever Mode).
	return FEVER_SCORE_BY_STAGE[clampi(stage, 0, FEVER_SCORE_BY_STAGE.size() - 1)]


func get_stability_value() -> float:
	return FEVER_STABILITY_BY_STAGE[clampi(stage, 0, FEVER_STABILITY_BY_STAGE.size() - 1)]


func get_growth_value() -> int:
	return FEVER_GROWTH_BY_STAGE[clampi(stage, 0, FEVER_GROWTH_BY_STAGE.size() - 1)]

@onready var shoot_timer = $ShootTimer # 假設你在 Enemy.tscn 內新增了 Timer 節點
@onready var muzzle = $Muzzle           # 假設你在 Enemy.tscn 內新增了 Marker2D 節點

func set_target(t):
	target = t

func _ready():
	# 確保敵人被加入 Enemies 群組
	add_to_group("Enemies")
	_orbit_sign = -1.0 if randf() < 0.5 else 1.0
	_base_scale = scale
	# 保險起見：確保 body_entered 有連線（避免場景沒接造成不扣血）
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	# Area2D vs Area2D：黑洞本體是 Area2D，所以需要 area_entered 才能打到
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	
	# 連接射擊計時器
	if shoot_timer:
		shoot_timer.timeout.connect(_shoot)
		shoot_timer.wait_time = shoot_interval
		# 假設 Timer 已經勾選 Autostart=True，如果沒有請在這裡加上 shoot_timer.start()

	# 初始套用目前 stage 的參數
	_set_stage_params(stage)
	if _sprite and _default_enemy_texture == null:
		_default_enemy_texture = _sprite.texture
	if _sprite:
		_base_sprite_modulate = _sprite.modulate
		_base_sprite_scale = _sprite.scale

	# 手機可讀性：高階段射擊前顯示預警線
	_telegraph_line = Line2D.new()
	_telegraph_line.visible = false
	_telegraph_line.width = 5.0
	_telegraph_line.default_color = Color(1, 0.15, 0.15, 0.35)
	_telegraph_line.z_index = 50
	add_child(_telegraph_line)

func _physics_process(delta: float) -> void:
	if _consumed:
		return
	_contact_cooldown_left = maxf(0.0, _contact_cooldown_left - maxf(delta, 0.0))
	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var distance_to_target := to_target.length()
	var inward := to_target.normalized() if distance_to_target > 0.001 else Vector2.RIGHT

	if _edible:
		_update_edible_visual(delta)
		if distance_to_target <= edible_capture_radius and _try_target_swallow(target):
			return
		if not _frozen:
			# Stay readable as prey while the black-hole pull wins at close range.
			var tangent := inward.orthogonal() * _orbit_sign
			var flee_direction := (-inward * 0.72 + tangent * 0.70).normalized()
			position += flee_direction * move_speed * edible_move_speed_scale * delta
			rotation = flee_direction.angle() + deg_to_rad(90.0)
		return

	_restore_normal_visual_state()
	if _frozen:
		return

	# The player's gravity Area is much larger than its damaging core. Poll core
	# distance every frame so entering the outer Area cannot consume the only hit.
	var melee_radius := _get_target_core_radius(target)
	if distance_to_target <= melee_radius:
		_deal_melee_hit(target)
		if _consumed or is_queued_for_deletion():
			return

	position += inward * move_speed * delta
	rotation = inward.angle() + deg_to_rad(90.0)
	# Catch fast crossings that enter the core during this movement step.
	if global_position.distance_to(target.global_position) <= melee_radius:
		_deal_melee_hit(target)


func _process(_delta: float) -> void:
	# Hourglass freezes physics; FEVER contact still needs to respond while frozen.
	if not _frozen or _consumed or not _edible or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= edible_capture_radius:
		_try_target_swallow(target)


func set_frozen(frozen: bool) -> void:
	_frozen = frozen
	_sync_activity_state()


func set_edible(edible: bool) -> void:
	if _consumed:
		return
	_edible = edible
	_pending_destroy = false
	_contact_cooldown_left = 0.0
	if is_node_ready():
		_apply_edible_visual_state()
		_sync_activity_state()


func is_edible() -> bool:
	return _edible and not _consumed


func is_consumed() -> bool:
	return _consumed


func _get_target_core_radius(hit: Object) -> float:
	var radius := MELEE_HIT_RADIUS
	if hit and hit.has_method("get_damage_radius"):
		radius = float(hit.call("get_damage_radius"))
	return maxf(1.0, radius)


func _sync_activity_state() -> void:
	if not is_node_ready():
		return
	set_physics_process(not _consumed)
	if shoot_timer:
		shoot_timer.paused = _frozen or _edible or _consumed


func _apply_edible_visual_state() -> void:
	if not _sprite:
		return
	if _edible:
		_sprite.modulate = edible_tint
		_sprite.scale = _base_sprite_scale * 1.06
	else:
		_restore_normal_visual_state()


func _restore_normal_visual_state() -> void:
	if not _sprite or _consumed or _edible:
		return
	_sprite.modulate = _base_sprite_modulate
	_sprite.scale = _base_sprite_scale


func _update_edible_visual(delta: float) -> void:
	if not _sprite:
		return
	_fever_visual_time += maxf(delta, 0.0)
	var pulse := 1.06 + sin(_fever_visual_time * 9.0) * 0.055
	var glow := 0.82 + sin(_fever_visual_time * 7.0) * 0.12
	_sprite.scale = _base_sprite_scale * pulse
	_sprite.modulate = Color(
		minf(edible_tint.r * glow + 0.12, 1.0),
		minf(edible_tint.g * glow + 0.12, 1.0),
		minf(edible_tint.b * glow + 0.12, 1.0),
		_base_sprite_modulate.a
	)

# ----------------------------------------------------
# 射擊邏輯
# ----------------------------------------------------
func _shoot():
	if _frozen or _edible or _consumed:
		return
	# 檢查目標是否有效、是否有投射物場景
	if not is_instance_valid(target) or not projectile_scene: return
	if get_tree().get_nodes_in_group("EnemyProjectiles").size() >= max_global_projectiles:
		return
	var base_dir: Vector2 = (target.global_position - muzzle.global_position).normalized()
	if base_dir.length() < 0.001:
		base_dir = Vector2.RIGHT

	if telegraph_enabled and stage >= telegraph_stage_min:
		if _telegraphing:
			return
		_telegraphing = true
		_show_telegraph(base_dir)
		await get_tree().create_timer(max(0.05, telegraph_time)).timeout
		_hide_telegraph()
		_telegraphing = false
		# 可能在等待期間被凍結/死亡
		if _frozen or _edible or _consumed or not is_instance_valid(target):
			return
		_fire_projectiles(base_dir)
		return

	_fire_projectiles(base_dir)


func _show_telegraph(base_dir: Vector2) -> void:
	if not _telegraph_line or not muzzle:
		return
	# 在敵人本地座標畫線（Line2D points 是 local）
	var from_local: Vector2 = to_local(muzzle.global_position)
	var far: float = 1200.0
	var to_local_pos: Vector2 = from_local + base_dir * far
	_telegraph_line.clear_points()
	_telegraph_line.add_point(from_local)
	_telegraph_line.add_point(to_local_pos)
	_telegraph_line.visible = true


func _hide_telegraph() -> void:
	if _telegraph_line:
		_telegraph_line.visible = false


func _fire_projectiles(base_dir: Vector2) -> void:
	var shots: int = maxi(1, burst_count)
	var spread_rad: float = deg_to_rad(spread_degrees)
	var start: float = -spread_rad * 0.5
	var step: float = 0.0
	if shots > 1:
		step = spread_rad / float(shots - 1)

	for i in range(shots):
		var dir: Vector2 = base_dir.rotated(start + step * float(i))
		var main = get_tree().get_current_scene()
		if main and main.has_method("spawn_enemy_projectile"):
			main.call("spawn_enemy_projectile", projectile_scene, muzzle.global_position, dir * projectile_speed, projectile_speed, projectile_damage, projectile_texture)
			continue
		var projectile = projectile_scene.instantiate()
		get_parent().add_child(projectile) # 將子彈加到 Main Scene 根節點
		projectile.global_position = muzzle.global_position
		projectile.speed = projectile_speed
		projectile.damage = projectile_damage
		var shot_velocity := dir * projectile_speed
		if projectile.has_method("set_motion"):
			projectile.call("set_motion", shot_velocity)
		else:
			projectile.velocity = shot_velocity
			projectile.global_rotation = dir.angle()
		if projectile_texture:
			var spr := projectile.get_node_or_null("Sprite2D") as Sprite2D
			if spr:
				spr.texture = projectile_texture

# ----------------------------------------------------
# 碰撞邏輯 (近戰攻擊)
# ----------------------------------------------------
func _on_body_entered(body):
	_deal_melee_hit(body)


func _on_area_entered(area: Area2D) -> void:
	_deal_melee_hit(area)


func _deal_melee_hit(hit: Object) -> void:
	if _consumed or not hit:
		return
	if not (hit.is_in_group("Player") or hit.has_method("apply_damage")):
		return

	var distance_to_hit := INF
	if hit is Node2D:
		distance_to_hit = global_position.distance_to((hit as Node2D).global_position)

	# FEVER ownership stays atomic in BlackHole: an overlap can never both score
	# and damage the player, even during the one-frame state handoff.
	if _edible or (hit.has_method("is_fever_active") and bool(hit.call("is_fever_active"))):
		if distance_to_hit <= edible_capture_radius:
			_try_target_swallow(hit)
		return

	if distance_to_hit > _get_target_core_radius(hit):
		return
	if _contact_cooldown_left > 0.0 or _pending_destroy:
		return
	_contact_cooldown_left = melee_hit_cooldown
	_pending_destroy = true
	if hit.has_method("apply_damage"):
		hit.call("apply_damage", damage)
	if hit.has_method("shrink_and_eject"):
		hit.call("shrink_and_eject", shrink_amount, eject_count)
	queue_free()


func _try_target_swallow(hit: Object) -> bool:
	if _consumed or not hit or not hit.has_method("try_swallow_enemy"):
		return false
	var accepted := bool(hit.call("try_swallow_enemy", self))
	if not accepted:
		return false
	# BlackHole normally starts the tween while awarding the kill. Keep the
	# interface safe for any alternate player implementation.
	if not _consumed and not is_queued_for_deletion():
		var sink_position := global_position
		if hit is Node2D:
			sink_position = (hit as Node2D).global_position
		begin_swallowed(sink_position)
	return true


func begin_swallowed(sink_position: Vector2, duration: float = 0.16) -> bool:
	if _consumed:
		return false
	_consumed = true
	_edible = false
	_pending_destroy = true
	remove_from_group("Enemies")
	set_physics_process(false)
	if shoot_timer:
		shoot_timer.stop()
	if _telegraph_line:
		_telegraph_line.visible = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if _collision_shape:
		_collision_shape.set_deferred("disabled", true)

	var tween_duration := maxf(duration, 0.05)
	var swallow_tween := create_tween().set_parallel()
	swallow_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	swallow_tween.tween_property(self, "global_position", sink_position, tween_duration)
	swallow_tween.tween_property(self, "scale", _base_scale * 0.04, tween_duration)
	swallow_tween.tween_property(self, "modulate:a", 0.0, tween_duration)
	swallow_tween.finished.connect(queue_free)
	return true


func set_stage(new_stage: int) -> void:
	stage = clampi(new_stage, 0, 5)
	_set_stage_params(stage)


func _set_stage_params(s: int) -> void:
	# 依通緝等級設計難度階段：移速/近戰傷害/射速/子彈速度&傷害/子彈外觀/散射
	# 先更新敵人本體外觀
	if _sprite:
		var tex: Texture2D = null
		if stage_enemy_textures.size() > s and stage_enemy_textures[s]:
			tex = stage_enemy_textures[s]
		elif _default_enemy_texture:
			tex = _default_enemy_texture
		if tex:
			_sprite.texture = tex

	match s:
		0:
			move_speed = 140.0
			damage = 8.0
			shoot_interval = 2.2
			projectile_speed = 420.0
			projectile_damage = 5.0
			burst_count = 1
			spread_degrees = 0.0
			projectile_texture = preload("res://Scenes/黑洞遊戲_子彈圖案.png")
		1:
			move_speed = 165.0
			damage = 10.0
			shoot_interval = 1.8
			projectile_speed = 480.0
			projectile_damage = 6.0
			burst_count = 1
			spread_degrees = 0.0
			projectile_texture = preload("res://Scenes/黑洞遊戲_敵人圖案.png")
		2:
			move_speed = 200.0
			damage = 12.0
			shoot_interval = 1.4
			projectile_speed = 560.0
			projectile_damage = 7.5
			burst_count = 1
			spread_degrees = 0.0
			projectile_texture = preload("res://Scenes/黑洞遊戲_子彈版本2_能量脈衝.png")
		3:
			move_speed = 240.0
			damage = 14.0
			shoot_interval = 1.1
			projectile_speed = 650.0
			projectile_damage = 9.0
			burst_count = 2
			spread_degrees = 10.0
			projectile_texture = preload("res://Scenes/黑洞遊戲_子彈版本3_閃電.png")
		4:
			move_speed = 290.0
			damage = 16.0
			shoot_interval = 0.85
			projectile_speed = 740.0
			projectile_damage = 11.5
			burst_count = 3
			spread_degrees = 16.0
			projectile_texture = preload("res://Scenes/黑洞遊戲_子彈版本3_閃電.png")
		5:
			move_speed = 340.0
			damage = 18.0
			shoot_interval = 0.65
			projectile_speed = 860.0
			projectile_damage = 14.5
			burst_count = 3
			spread_degrees = 22.0
			projectile_texture = preload("res://Scenes/黑洞遊戲_子彈版本4_冰霜.png")

	if shoot_timer:
		shoot_timer.wait_time = shoot_interval
