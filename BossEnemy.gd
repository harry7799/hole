extends Area2D
class_name BossEnemy
## Boss 敵人 — 多段血量 + 多攻擊模式
## 在黑洞通緝等級 5 時出現，帶來最終挑戰。

# ============================================================
# 狀態機
# ============================================================
enum BossState { ENTERING, ORBITING, CHARGING, SPIRAL_SHOOT, SUMMONING, STUNNED, DYING }

# ============================================================
# 可調參數
# ============================================================
@export var projectile_scene: PackedScene

# ============================================================
# 運行狀態
# ============================================================
var _state: BossState = BossState.ENTERING
var _hp: float = GameConfig.BOSS_MAX_HP
var _max_hp: float = GameConfig.BOSS_MAX_HP
var target: Node2D = null

# Orbit
var _orbit_angle: float = 0.0

# Charge
var _charge_dir: Vector2 = Vector2.ZERO
var _charge_timer: float = 0.0
const CHARGE_DURATION: float = 0.7

# Spiral shoot
var _spiral_angle_offset: float = 0.0
var _spiral_shots_fired: int = 0
const SPIRAL_WAVES: int = 5
const SPIRAL_WAVE_INTERVAL: float = 0.25
var _spiral_wave_timer: float = 0.0

# Summon
var _summon_requested: bool = false

# State timers
var _state_timer: float = 0.0
var _enter_speed: float = 300.0

# Attack cycle
var _attack_index: int = 0
const ATTACK_CYCLE: Array = [&"ORBIT", &"SPIRAL", &"ORBIT", &"CHARGE", &"ORBIT", &"SUMMON"]

# Pull damage cooldown (BlackHole dealing damage to boss)
var _pull_damage_cd: float = 0.0

# Frozen (hourglass)
var _frozen: bool = false

# Visual
var _sprite: Sprite2D = null
var _hp_bar_bg: ColorRect = null
var _hp_bar_fill: ColorRect = null
const HP_BAR_WIDTH: float = 120.0
const HP_BAR_HEIGHT: float = 8.0

# ============================================================
# 訊號
# ============================================================
signal boss_hp_changed(current_hp: float, max_hp: float)
signal boss_defeated(boss: BossEnemy)
signal boss_summon_requested(boss_position: Vector2)

# ============================================================
# 介面方法（與 Enemy.gd 相容）
# ============================================================
func is_enemy() -> bool:
	return true

func is_boss() -> bool:
	return true

func get_score_value() -> float:
	return GameConfig.BOSS_SCORE_VALUE

func set_target(t: Node2D) -> void:
	target = t

func set_frozen(frozen: bool) -> void:
	_frozen = frozen

func set_stage(_s: int) -> void:
	pass # Boss 不使用 stage 系統

# ============================================================
# 生命週期
# ============================================================
func _ready() -> void:
	add_to_group("Enemies")
	add_to_group("Bosses")
	_build_visuals()
	_build_hp_bar()
	# 進場：從畫面外飛向目標附近
	_state = BossState.ENTERING
	_state_timer = 0.0

func _build_visuals() -> void:
	# 使用現有最高級敵人貼圖，放大+紅色調
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if not _sprite:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		add_child(_sprite)
	_sprite.scale = Vector2(2.5, 2.5)
	_sprite.modulate = Color(1.0, 0.3, 0.2, 1.0) # 紅橙色

func _build_hp_bar() -> void:
	# 頭頂血條
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	_hp_bar_bg.position = Vector2(-HP_BAR_WIDTH * 0.5, -140.0)
	_hp_bar_bg.color = Color(0.15, 0.15, 0.15, 0.85)
	add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	_hp_bar_fill.position = Vector2(-HP_BAR_WIDTH * 0.5, -140.0)
	_hp_bar_fill.color = Color(0.9, 0.15, 0.1, 1.0)
	add_child(_hp_bar_fill)

