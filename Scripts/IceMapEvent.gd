extends MapEventBase
class_name IceMapEvent
## 冰雪地圖事件：地面打滑慣性變大
##
## 機制：
## - 降低 PlayerController 的 acceleration 和 deceleration（打滑感）
## - 隨機出現「冰凍區域」，進入後慣性更大
## - 冰面上的 SwallowableObject（獵物）也會受影響，滑動更遠
## - 等級越高，全場基礎打滑越嚴重
## - 視覺：淡藍色粒子飄落 + 冰凍區域淡藍圈

const BASE_ACCEL_MULTIPLIER: float = 0.45    # 基礎加速度降低到 45%
const BASE_DECEL_MULTIPLIER: float = 0.35    # 基礎減速降低到 35%（更滑）
const LEVEL_SLIP_FACTOR: float = 0.02        # 每級額外降低

const ICE_PATCH_INTERVAL: float = 8.0        # 冰凍區域生成間隔
const ICE_PATCH_DURATION: float = 12.0       # 冰凍區域持續時間
const ICE_PATCH_RADIUS: float = 180.0        # 冰凍區域半徑
const ICE_PATCH_EXTRA_SLIP: float = 0.5      # 冰凍區域內額外打滑倍率
const MAX_ICE_PATCHES: int = 3               # 同時最大冰凍區數

const PREY_DRIFT_MULTIPLIER: float = 1.8     # 獵物額外漂移倍率
const PREY_DAMPING_REDUCTION: float = 0.4    # 獵物阻尼降低

const SNOW_PARTICLE_COUNT: int = 60          # 雪花粒子數量

var _original_accel: float = 0.0
var _original_decel: float = 0.0
var _ice_patch_timer: float = 0.0
var _ice_patches: Array = []  # [{node: Node2D, timer: float, pos: Vector2}]
var _ice_container: Node2D = null
var _snow_particles: GPUParticles2D = null
var _in_ice_patch: bool = false


func get_event_name() -> String:
	return "❄️ 冰封禁域"

func get_event_description() -> String:
	return "冰面打滑！操控慣性增大，注意冰凍區域。"

func _on_activate() -> void:
	_ice_patches.clear()
	_ice_patch_timer = 5.0  # 5 秒後第一個冰凍區

	# 儲存原始值，套用打滑
	if player_ctrl_ref and is_instance_valid(player_ctrl_ref):
		_original_accel = player_ctrl_ref.acceleration
		_original_decel = player_ctrl_ref.deceleration
		_apply_slip(0)

	# 建立容器
	_ice_container = Node2D.new()
	_ice_container.name = "IcePatches"
	_ice_container.z_index = -500
	if main_ref:
		main_ref.add_child(_ice_container)

	# 建立雪花粒子
	_create_snow_particles()

func _on_deactivate() -> void:
	# 還原操控
	if player_ctrl_ref and is_instance_valid(player_ctrl_ref):
		player_ctrl_ref.acceleration = _original_accel
		player_ctrl_ref.deceleration = _original_decel

	_ice_patches.clear()
	if _ice_container and is_instance_valid(_ice_container):
		_ice_container.queue_free()
		_ice_container = null
	if _snow_particles and is_instance_valid(_snow_particles):
		_snow_particles.queue_free()
		_snow_particles = null

func process(delta: float) -> void:
	if not _active:
		return

	var level: int = _get_level()

	# 動態調整打滑程度
	_apply_slip(level)

	# 更新雪花粒子位置跟隨相機
	if _snow_particles and is_instance_valid(_snow_particles) and camera_ref and is_instance_valid(camera_ref):
		_snow_particles.global_position = camera_ref.global_position

	# 冰凍區域計時
	_ice_patch_timer -= delta
	if _ice_patch_timer <= 0.0:
		_ice_patch_timer = ICE_PATCH_INTERVAL
		_try_spawn_ice_patch()

	# 更新冰凍區域
	_in_ice_patch = false
	var to_remove: Array = []
	for i in range(_ice_patches.size()):
		var patch: Dictionary = _ice_patches[i]
		patch["timer"] -= delta
		_update_ice_patch_visual(patch, delta)
		# 檢測黑洞是否在冰凍區內
		if black_hole_ref and is_instance_valid(black_hole_ref):
			var dist: float = black_hole_ref.global_position.distance_to(patch["pos"])
			if dist < ICE_PATCH_RADIUS:
				_in_ice_patch = true
		if patch["timer"] <= 0.0:
			to_remove.append(i)

	to_remove.reverse()
	for idx in to_remove:
		var patch: Dictionary = _ice_patches[idx]
		if patch.get("node") and is_instance_valid(patch["node"]):
			patch["node"].queue_free()
		_ice_patches.remove_at(idx)

	# 冰凍區額外打滑
	if _in_ice_patch and player_ctrl_ref and is_instance_valid(player_ctrl_ref):
		player_ctrl_ref.acceleration *= ICE_PATCH_EXTRA_SLIP
		player_ctrl_ref.deceleration *= ICE_PATCH_EXTRA_SLIP

func physics_process(delta: float) -> void:
	if not _active:
		return
	# 降低獵物阻尼，讓它們滑得更遠
	_apply_prey_ice_physics()


