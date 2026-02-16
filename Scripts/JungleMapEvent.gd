extends MapEventBase
class_name JungleMapEvent
## 叢林地圖事件：藤蔓纏繞敵人
##
## 機制：
## - 定期在玩家附近隨機生成「藤蔓區域」
## - 藤蔓會纏繞（凍結）進入範圍的敵人，持續一段時間
## - 被纏繞的敵人無法移動和攻擊，更容易被吞噬
## - 藤蔓本身也可以被黑洞吞噬獲得小量分數
## - 等級越高，藤蔓生成越頻繁、纏繞持續越久
## - 視覺：綠色生長藤蔓，金色高光纏繞效果

const VINE_SPAWN_INTERVAL_BASE: float = 7.0   # 藤蔓生成基礎間隔
const VINE_LIFETIME: float = 15.0              # 藤蔓存在時間
const VINE_RADIUS: float = 160.0               # 纏繞偵測半徑
const VINE_ENTANGLE_DURATION: float = 4.0      # 纏繞持續時間
const VINE_SCORE_VALUE: float = 15.0           # 被吞噬分數

const LEVEL_INTERVAL_REDUCTION: float = 0.4    # 每級間隔減少
const LEVEL_DURATION_BONUS: float = 0.3        # 每級纏繞持續加成
const MIN_SPAWN_INTERVAL: float = 3.0
const MAX_VINES: int = 4                        # 同時最大藤蔓數

var _vine_timer: float = 0.0
var _vines: Array = []  # [{node: Node2D, timer: float, pos: Vector2, entangled: Array}]
var _vine_container: Node2D = null
var _entangled_map: Dictionary = {}  # enemy_node -> release_timer (float)

func get_event_name() -> String:
	return "🌿 叢林纏繞"

func get_event_description() -> String:
	return "藤蔓纏繞敵人！被纏住的敵人無法行動，更容易吞噬。"

func _on_activate() -> void:
	_vines.clear()
	_entangled_map.clear()
	_vine_timer = 4.0  # 4 秒後第一條藤蔓

	_vine_container = Node2D.new()
	_vine_container.name = "JungleVines"
	_vine_container.z_index = -400
	if main_ref:
		main_ref.add_child(_vine_container)

func _on_deactivate() -> void:
	# 釋放所有被纏繞的敵人
	for enemy in _entangled_map.keys():
		if is_instance_valid(enemy) and enemy.has_method("set_frozen"):
			enemy.call("set_frozen", false)
			_remove_entangle_visual(enemy)
	_entangled_map.clear()
	_vines.clear()
	if _vine_container and is_instance_valid(_vine_container):
		_vine_container.queue_free()
		_vine_container = null

func process(delta: float) -> void:
	if not _active:
		return

	var level: int = _get_level()

	# 藤蔓生成計時
	_vine_timer -= delta
	if _vine_timer <= 0.0:
		var interval: float = maxf(MIN_SPAWN_INTERVAL, VINE_SPAWN_INTERVAL_BASE - level * LEVEL_INTERVAL_REDUCTION)
		_vine_timer = interval
		_try_spawn_vine()

	# 更新所有藤蔓
	var to_remove: Array = []
	for i in range(_vines.size()):
		var vine: Dictionary = _vines[i]
		vine["timer"] -= delta
		_update_vine_visual(vine, delta)
		_check_vine_entangle(vine, level)
		# 檢查是否被黑洞吞噬
		if _check_vine_swallowed(vine):
			to_remove.append(i)
			continue
		if vine["timer"] <= 0.0:
			to_remove.append(i)

	to_remove.reverse()
	for idx in to_remove:
		var vine: Dictionary = _vines[idx]
		if vine.get("node") and is_instance_valid(vine["node"]):
			vine["node"].queue_free()
		_vines.remove_at(idx)

	# 更新纏繞計時
	var release_list: Array = []
	for enemy in _entangled_map.keys():
		if not is_instance_valid(enemy):
			release_list.append(enemy)
			continue
		_entangled_map[enemy] -= delta
		if _entangled_map[enemy] <= 0.0:
			release_list.append(enemy)

	for enemy in release_list:
		if is_instance_valid(enemy) and enemy.has_method("set_frozen"):
			enemy.call("set_frozen", false)
			_remove_entangle_visual(enemy)
		_entangled_map.erase(enemy)


func _get_level() -> int:
	if black_hole_ref and is_instance_valid(black_hole_ref) and "current_level" in black_hole_ref:
		return int(black_hole_ref.current_level)
	return 0


func _try_spawn_vine() -> void:
	if _vines.size() >= MAX_VINES:
		return
	if not _vine_container or not is_instance_valid(_vine_container):
		return
	if not black_hole_ref or not is_instance_valid(black_hole_ref):
		return

	var bh_pos: Vector2 = black_hole_ref.global_position
	# 在黑洞與敵人之間偏向敵人處生成
	var spawn_pos: Vector2 = bh_pos
	var enemies: Array = main_ref.get_tree().get_nodes_in_group("Enemies") if main_ref else []
	if enemies.size() > 0:
		var nearest_enemy: Node2D = null
		var nearest_dist: float = INF
		for e in enemies:
			if is_instance_valid(e) and e is Node2D:
				var d: float = bh_pos.distance_to(e.global_position)
				if d < nearest_dist and d > 50.0:
					nearest_dist = d
					nearest_enemy = e
		if nearest_enemy:
			# 在黑洞與最近敵人之間靠近敵人的位置
			var mid: Vector2 = bh_pos.lerp(nearest_enemy.global_position, randf_range(0.4, 0.8))
			spawn_pos = mid
		else:
			spawn_pos = bh_pos + Vector2(randf_range(-300, 300), randf_range(-300, 300))
	else:
		spawn_pos = bh_pos + Vector2(randf_range(-250, 250), randf_range(-250, 250))

	var vine_node := Node2D.new()
	vine_node.global_position = spawn_pos
	vine_node.add_to_group("VineNodes")
	_vine_container.add_child(vine_node)

	var visual := VineCircleDraw.new()
	visual.vine_radius = VINE_RADIUS
	vine_node.add_child(visual)

	_vines.append({
		"node": vine_node,
		"visual": visual,
		"timer": VINE_LIFETIME,
		"pos": spawn_pos,
		"grow_t": 0.0,
	})


