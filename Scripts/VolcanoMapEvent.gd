extends MapEventBase
class_name VolcanoMapEvent
## 火山地圖事件：隨機噴岩漿傷害區域
##
## 機制：
## - 每 ERUPT_INTERVAL 秒，在黑洞附近隨機位置產生「岩漿噴發預警圈」
## - 預警 WARNING_DURATION 秒後爆發，對範圍內的黑洞造成傷害
## - 岩漿區域存在 LAVA_DURATION 秒，持續造成傷害
## - 視覺：紅色半透明圓 + 脈動動畫 + 爆發閃光
## - 等級越高噴發越頻繁，同時存在的岩漿區數量上限 MAX_LAVA_ZONES

const ERUPT_INTERVAL_BASE: float = 6.0     # 基礎噴發間隔
const ERUPT_INTERVAL_MIN: float = 2.5      # 最短間隔
const WARNING_DURATION: float = 1.8        # 預警時間
const LAVA_DURATION: float = 3.0           # 岩漿持續時間
const LAVA_RADIUS: float = 120.0           # 岩漿範圍半徑
const LAVA_DAMAGE_PER_SEC: float = 12.0    # 每秒傷害
const MAX_LAVA_ZONES: int = 5              # 同時最大岩漿區數
const SPAWN_RANGE_MIN: float = 150.0       # 最近生成距離
const SPAWN_RANGE_MAX: float = 500.0       # 最遠生成距離
const RUMBLE_STRENGTH: float = 4.0         # 螢幕震動強度

var _erupt_timer: float = 0.0
var _erupt_interval: float = ERUPT_INTERVAL_BASE
var _lava_zones: Array = []  # [{node: Node2D, state: "warning"|"active", timer: float, radius: float}]
var _lava_container: Node2D = null


func get_event_name() -> String:
	return "🌋 火山噴發"

func get_event_description() -> String:
	return "岩漿會隨機噴發，注意躲避紅色區域！"

func _on_activate() -> void:
	_erupt_timer = 3.0  # 開局 3 秒後第一次噴發
	_erupt_interval = ERUPT_INTERVAL_BASE
	_lava_zones.clear()
	# 建立容器節點
	_lava_container = Node2D.new()
	_lava_container.name = "LavaZones"
	_lava_container.z_index = -500  # 在背景上方，物體下方
	if main_ref:
		main_ref.add_child(_lava_container)

func _on_deactivate() -> void:
	_lava_zones.clear()
	if _lava_container and is_instance_valid(_lava_container):
		_lava_container.queue_free()
		_lava_container = null

func process(delta: float) -> void:
	if not _active or not black_hole_ref or not is_instance_valid(black_hole_ref):
		return

	# 根據黑洞等級調整噴發頻率
	var level: int = 0
	if black_hole_ref.has_method("get") and "current_level" in black_hole_ref:
		level = int(black_hole_ref.current_level)
	_erupt_interval = maxf(ERUPT_INTERVAL_MIN, ERUPT_INTERVAL_BASE - level * 0.3)

	# 噴發計時
	_erupt_timer -= delta
	if _erupt_timer <= 0.0:
		_erupt_timer = _erupt_interval
		_try_spawn_lava()

	# 更新所有岩漿區域
	var to_remove: Array = []
	for i in range(_lava_zones.size()):
		var zone: Dictionary = _lava_zones[i]
		zone["timer"] -= delta

		if zone["state"] == "warning":
			_update_warning_visual(zone, delta)
			if zone["timer"] <= 0.0:
				# 預警結束 → 爆發
				zone["state"] = "active"
				zone["timer"] = LAVA_DURATION
				_on_lava_erupt(zone)
		elif zone["state"] == "active":
			_update_active_visual(zone, delta)
			_check_lava_damage(zone, delta)
			if zone["timer"] <= 0.0:
				to_remove.append(i)

	# 移除過期的岩漿區
	to_remove.reverse()
	for idx in to_remove:
		var zone: Dictionary = _lava_zones[idx]
		if zone.get("node") and is_instance_valid(zone["node"]):
			zone["node"].queue_free()
		_lava_zones.remove_at(idx)


