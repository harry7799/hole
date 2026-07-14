extends Node
class_name SpawnManager
## Manages all entity spawning, timers, projectile pooling, and enemy stage cycles.
## Created as a child node of Main and receives references via setup().

# ---- References (set via setup()) ----
var _main: Node2D          # Main scene node (for add_child, game state)
var _camera: Camera2D
var _black_hole: Node2D
var object_scene: PackedScene
var enemy_scene: PackedScene

# ---- Timers ----
var spawn_timer: Timer
var enemy_spawn_timer: Timer
var powerup_spawn_timer: Timer
var spawn_rate: float = 1.5

# ---- Spawn limits ----
var prey_base_spawn_count: int = 2
var prey_max_spawn_count: int = 5
var max_prey_alive: int = 90
var max_enemies_alive: int = 22
var max_enemy_projectiles_alive: int = 90

# ---- FEVER hunt pacing ----
var fever_active: bool = false
var fever_enemy_target: int = 8
var fever_spawn_interval: float = 0.55

# ---- Powerup scenes ----
var _magnet_scene: PackedScene = preload("res://Scenes/MagnetItem.tscn")
var _hourglass_scene: PackedScene = preload("res://Scenes/HourglassItem.tscn")
var _shield_scene: PackedScene = preload("res://Scenes/ShieldItem.tscn")
var _score_boost_scene: PackedScene = preload("res://Scenes/ScoreBoostItem.tscn")
var powerup_spawn_interval: float = 14.0
var magnet_duration: float = 10.0
var hourglass_duration: float = 15.0
var shield_duration: float = 8.0
var score_boost_duration: float = 10.0

# ---- Powerup state (read/write by Main for timer countdown) ----
var magnet_time_left: float = 0.0
var hourglass_time_left: float = 0.0
var hourglass_active: bool = false
var shield_time_left: float = 0.0
var score_boost_time_left: float = 0.0

# ---- Boss state ----
var boss_scene: PackedScene = preload("res://Scenes/BossEnemy.tscn")
var boss_active: bool = false        ## 場上是否有 Boss
var boss_instance: Node2D = null     ## 目前場上的 Boss 節點
var boss_spawned_this_run: bool = false  ## 本局是否已經生成過 Boss

# ---- Enemy stage cycle ----
var _enemy_stage_cycle: Array[int] = []

# ---- Wave-based difficulty (Phase 4C) ----
## 波浪式難度：壓力波→喘息波→壓力波 循環
var wave_enabled: bool = true
var wave_pressure_duration: float = 12.0   ## 壓力波持續秒數
var wave_relief_duration: float = 6.0      ## 喘息波持續秒數
var _wave_timer: float = 0.0              ## 當前波次剩餘時間
var _wave_is_pressure: bool = true        ## 目前是否為壓力波
var _wave_spawn_mult: float = 1.0         ## 當前敵人生成速率倍率 (<1=更快, >1=更慢)

# ---- Projectile pool ----
var enable_projectile_pooling: bool = true
var projectile_pool_prewarm: int = 40
var _projectile_pool_root: Node2D = null
var _projectile_pools: Dictionary = {}  # key: PackedScene.resource_path -> Array[Area2D]

# ---- Loot Goblin (Phase 4D) ----
var _loot_goblin_scene: PackedScene = preload("res://Scenes/LootGoblin.tscn")
var _loot_goblin_timer: float = 0.0
var loot_goblin_interval_min: float = 30.0  ## 最短間隔
var loot_goblin_interval_max: float = 50.0  ## 最長間隔
var loot_goblin_min_wanted: int = 2         ## 至少通緝幾級才生成

# ---- Group cache (per-frame) ----
var _cached_groups: Dictionary = {}
var _cache_frame: int = -1

# ===========================================================
# Setup
# ===========================================================

