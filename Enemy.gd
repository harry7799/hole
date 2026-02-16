extends Area2D

# ----------------------------------------------------
# 遊玩數值常數
# ----------------------------------------------------
const MELEE_HIT_RADIUS: float = 140.0

# ----------------------------------------------------
# 資源與節點引用
# ----------------------------------------------------
@export var move_speed: float = 150.0
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

@onready var _sprite := get_node_or_null("Sprite2D") as Sprite2D
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
	return 18.0 + float(stage) * 4.0

@onready var shoot_timer = $ShootTimer # 假設你在 Enemy.tscn 內新增了 Timer 節點
@onready var muzzle = $Muzzle           # 假設你在 Enemy.tscn 內新增了 Marker2D 節點

func set_target(t):
	target = t

func _ready():
	# 確保敵人被加入 Enemies 群組
	add_to_group("Enemies")
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

	# 手機可讀性：高階段射擊前顯示預警線
	_telegraph_line = Line2D.new()
	_telegraph_line.visible = false
	_telegraph_line.width = 5.0
	_telegraph_line.default_color = Color(1, 0.15, 0.15, 0.35)
	_telegraph_line.z_index = 50
	add_child(_telegraph_line)

func _physics_process(delta):
	if _frozen:
		return
	if not is_instance_valid(target): return
	
	# 簡單的追蹤 AI
	var dir = (target.global_position - global_position).normalized()
	position += dir * move_speed * delta
	
	# 旋轉向目標 
	# (假設 Sprite 預設面向上方，所以需要 +90 度來讓子彈朝前)
	rotation = dir.angle() + deg_to_rad(90) 

	# Damage should apply when we reach the black hole core, not when we first enter
	# the huge gravity Area2D.
	if not _pending_destroy and (target.is_in_group("Player") or target.has_method("apply_damage")):
		var r: float = MELEE_HIT_RADIUS
		if target.has_method("get_damage_radius"):
			r = float(target.call("get_damage_radius"))
		if global_position.distance_to(target.global_position) <= r:
			_pending_destroy = true
			_deal_melee_hit(target)


func _process(_delta: float) -> void:
	# Hourglass “time stop” freezes enemy physics; allow Fever hunt by proximity when the player moves into the enemy.
	if not _frozen:
		return
	if _pending_destroy:
		return
	if not is_instance_valid(target):
		return
	if not (target.is_in_group("Player") or target.has_method("apply_damage")):
		return
	if target.has_method("is_fever_active") and bool(target.call("is_fever_active")):
		if not (target is Node2D):
			return
		var r: float = MELEE_HIT_RADIUS
		if target.has_method("get_damage_radius"):
			r = float(target.call("get_damage_radius"))
		if global_position.distance_to((target as Node2D).global_position) <= r:
			_pending_destroy = true
			if target.has_method("_swallow_body"):
				target.call("_swallow_body", self)
			else:
				queue_free()


func set_frozen(frozen: bool) -> void:
	_frozen = frozen
	set_physics_process(not frozen)
	if shoot_timer:
		shoot_timer.paused = frozen

# ----------------------------------------------------
# 射擊邏輯
# ----------------------------------------------------
func _shoot():
	# 檢查目標是否有效、是否有投射物場景
	if not is_instance_valid(target) or not projectile_scene: return
	if get_tree().get_nodes_in_group("EnemyProjectiles").size() >= max_global_projectiles:
		return
	if _frozen:
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
		if _frozen or not is_instance_valid(target):
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
		projectile.velocity = dir * projectile_speed
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
	if not hit:
		return
	# 檢查是否撞到黑洞 (Player group)
	if hit.is_in_group("Player") or hit.has_method("apply_damage"):
		# 黑洞的吸引範圍碰撞圈很大，避免遠距離「擦到」就算近戰命中
		if hit is Node2D:
			var d: float = global_position.distance_to((hit as Node2D).global_position)
			var r: float = MELEE_HIT_RADIUS
			if hit.has_method("get_damage_radius"):
				r = float(hit.call("get_damage_radius"))
			if d > r:
				return
		# Fever：不造成傷害，直接被吞噬（爽快感）
		if hit.has_method("is_fever_active") and bool(hit.call("is_fever_active")):
			# 若黑洞提供 Fever 吞噬介面就走該介面（可加分/回復穩定度）
			if hit.has_method("_swallow_body") and self is Node2D:
				hit.call("_swallow_body", self)
			else:
				queue_free()
			return
		if hit.has_method("apply_damage"):
			hit.apply_damage(damage)
		if hit.has_method("shrink_and_eject"):
			hit.shrink_and_eject(shrink_amount, eject_count)
		queue_free()


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