func _update_hp_bar() -> void:
	if _hp_bar_fill:
		var ratio: float = clampf(_hp / _max_hp, 0.0, 1.0)
		_hp_bar_fill.size.x = HP_BAR_WIDTH * ratio
		# 色彩漸變：綠 → 黃 → 紅
		if ratio > 0.5:
			_hp_bar_fill.color = Color(0.9, 0.15, 0.1, 1.0)
		elif ratio > 0.25:
			_hp_bar_fill.color = Color(1.0, 0.6, 0.0, 1.0)
		else:
			_hp_bar_fill.color = Color(1.0, 0.0, 0.0, 1.0)

# ============================================================
# 主要處理
# ============================================================
func _physics_process(delta: float) -> void:
	if _frozen:
		return
	if not is_instance_valid(target):
		return

	_pull_damage_cd = maxf(0.0, _pull_damage_cd - delta)

	match _state:
		BossState.ENTERING:
			_process_entering(delta)
		BossState.ORBITING:
			_process_orbiting(delta)
		BossState.CHARGING:
			_process_charging(delta)
		BossState.SPIRAL_SHOOT:
			_process_spiral_shoot(delta)
		BossState.SUMMONING:
			_process_summoning(delta)
		BossState.STUNNED:
			_process_stunned(delta)
		BossState.DYING:
			pass # 等待動畫結束由外部 queue_free

# ============================================================
# 狀態處理
# ============================================================
func _process_entering(delta: float) -> void:
	var dir: Vector2 = (target.global_position - global_position).normalized()
	global_position += dir * _enter_speed * delta
	_look_at_target()
	var dist: float = global_position.distance_to(target.global_position)
	if dist <= GameConfig.BOSS_ORBIT_RADIUS + 50.0:
		_orbit_angle = (global_position - target.global_position).angle()
		_transition_to(BossState.ORBITING)

func _process_orbiting(delta: float) -> void:
	_state_timer += delta
	_orbit_angle += GameConfig.BOSS_ORBIT_SPEED * delta
	var orbit_pos: Vector2 = target.global_position + Vector2.RIGHT.rotated(_orbit_angle) * GameConfig.BOSS_ORBIT_RADIUS
	global_position = global_position.lerp(orbit_pos, 5.0 * delta)
	_look_at_target()
	if _state_timer >= 3.0:
		_advance_attack_cycle()

func _process_charging(delta: float) -> void:
	_charge_timer += delta
	global_position += _charge_dir * GameConfig.BOSS_CHARGE_SPEED * delta
	# 衝鋒碰撞檢測
	if is_instance_valid(target):
		var dist: float = global_position.distance_to(target.global_position)
		var dmg_r: float = 160.0
		if target.has_method("get_damage_radius"):
			dmg_r = float(target.call("get_damage_radius"))
		if dist <= dmg_r:
			if target.has_method("apply_damage"):
				target.call("apply_damage", GameConfig.BOSS_CHARGE_DAMAGE)
			_transition_to(BossState.STUNNED)
			return
	if _charge_timer >= CHARGE_DURATION:
		_transition_to(BossState.ORBITING)

func _process_spiral_shoot(delta: float) -> void:
	_spiral_wave_timer += delta
	if _spiral_shots_fired < SPIRAL_WAVES and _spiral_wave_timer >= SPIRAL_WAVE_INTERVAL:
		_spiral_wave_timer = 0.0
		_fire_spiral_wave()
		_spiral_shots_fired += 1
	_look_at_target()
	if _spiral_shots_fired >= SPIRAL_WAVES:
		_transition_to(BossState.ORBITING)

func _process_summoning(delta: float) -> void:
	_state_timer += delta
	if not _summon_requested:
		_summon_requested = true
		boss_summon_requested.emit(global_position)
	# 短暫停頓後恢復
	if _state_timer >= 1.5:
		_transition_to(BossState.ORBITING)