func _try_spawn_lava() -> void:
	if _lava_zones.size() >= MAX_LAVA_ZONES:
		return
	if not _lava_container or not is_instance_valid(_lava_container):
		return

	# 在黑洞附近隨機位置生成
	var bh_pos: Vector2 = black_hole_ref.global_position
	var angle: float = randf() * TAU
	var dist: float = randf_range(SPAWN_RANGE_MIN, SPAWN_RANGE_MAX)
	var spawn_pos: Vector2 = bh_pos + Vector2(cos(angle), sin(angle)) * dist

	# 建立視覺節點
	var zone_node := Node2D.new()
	zone_node.global_position = spawn_pos
	_lava_container.add_child(zone_node)

	# 預警圈（半透明紅色虛線圓）
	var warning_circle := _create_circle_visual(LAVA_RADIUS, Color(1.0, 0.3, 0.1, 0.15), Color(1.0, 0.2, 0.0, 0.6))
	zone_node.add_child(warning_circle)

	var zone_data: Dictionary = {
		"node": zone_node,
		"visual": warning_circle,
		"state": "warning",
		"timer": WARNING_DURATION,
		"radius": LAVA_RADIUS,
		"pos": spawn_pos,
		"pulse_t": 0.0,
	}
	_lava_zones.append(zone_data)


func _create_circle_visual(radius: float, fill_color: Color, ring_color: Color) -> Node2D:
	# 用 _draw 的自訂節點來畫圓
	var visual := LavaCircleDraw.new()
	visual.fill_color = fill_color
	visual.ring_color = ring_color
	visual.circle_radius = radius
	return visual


func _update_warning_visual(zone: Dictionary, delta: float) -> void:
	zone["pulse_t"] += delta * 4.0
	var pulse: float = 0.5 + 0.5 * sin(zone["pulse_t"] * TAU)
	var visual = zone.get("visual")
	if visual and is_instance_valid(visual):
		# 脈動透明度
		var base_alpha: float = lerpf(0.1, 0.4, 1.0 - zone["timer"] / WARNING_DURATION)
		visual.modulate.a = base_alpha + pulse * 0.2
		# 逐漸放大到完整大小
		var scale_t: float = 1.0 - zone["timer"] / WARNING_DURATION
		var s: float = lerpf(0.3, 1.0, scale_t)
		visual.scale = Vector2(s, s)


func _on_lava_erupt(zone: Dictionary) -> void:
	var visual = zone.get("visual")
	if visual and is_instance_valid(visual) and visual is LavaCircleDraw:
		visual.fill_color = Color(1.0, 0.25, 0.0, 0.35)
		visual.ring_color = Color(1.0, 0.6, 0.1, 0.8)
		visual.scale = Vector2.ONE
		visual.queue_redraw()
	# 震動回饋
	Input.vibrate_handheld(25)
	# 輕微螢幕震動
	if camera_ref and is_instance_valid(camera_ref):
		_shake_camera(RUMBLE_STRENGTH, 0.15)


func _update_active_visual(zone: Dictionary, delta: float) -> void:
	zone["pulse_t"] += delta * 2.0
	var visual = zone.get("visual")
	if visual and is_instance_valid(visual):
		var pulse: float = 0.7 + 0.3 * sin(zone["pulse_t"] * TAU)
		visual.modulate.a = pulse
		# 接近消失時淡出
		if zone["timer"] < 0.8:
			visual.modulate.a *= zone["timer"] / 0.8


func _check_lava_damage(zone: Dictionary, delta: float) -> void:
	if not black_hole_ref or not is_instance_valid(black_hole_ref):
		return
	var bh_pos: Vector2 = black_hole_ref.global_position
	var lava_pos: Vector2 = zone["pos"]
	var dist: float = bh_pos.distance_to(lava_pos)
	if dist < zone["radius"]:
		# 在岩漿區域內，造成傷害
		var damage: float = LAVA_DAMAGE_PER_SEC * delta
		if black_hole_ref.has_method("apply_damage"):
			black_hole_ref.apply_damage(damage)


func _shake_camera(strength: float, duration: float) -> void:
	if not camera_ref or not is_instance_valid(camera_ref):
		return
	var orig_offset: Vector2 = camera_ref.offset
	var tween := camera_ref.create_tween()
	var steps: int = int(duration / 0.03)
	for _i in range(steps):
		tween.tween_property(camera_ref, "offset", orig_offset + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), 0.03)
	tween.tween_property(camera_ref, "offset", orig_offset, 0.04)


## 內部繪圖節點：畫岩漿圓圈
class LavaCircleDraw extends Node2D:
	var fill_color: Color = Color(1.0, 0.3, 0.1, 0.15)
	var ring_color: Color = Color(1.0, 0.2, 0.0, 0.6)
	var circle_radius: float = 120.0

	func _draw() -> void:
		# 填充圓
		draw_circle(Vector2.ZERO, circle_radius, fill_color)
		# 外環
		var seg: int = 48
		var prev: Vector2 = Vector2(circle_radius, 0)
		for i in range(1, seg + 1):
			var angle: float = float(i) / float(seg) * TAU
			var next: Vector2 = Vector2(cos(angle), sin(angle)) * circle_radius
			draw_line(prev, next, ring_color, 2.5, true)
			prev = next

	func _process(_d: float) -> void:
		queue_redraw()