func setup(main: Node2D, cam: Camera2D, bh: Node2D,
		obj_scene: PackedScene, enemy_sc: PackedScene,
		pool_enabled: bool = true, pool_prewarm: int = 40) -> void:
	_main = main
	_camera = cam
	_black_hole = bh
	object_scene = obj_scene
	enemy_scene = enemy_sc
	enable_projectile_pooling = pool_enabled
	projectile_pool_prewarm = pool_prewarm
	# Copy export-style tuning from Main if available
	if main.get("prey_base_spawn_count") != null:
		prey_base_spawn_count = int(main.prey_base_spawn_count)
	if main.get("prey_max_spawn_count") != null:
		prey_max_spawn_count = int(main.prey_max_spawn_count)
	if main.get("max_prey_alive") != null:
		max_prey_alive = int(main.max_prey_alive)
	if main.get("max_enemies_alive") != null:
		max_enemies_alive = int(main.max_enemies_alive)
	if main.get("max_enemy_projectiles_alive") != null:
		max_enemy_projectiles_alive = int(main.max_enemy_projectiles_alive)
	if main.get("powerup_spawn_interval") != null:
		powerup_spawn_interval = float(main.powerup_spawn_interval)
	if main.get("magnet_duration") != null:
		magnet_duration = float(main.magnet_duration)
	if main.get("hourglass_duration") != null:
		hourglass_duration = float(main.hourglass_duration)
	_create_timers()
	_setup_pools()


# ===========================================================
# Timers
# ===========================================================

func _create_timers() -> void:
	spawn_timer = Timer.new()
	add_child(spawn_timer)
	spawn_timer.wait_time = spawn_rate
	spawn_timer.autostart = false
	spawn_timer.one_shot = false
	spawn_timer.timeout.connect(_spawn_object)

	enemy_spawn_timer = Timer.new()
	add_child(enemy_spawn_timer)
	enemy_spawn_timer.wait_time = 8.0
	enemy_spawn_timer.timeout.connect(_spawn_enemy)

	powerup_spawn_timer = Timer.new()
	add_child(powerup_spawn_timer)
	powerup_spawn_timer.wait_time = powerup_spawn_interval
	powerup_spawn_timer.autostart = false
	powerup_spawn_timer.one_shot = false
	powerup_spawn_timer.timeout.connect(_spawn_powerup)


func start_timers() -> void:
	if spawn_timer:
		spawn_timer.start()
	if enemy_spawn_timer:
		enemy_spawn_timer.start()
	if powerup_spawn_timer:
		powerup_spawn_timer.start()


func stop_timers() -> void:
	if spawn_timer:
		spawn_timer.stop()
	if enemy_spawn_timer:
		enemy_spawn_timer.stop()
	if powerup_spawn_timer:
		powerup_spawn_timer.stop()


func set_fever_active(active: bool) -> void:
	fever_active = active
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy.has_method("is_boss") and bool(enemy.call("is_boss")):
			continue
		if enemy.has_method("set_edible"):
			enemy.call("set_edible", active)

	if not enemy_spawn_timer:
		return
	if fever_active:
		enemy_spawn_timer.wait_time = fever_spawn_interval
		enemy_spawn_timer.start()
		# Prime one dense wave immediately; the normal cap still applies.
		_spawn_enemy()
	elif _main and bool(_main.get("game_started")):
		update_enemy_spawning(int(_main.wanted_level))
	else:
		enemy_spawn_timer.stop()


func reset_powerup_state() -> void:
	magnet_time_left = 0.0
	hourglass_time_left = 0.0
	hourglass_active = false
	shield_time_left = 0.0
	score_boost_time_left = 0.0
	fever_active = false
	# Boss reset
	boss_active = false
	boss_instance = null
	boss_spawned_this_run = false
	# Wave reset
	_wave_timer = wave_pressure_duration
	_wave_is_pressure = true
	_wave_spawn_mult = 1.0
	# Loot Goblin reset
	_loot_goblin_timer = randf_range(loot_goblin_interval_min, loot_goblin_interval_max)