func _update_vine_visual(vine: Dictionary, delta: float) -> void:
	vine["grow_t"] = minf(vine["grow_t"] + delta * 2.0, 1.0)
	var visual = vine.get("visual")
	if not visual or not is_instance_valid(visual):
		return

	# 生長動畫
	visual.growth_factor = vine["grow_t"]

	# 淡出
	if vine["timer"] < 2.0:
		visual.modulate.a = clampf(vine["timer"] / 2.0, 0.0, 1.0)
	else:
		visual.modulate.a = 1.0


func _check_vine_entangle(vine: Dictionary, level: int) -> void:
	if not main_ref:
		return
	var vine_pos: Vector2 = vine["pos"]
	var enemies: Array = main_ref.get_tree().get_nodes_in_group("Enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if _entangled_map.has(enemy):
			continue  # 已經被纏繞
		var dist: float = enemy.global_position.distance_to(vine_pos)
		if dist < VINE_RADIUS:
			# 纏繞敵人！
			var duration: float = VINE_ENTANGLE_DURATION + level * LEVEL_DURATION_BONUS
			_entangled_map[enemy] = duration
			if enemy.has_method("set_frozen"):
				enemy.call("set_frozen", true)
			_apply_entangle_visual(enemy)


func _check_vine_swallowed(vine: Dictionary) -> bool:
	if not black_hole_ref or not is_instance_valid(black_hole_ref):
		return false
	var kill_radius: float = 30.0  # 預設值
	if "kill_radius" in black_hole_ref:
		kill_radius = black_hole_ref.kill_radius
	var dist: float = black_hole_ref.global_position.distance_to(vine["pos"])
	if dist < kill_radius * 1.2:
		# 被吞噬，給分
		if black_hole_ref.has_signal("object_swallowed"):
			black_hole_ref.emit_signal("object_swallowed", VINE_SCORE_VALUE)
		return true
	return false


func _apply_entangle_visual(enemy: Node) -> void:
	if not is_instance_valid(enemy) or not enemy is CanvasItem:
		return
	# 綠色色調表示被纏繞
	(enemy as CanvasItem).modulate = Color(0.4, 1.0, 0.4, 1.0)


func _remove_entangle_visual(enemy: Node) -> void:
	if not is_instance_valid(enemy) or not enemy is CanvasItem:
		return
	(enemy as CanvasItem).modulate = Color.WHITE


## 內部繪圖節點：畫藤蔓圓圈
class VineCircleDraw extends Node2D:
	var vine_radius: float = 160.0
	var growth_factor: float = 0.0  # 0~1 生長進度
	var _anim_t: float = 0.0

	func _process(delta: float) -> void:
		_anim_t += delta
		queue_redraw()

	func _draw() -> void:
		var r: float = vine_radius * growth_factor
		if r < 5.0:
			return

		# 半透明綠色底
		draw_circle(Vector2.ZERO, r, Color(0.2, 0.6, 0.2, 0.08))

		# 多條藤蔓線
		var vine_count: int = 6
		for v in range(vine_count):
			var base_angle: float = float(v) / float(vine_count) * TAU + _anim_t * 0.2
			_draw_vine_line(base_angle, r)

		# 外圈
		var seg: int = 40
		var prev: Vector2 = Vector2(r, 0)
		for i in range(1, seg + 1):
			var angle: float = float(i) / float(seg) * TAU
			var jitter: float = sin(angle * 6.0 + _anim_t * 2.0) * 5.0
			var next: Vector2 = Vector2(cos(angle), sin(angle)) * (r + jitter)
			draw_line(prev, next, Color(0.3, 0.7, 0.2, 0.45), 2.5, true)
			prev = next

	func _draw_vine_line(base_angle: float, max_r: float) -> void:
		var points: int = 8
		var prev: Vector2 = Vector2.ZERO
		for i in range(1, points + 1):
			var t: float = float(i) / float(points)
			var dist: float = t * max_r * 0.85
			var angle_offset: float = sin(t * PI * 2.0 + _anim_t + base_angle) * 0.4
			var angle: float = base_angle + angle_offset
			var pt: Vector2 = Vector2(cos(angle), sin(angle)) * dist
			var green: float = 0.4 + t * 0.4
			var alpha: float = (1.0 - t * 0.5) * 0.6
			draw_line(prev, pt, Color(0.2, green, 0.15, alpha), 2.0 - t * 0.8, true)
			# 末端小葉子
			if i == points:
				var leaf_size: float = 6.0 + sin(_anim_t * 3.0 + base_angle) * 2.0
				draw_circle(pt, leaf_size, Color(0.3, 0.75, 0.2, alpha * 0.8))
			prev = pt