func _process_stunned(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= 1.0:
		_transition_to(BossState.ORBITING)

# ============================================================
# 狀態轉換
# ============================================================
func _transition_to(new_state: BossState) -> void:
	_state = new_state
	_state_timer = 0.0
	match new_state:
		BossState.CHARGING:
			if is_instance_valid(target):
				_charge_dir = (target.global_position - global_position).normalized()
			_charge_timer = 0.0
		BossState.SPIRAL_SHOOT:
			_spiral_shots_fired = 0
			_spiral_wave_timer = 0.0
			_spiral_angle_offset = randf() * TAU
		BossState.SUMMONING:
			_summon_requested = false
		BossState.STUNNED:
			# 暈眩視覺
			if _sprite:
				var tw: Tween = create_tween()
				tw.tween_property(_sprite, "modulate:a", 0.4, 0.15)
				tw.tween_property(_sprite, "modulate:a", 1.0, 0.15)
				tw.set_loops(3)

func _advance_attack_cycle() -> void:
	var action: StringName = ATTACK_CYCLE[_attack_index % ATTACK_CYCLE.size()]
	_attack_index += 1
	match action:
		&"ORBIT":
			_transition_to(BossState.ORBITING)
		&"CHARGE":
			_transition_to(BossState.CHARGING)
		&"SPIRAL":
			_transition_to(BossState.SPIRAL_SHOOT)
		&"SUMMON":
			_transition_to(BossState.SUMMONING)

func _look_at_target() -> void:
	if not is_instance_valid(target):
		return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	rotation = dir.angle() + PI * 0.5

# ============================================================
# 螺旋射擊
# ============================================================
func _fire_spiral_wave() -> void:
	if not is_instance_valid(target):
		return
	var count: int = GameConfig.BOSS_SPIRAL_BULLET_COUNT
	var angle_step: float = TAU / float(count)
	for i in count:
		var angle: float = _spiral_angle_offset + angle_step * float(i)
		var dir: Vector2 = Vector2.RIGHT.rotated(angle)
		var spawn_pos: Vector2 = global_position + dir * 80.0
		_spawn_projectile(spawn_pos, dir)
	_spiral_angle_offset += 0.4 # 每波旋轉偏移

func _spawn_projectile(pos: Vector2, dir: Vector2) -> void:
	# 使用 Main 的物件池
	if not projectile_scene:
		return
	var main_node: Node = get_tree().current_scene
	if main_node and main_node.has_method("spawn_enemy_projectile"):
		main_node.call("spawn_enemy_projectile",
			projectile_scene, pos, dir,
			GameConfig.BOSS_SPIRAL_SPEED,
			GameConfig.BOSS_SPIRAL_DAMAGE,
			null)
	else:
		var p: Node = projectile_scene.instantiate()
		if p.has_method("setup"):
			p.call("setup", dir, GameConfig.BOSS_SPIRAL_SPEED, GameConfig.BOSS_SPIRAL_DAMAGE, null)
		get_tree().current_scene.add_child(p)
		p.global_position = pos

# ============================================================
# 受傷邏輯 — 由黑洞吞噬觸發
# ============================================================
func take_pull_damage(amount: float) -> void:
	"""黑洞 kill_radius 內造成的吞噬傷害"""
	if _pull_damage_cd > 0.0:
		return
	_pull_damage_cd = GameConfig.BOSS_PULL_HIT_COOLDOWN
	_apply_damage(amount)

func take_shockwave_damage(amount: float) -> void:
	"""衝擊波造成的傷害"""
	_apply_damage(amount)

func _apply_damage(amount: float) -> void:
	if _state == BossState.DYING:
		return
	_hp = maxf(0.0, _hp - amount)
	boss_hp_changed.emit(_hp, _max_hp)
	_update_hp_bar()
	# 受傷閃爍
	if _sprite:
		var tw: Tween = create_tween()
		tw.tween_property(_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.06)
		tw.tween_property(_sprite, "modulate", Color(1.0, 0.3, 0.2, 1.0), 0.06)
	if _hp <= 0.0:
		_die()

func _die() -> void:
	_state = BossState.DYING
	# 死亡動畫：縮小 + 淡出
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.6).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_on_death_finished)

func _on_death_finished() -> void:
	boss_defeated.emit(self)
	queue_free()

# ============================================================
# 外部查詢
# ============================================================
func get_hp_ratio() -> float:
	return clampf(_hp / _max_hp, 0.0, 1.0)

func get_hp() -> float:
	return _hp

func get_max_hp() -> float:
	return _max_hp