# ===========================================================
# Wave-based difficulty cycle (Phase 4C)
# ===========================================================

func _process(delta: float) -> void:
	if not _main or not _main.game_started or _main.is_game_over:
		return
	# Wave-based difficulty
	if wave_enabled:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_wave_is_pressure = not _wave_is_pressure
			if _wave_is_pressure:
				_wave_timer = wave_pressure_duration
				_wave_spawn_mult = 0.7  # 敵人生成加快（timer 乘以 0.7）
			else:
				_wave_timer = wave_relief_duration
				_wave_spawn_mult = 1.8  # 喘息波：敵人生成放慢
				# 喘息波開始時額外生成獵物讓玩家補血
				_spawn_relief_prey()
			_apply_wave_to_enemy_timer()
	# Loot Goblin spawning
	if _main.wanted_level >= loot_goblin_min_wanted:
		_loot_goblin_timer -= delta
		if _loot_goblin_timer <= 0.0:
			_spawn_loot_goblin()
			_loot_goblin_timer = randf_range(loot_goblin_interval_min, loot_goblin_interval_max)


func _spawn_relief_prey() -> void:
	"""喘息波開始時額外生成一批獵物"""
	if not object_scene:
		return
	var extra: int = clampi(prey_base_spawn_count + 2, 2, 6)
	for _i in range(extra):
		var prey_now := _get_cached_group("Prey").size()
		if prey_now >= max_prey_alive:
			break
		var obj = object_scene.instantiate()
		obj.global_position = get_spawn_position()
		if obj is RigidBody2D and _black_hole:
			var to_bh: Vector2 = _black_hole.global_position - obj.global_position
			var dir_to_bh: Vector2 = to_bh.normalized() if to_bh.length() > 0.001 else Vector2.RIGHT
			var random_dir := Vector2.RIGHT.rotated(randf() * TAU)
			var drift := random_dir * randf_range(60.0, 200.0)
			var away_bias := (-dir_to_bh) * randf_range(20.0, 120.0)
			obj.linear_velocity = drift + away_bias
		_main.add_child(obj)


func _apply_wave_to_enemy_timer() -> void:
	"""將波浪倍率套用到敵人生成計時器"""
	if not enemy_spawn_timer:
		return
	if fever_active:
		enemy_spawn_timer.wait_time = fever_spawn_interval
		return
	var wl: int = 0
	if _main:
		wl = int(_main.wanted_level)
	var base_wait: float = 8.0
	match wl:
		0: base_wait = 8.0
		1: base_wait = 4.5
		2: base_wait = 2.8
		3: base_wait = 1.7
		4: base_wait = 1.0
		5: base_wait = 0.6
	enemy_spawn_timer.wait_time = maxf(0.3, base_wait * _wave_spawn_mult)


func _spawn_loot_goblin() -> void:
	"""生成寶藏哥布林（稀有逃跑型獵物）"""
	if not _loot_goblin_scene or not _main:
		return
	# 場上最多 1 隻
	var existing: int = _get_cached_group("LootGoblins").size()
	if existing >= 1:
		return
	var goblin: Node2D = _loot_goblin_scene.instantiate()
	goblin.global_position = get_spawn_position()
	if goblin.has_method("set_target") and _black_hole:
		goblin.set_target(_black_hole)
	_main.add_child(goblin)
	# 通知玩家
	if _main.has_method("_show_toast"):
		_main._show_toast("⭐ 寶藏哥布林出現！", Color(1.0, 0.85, 0.2))

# ===========================================================
# Group cache (same per-frame cache as Main)
# ===========================================================

func _get_cached_group(group_name: String) -> Array[Node]:
	var frame := Engine.get_process_frames()
	if frame != _cache_frame:
		_cached_groups.clear()
		_cache_frame = frame
	if _cached_groups.has(group_name):
		return _cached_groups[group_name]
	var nodes: Array[Node] = []
	for n in get_tree().get_nodes_in_group(group_name):
		nodes.append(n)
	_cached_groups[group_name] = nodes
	return nodes