func _get_level() -> int:
	if black_hole_ref and is_instance_valid(black_hole_ref) and "current_level" in black_hole_ref:
		return int(black_hole_ref.current_level)
	return 0

func _apply_slip(level: int) -> void:
	if not player_ctrl_ref or not is_instance_valid(player_ctrl_ref):
		return
	var slip_mult: float = maxf(0.15, BASE_ACCEL_MULTIPLIER - level * LEVEL_SLIP_FACTOR)
	var decel_mult: float = maxf(0.10, BASE_DECEL_MULTIPLIER - level * LEVEL_SLIP_FACTOR)
	player_ctrl_ref.acceleration = _original_accel * slip_mult
	player_ctrl_ref.deceleration = _original_decel * decel_mult


func _try_spawn_ice_patch() -> void:
	if _ice_patches.size() >= MAX_ICE_PATCHES:
		return
	if not _ice_container or not is_instance_valid(_ice_container):
		return
	if not black_hole_ref or not is_instance_valid(black_hole_ref):
		return

	var bh_pos: Vector2 = black_hole_ref.global_position
	var angle: float = randf() * TAU
	var dist: float = randf_range(100.0, 400.0)
	var spawn_pos: Vector2 = bh_pos + Vector2(cos(angle), sin(angle)) * dist

	var patch_node := Node2D.new()
	patch_node.global_position = spawn_pos
	_ice_container.add_child(patch_node)

	var visual := IceCircleDraw.new()
	visual.circle_radius = ICE_PATCH_RADIUS
	patch_node.add_child(visual)

	_ice_patches.append({
		"node": patch_node,
		"visual": visual,
		"timer": ICE_PATCH_DURATION,
		"pos": spawn_pos,
		"pulse_t": 0.0,
	})


func _update_ice_patch_visual(patch: Dictionary, delta: float) -> void:
	patch["pulse_t"] += delta * 1.5
	var visual = patch.get("visual")
	if not visual or not is_instance_valid(visual):
		return
	var pulse: float = 0.8 + 0.2 * sin(patch["pulse_t"] * TAU)
	visual.modulate.a = pulse * 0.6
	# 淡出
	if patch["timer"] < 2.0:
		visual.modulate.a *= patch["timer"] / 2.0


func _apply_prey_ice_physics() -> void:
	# 每幀降低獵物的 linear_damp，使其滑動更遠
	var prey_nodes: Array = main_ref.get_tree().get_nodes_in_group("Prey") if main_ref else []
	for prey in prey_nodes:
		if prey is RigidBody2D and is_instance_valid(prey):
			prey.linear_damp = maxf(0.0, prey.linear_damp * PREY_DAMPING_REDUCTION)


func _create_snow_particles() -> void:
	if not main_ref:
		return
	_snow_particles = GPUParticles2D.new()
	_snow_particles.name = "SnowParticles"
	_snow_particles.amount = SNOW_PARTICLE_COUNT
	_snow_particles.lifetime = 4.0
	_snow_particles.z_index = 900  # 在大多數東西上方
	_snow_particles.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(400, 10, 0)  # 寬幅發射
	mat.direction = Vector3(0.2, 1, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 80.0
	mat.gravity = Vector3(5, 45, 0)
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.scale_min = 0.8
	mat.scale_max = 2.5
	mat.color = Color(0.85, 0.92, 1.0, 0.4)
	_snow_particles.process_material = mat

	# 小白點作為雪花
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.9))
	var tex := ImageTexture.create_from_image(img)
	_snow_particles.texture = tex

	main_ref.add_child(_snow_particles)


## 內部繪圖節點：畫冰凍區域圓圈
class IceCircleDraw extends Node2D:
	var circle_radius: float = 180.0

	func _draw() -> void:
		# 半透明冰藍填充
		draw_circle(Vector2.ZERO, circle_radius, Color(0.5, 0.8, 1.0, 0.12))
		# 冰藍外環
		var seg: int = 48
		var prev: Vector2 = Vector2(circle_radius, 0)
		for i in range(1, seg + 1):
			var angle: float = float(i) / float(seg) * TAU
			var next: Vector2 = Vector2(cos(angle), sin(angle)) * circle_radius
			draw_line(prev, next, Color(0.6, 0.85, 1.0, 0.5), 2.0, true)
			prev = next
		# 內部冰花圖案（十字）
		var cross_len: float = circle_radius * 0.4
		var cross_color := Color(0.7, 0.9, 1.0, 0.2)
		draw_line(Vector2(-cross_len, 0), Vector2(cross_len, 0), cross_color, 1.5)
		draw_line(Vector2(0, -cross_len), Vector2(0, cross_len), cross_color, 1.5)
		draw_line(Vector2(-cross_len * 0.7, -cross_len * 0.7), Vector2(cross_len * 0.7, cross_len * 0.7), cross_color, 1.0)
		draw_line(Vector2(-cross_len * 0.7, cross_len * 0.7), Vector2(cross_len * 0.7, -cross_len * 0.7), cross_color, 1.0)

	func _process(_d: float) -> void:
		queue_redraw()