# ===========================================================
# Spawn position
# ===========================================================

func get_spawn_position() -> Vector2:
	var center := _camera.global_position if _camera else Vector2.ZERO
	var vp := get_viewport().get_visible_rect().size
	var angle := randf() * TAU
	var zoom_scale := 1.0
	if _camera:
		zoom_scale = 1.0 / max(0.001, min(_camera.zoom.x, _camera.zoom.y))
	var radius := maxf(vp.x, vp.y) * 0.7 * zoom_scale
	return center + Vector2(cos(angle), sin(angle)) * radius


# ===========================================================
# Spawn functions
# ===========================================================

func _spawn_object() -> void:
	if not _main.game_started or not object_scene or _main.is_game_over:
		return
	var prey_now := _get_cached_group("Prey").size()
	if prey_now >= max_prey_alive:
		return
	var lv := 1
	if _black_hole:
		lv = int(_black_hole.get("current_level"))
		if lv <= 0:
			lv = 1
	@warning_ignore("integer_division")
	var spawn_count: int = clampi(prey_base_spawn_count + lv / 10, 1, prey_max_spawn_count)
	spawn_count = min(spawn_count, max(0, max_prey_alive - prey_now))
	for i in range(spawn_count):
		var obj = object_scene.instantiate()
		obj.global_position = get_spawn_position()
		if obj is RigidBody2D and _black_hole:
			var to_bh: Vector2 = _black_hole.global_position - obj.global_position
			var dir_to_bh: Vector2 = to_bh.normalized() if to_bh.length() > 0.001 else Vector2.RIGHT
			var random_dir := Vector2.RIGHT.rotated(randf() * TAU)
			var drift := random_dir * randf_range(60.0, 200.0)
			var away_bias := (-dir_to_bh) * randf_range(20.0, 120.0)
			obj.linear_velocity = drift + away_bias
		_main.add_child(obj)


func _spawn_enemy() -> void:
	if not _main.game_started or not enemy_scene or _main.is_game_over:
		return
	var enemies_now: int = _get_cached_group("Enemies").size()
	if enemies_now >= max_enemies_alive:
		return
	var wl: int = _main.wanted_level
	var desired: int = 2
	match wl:
		0: desired = 2
		1: desired = 3
		2: desired = 5
		3: desired = 7
		4: desired = 9
		5: desired = 11
	if fever_active:
		desired = maxi(desired, fever_enemy_target)
	desired = clampi(desired, 1, max_enemies_alive)
	if enemies_now >= desired:
		return
	var burst_cap := 4 if fever_active else 3
	var spawn_count: int = clampi(desired - enemies_now, 1, burst_cap)
	var proj_now: int = _get_cached_group("EnemyProjectiles").size()
	if proj_now >= max_enemy_projectiles_alive:
		spawn_count = mini(spawn_count, 1)
	for i in range(spawn_count):
		var enemy = enemy_scene.instantiate()
		enemy.global_position = get_spawn_position()
		if enemy.has_method("set_target") and _black_hole:
			enemy.set_target(_black_hole)
		var stage := next_enemy_stage_for_spawn()
		if enemy.has_method("set_stage"):
			enemy.set_stage(stage)
		enemy.add_to_group("Enemies")
		_main.add_child(enemy)
		_configure_enemy_for_current_state(enemy)


func _configure_enemy_for_current_state(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	if enemy.has_method("is_boss") and bool(enemy.call("is_boss")):
		return
	if enemy.has_method("set_edible"):
		enemy.call("set_edible", fever_active)


func _spawn_powerup() -> void:
	if not _main.game_started or _main.is_game_over:
		return
	# Weighted random: Magnet 35%, Hourglass 30%, Shield 20%, ScoreBoost 15%
	var roll := randf()
	var scene: PackedScene
	if roll < 0.35:
		scene = _magnet_scene
	elif roll < 0.65:
		scene = _hourglass_scene
	elif roll < 0.85:
		scene = _shield_scene
	else:
		scene = _score_boost_scene
	if not scene:
		return
	var item = scene.instantiate()
	item.global_position = get_spawn_position()
	if item is RigidBody2D:
		(item as RigidBody2D).linear_velocity = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(50.0, 120.0)
	_main.add_child(item)


func spawn_campaign_center_enemy(campaign_center: Vector2, proximity: float) -> void:
	if not _main.game_started or not enemy_scene or _main.is_game_over:
		return
	if _get_cached_group("Enemies").size() >= max_enemies_alive:
		return
	if _get_cached_group("EnemyProjectiles").size() >= max_enemy_projectiles_alive:
		return
	if not _camera or not _black_hole:
		return
	var enemy = enemy_scene.instantiate()
	var r_min: float = lerpf(950.0, 520.0, proximity)
	var r_max: float = lerpf(1450.0, 820.0, proximity)
	var a: float = randf() * TAU
	var r: float = randf_range(r_min, r_max)
	enemy.global_position = campaign_center + Vector2(cos(a), sin(a)) * r
	if enemy.has_method("set_target"):
		enemy.set_target(_black_hole)
	if enemy.has_method("set_stage"):
		enemy.set_stage(_main.wanted_level)
	enemy.add_to_group("Enemies")
	_main.add_child(enemy)
	_configure_enemy_for_current_state(enemy)


# ===========================================================
# Boss 生成
# ===========================================================

func try_spawn_boss() -> bool:
	"""嘗試在 wanted >= 5 時生成 Boss。回傳是否成功。"""
	if boss_spawned_this_run or boss_active:
		return false
	if not boss_scene or not _main or not _black_hole:
		return false
	var boss: Node = boss_scene.instantiate()
	boss.global_position = get_spawn_position()
	if boss.has_method("set_target"):
		boss.call("set_target", _black_hole)
	# 連接 Boss 訊號
	if boss.has_signal("boss_defeated"):
		boss.connect("boss_defeated", _on_boss_defeated)
	if boss.has_signal("boss_summon_requested"):
		boss.connect("boss_summon_requested", _on_boss_summon)
	if boss.has_signal("boss_hp_changed"):
		boss.connect("boss_hp_changed", _on_boss_hp_changed)
	boss_instance = boss as Node2D
	boss_active = true
	boss_spawned_this_run = true
	_main.add_child(boss)
	return true

func _on_boss_defeated(_boss: Node) -> void:
	boss_active = false
	boss_instance = null
	# 通知 Main.gd 處理獎勵 UI
	if _main and _main.has_method("_on_boss_defeated"):
		_main.call("_on_boss_defeated")

func _on_boss_summon(boss_pos: Vector2) -> void:
	"""Boss 召喚小兵"""
	for i in GameConfig.BOSS_SUMMON_COUNT:
		if _get_cached_group("Enemies").size() >= max_enemies_alive:
			break
		var enemy: Node = enemy_scene.instantiate()
		var offset := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(100.0, 250.0)
		enemy.global_position = boss_pos + offset
		if enemy.has_method("set_target") and _black_hole:
			enemy.call("set_target", _black_hole)
		if enemy.has_method("set_stage"):
			enemy.call("set_stage", 4)  # 高階敵人
		enemy.add_to_group("Enemies")
		_main.add_child(enemy)
		_configure_enemy_for_current_state(enemy)

func _on_boss_hp_changed(current_hp: float, max_hp: float) -> void:
	if _main and _main.has_method("_on_boss_hp_changed"):
		_main.call("_on_boss_hp_changed", current_hp, max_hp)


# ===========================================================
# Powerup collection / hourglass
# ===========================================================

func on_powerup_collected(powerup_type: StringName) -> void:
	match String(powerup_type):
		"MAGNET":
			magnet_time_left = max(magnet_time_left, magnet_duration)
		"HOURGLASS":
			_activate_hourglass(hourglass_duration)
		"SHIELD":
			shield_time_left = max(shield_time_left, shield_duration)
			_activate_shield()
		"SCORE_BOOST":
			score_boost_time_left = max(score_boost_time_left, score_boost_duration)
		_:
			pass


func _activate_hourglass(duration: float) -> void:
	hourglass_time_left = max(hourglass_time_left, duration)
	if hourglass_active:
		return
	hourglass_active = true
	set_combat_frozen(true)


func _activate_shield() -> void:
	# Notify BlackHole to enable damage immunity
	if _black_hole and _black_hole.has_method("set_shield_active"):
		_black_hole.set_shield_active(true)


func set_combat_frozen(frozen: bool) -> void:
	for e in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(e):
			continue
		if e.has_method("set_frozen"):
			e.set_frozen(frozen)
		else:
			e.set_physics_process(not frozen)
	for p in get_tree().get_nodes_in_group("EnemyProjectiles"):
		if is_instance_valid(p):
			p.set_physics_process(not frozen)


# ===========================================================
# Enemy stage cycle
# ===========================================================

func rebuild_enemy_stage_cycle(wl: int) -> void:
	_enemy_stage_cycle.clear()
	if wl <= 0:
		return
	var bag_size: int = 10
	var newest_count: int = int(round(float(bag_size) * 0.7))
	newest_count = clampi(newest_count, 1, bag_size)
	var older_count: int = maxi(0, bag_size - newest_count)
	for _i in range(newest_count):
		_enemy_stage_cycle.append(wl)
	if wl <= 1:
		for _j in range(older_count):
			_enemy_stage_cycle.append(wl)
	else:
		for _j in range(older_count):
			_enemy_stage_cycle.append(randi_range(1, wl - 1))
	_enemy_stage_cycle.shuffle()


func next_enemy_stage_for_spawn() -> int:
	var wl: int = _main.wanted_level
	if wl <= 0:
		return 0
	if _enemy_stage_cycle.is_empty():
		rebuild_enemy_stage_cycle(wl)
	if _enemy_stage_cycle.is_empty():
		return wl
	return int(_enemy_stage_cycle.pop_front())


func apply_enemy_stage_to_all(stage: int) -> void:
	for e in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(e):
			continue
		if e.has_method("set_stage"):
			e.set_stage(stage)


func update_enemy_spawning(wl: int) -> void:
	if not enemy_spawn_timer:
		return
	if fever_active:
		enemy_spawn_timer.wait_time = fever_spawn_interval
		enemy_spawn_timer.start()
		return
	var new_wait_time := 8.0
	match wl:
		0: new_wait_time = 8.0
		1: new_wait_time = 4.5
		2: new_wait_time = 2.8
		3: new_wait_time = 1.7
		4: new_wait_time = 1.0
		5: new_wait_time = 0.6
	# 套用波浪倍率
	if wave_enabled:
		new_wait_time = maxf(0.3, new_wait_time * _wave_spawn_mult)
	enemy_spawn_timer.wait_time = new_wait_time
	enemy_spawn_timer.start()


# ===========================================================
# Projectile pool
# ===========================================================

func _setup_pools() -> void:
	if _projectile_pool_root and is_instance_valid(_projectile_pool_root):
		return
	_projectile_pool_root = Node2D.new()
	_projectile_pool_root.name = "PoolRoot"
	add_child(_projectile_pool_root)
	if not enable_projectile_pooling:
		return
	if projectile_pool_prewarm <= 0:
		return
	var scene: PackedScene = null
	if enemy_scene:
		var tmp = enemy_scene.instantiate()
		if tmp and tmp.has_method("get"):
			scene = tmp.get("projectile_scene")
		if is_instance_valid(tmp):
			tmp.queue_free()
	if scene and scene is PackedScene:
		for i in range(projectile_pool_prewarm):
			var p = (scene as PackedScene).instantiate()
			if p is Area2D:
				_projectile_pool_root.add_child(p)
				recycle_enemy_projectile(p as Area2D)


func spawn_enemy_projectile(projectile_scene: PackedScene, pos: Vector2, vel: Vector2, spd: float, dmg: float, tex: Texture2D) -> void:
	if not projectile_scene:
		return
	if not enable_projectile_pooling:
		var projectile = projectile_scene.instantiate()
		_main.add_child(projectile)
		if projectile.has_method("setup_for_spawn"):
			projectile.call("setup_for_spawn", pos, vel, spd, dmg, tex)
		else:
			projectile.global_position = pos
			projectile.velocity = vel
			projectile.speed = spd
			projectile.damage = dmg
		return

	var key: String = projectile_scene.resource_path
	var pool: Array = _projectile_pools.get(key, []) as Array
	var p: Area2D = null
	if pool.size() > 0:
		while pool.size() > 0 and (p == null or not is_instance_valid(p)):
			var candidate = pool.pop_back()
			if candidate == null:
				continue
			if not is_instance_valid(candidate):
				continue
			if candidate is Area2D:
				p = candidate as Area2D
		_projectile_pools[key] = pool
	else:
		var inst = projectile_scene.instantiate()
		if inst is Area2D:
			p = inst as Area2D
			_main.add_child(p)
			p.set_meta("pool_key", key)
		else:
			return

	if not p or not is_instance_valid(p):
		return
	if p.get_parent() != _main:
		p.get_parent().remove_child(p)
		_main.add_child(p)
	if not p.is_in_group("EnemyProjectiles"):
		p.add_to_group("EnemyProjectiles")
	if p.has_method("setup_for_spawn"):
		p.call("setup_for_spawn", pos, vel, spd, dmg, tex)
	else:
		p.global_position = pos
		p.velocity = vel
		p.speed = spd
		p.damage = dmg
		p.visible = true
		p.set_physics_process(true)
		p.set_process(true)
		p.monitoring = true
		p.monitorable = true


func recycle_enemy_projectile(p: Area2D) -> void:
	if not p or not is_instance_valid(p):
		return
	if not enable_projectile_pooling:
		p.queue_free()
		return
	var key: String = ""
	if p.has_meta("pool_key"):
		key = String(p.get_meta("pool_key"))
	if key == "":
		key = "__default"
	var pool: Array = _projectile_pools.get(key, []) as Array
	if p.is_in_group("EnemyProjectiles"):
		p.remove_from_group("EnemyProjectiles")
	p.visible = false
	p.set_physics_process(false)
	p.set_process(false)
	p.set_deferred("monitoring", false)
	p.set_deferred("monitorable", false)
	if _projectile_pool_root and is_instance_valid(_projectile_pool_root) and p.get_parent() != _projectile_pool_root:
		call_deferred("_reparent_projectile_to_pool", p)
	pool.append(p)
	_projectile_pools[key] = pool


func _reparent_projectile_to_pool(p: Area2D) -> void:
	if not p or not is_instance_valid(p):
		return
	if not _projectile_pool_root or not is_instance_valid(_projectile_pool_root):
		return
	var parent := p.get_parent()
	if parent and is_instance_valid(parent) and parent != _projectile_pool_root:
		parent.remove_child(p)
		_projectile_pool_root.add_child(p)


# ===========================================================
# Clearing
# ===========================================================

func clear_all_enemies() -> void:
	for body in get_tree().get_nodes_in_group("Enemies"):
		if is_instance_valid(body):
			body.queue_free()


func clear_enemy_projectiles() -> void:
	for p in get_tree().get_nodes_in_group("EnemyProjectiles"):
		if is_instance_valid(p):
			p.queue_free()
