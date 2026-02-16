extends Area2D

# ----------------------------------------------------
# 遊玩數值常數
# ----------------------------------------------------
const ENEMY_CONTACT_DAMAGE: float = 30.0
const FEVER_ENEMY_STABILITY_GAIN: float = 18.0
const GROWTH_ENERGY_DIVISOR: float = 22.0

# ----------------------------------------------------
# 節點引用
# ----------------------------------------------------
@onready var visuals = $Visuals
@onready var collision_shape = $CollisionShape2D
@onready var glitch_particles = $GlitchParticles  # 數據噴出粒子效果 (CPUParticles2D)
@onready var fever_particles = get_node_or_null("GlitchParticles2") as CPUParticles2D

# Skin overlay (because the black hole shader renders SCREEN_TEXTURE, Sprite TEXTURE changes alone are not visible).
var _skin_overlay: Sprite2D = null
var _skin_overlay_spin_deg_per_sec: float = 0.0
var _skin_overlay_color: Color = Color(1, 1, 1, 0.0)
var _skin_strength_mult: float = 1.0
var _skin_aberration_mult: float = 1.0
var _skin_fever_ring_color: Color = Color(1.0, 0.86, 0.25, 1.0)
var _skin_visual_tint: Color = Color(1, 1, 1, 1)
var _skin_ripple_strength_mult: float = 1.0
var _skin_ripple_speed_mult: float = 1.0

# 為了在 Main.gd 之外調整 WorldEnvironment
var main_scene_node: Node2D 
var black_hole_material: ShaderMaterial 
# 【新增】全螢幕效果相關變數
#@onready var full_screen_effect_node: CanvasLayer = null # 引用全螢幕效果節點
@onready var full_screen_effect = get_node("%FullScreenEffect") as Node2D
var full_screen_distort_material: ShaderMaterial = null   # 引用全螢幕 ShaderMaterial

@export var fullscreen_distort_enabled: bool = true

# Debug: 在編輯器 / 測試時強制指派 fallback shader（方便快速驗證）
@export var debug_force_assign_fullscreen_fallback: bool = false

func apply_skin_texture(tex: Texture2D) -> void:
	# NOTE: The BlackHole shader uses SCREEN_TEXTURE for the distortion, so Sprite TEXTURE is not used visually.
	# We keep setting it for completeness, but the visible change comes from the overlay sprite.
	if visuals and tex:
		visuals.texture = tex
	_ensure_skin_overlay()
	if _skin_overlay and is_instance_valid(_skin_overlay):
		_skin_overlay.texture = tex
		_skin_overlay.visible = tex != null
		# Default overlay style if caller only sets a texture.
		_skin_overlay_color = Color(1, 1, 1, 0.55)
		_skin_overlay.modulate = _skin_overlay_color
		_skin_overlay_spin_deg_per_sec = 90.0


func apply_skin_def(def: Dictionary) -> void:
	# Apply a full skin definition from Main.gd: texture + effect knobs.
	if def.is_empty():
		return
	var tex: Texture2D = def.get("texture") as Texture2D
	apply_skin_texture(tex)
	_skin_strength_mult = float(def.get("strength_mult", 1.0))
	_skin_aberration_mult = float(def.get("aberration_mult", 1.0))
	_skin_ripple_strength_mult = float(def.get("ripple_strength_mult", 1.0))
	_skin_ripple_speed_mult = float(def.get("ripple_speed_mult", 1.0))
	_skin_overlay_spin_deg_per_sec = float(def.get("overlay_spin", 0.0))
	var vt: Variant = def.get("visual_tint", Color(1, 1, 1, 1))
	if vt is Color:
		_skin_visual_tint = vt as Color
	else:
		_skin_visual_tint = Color(1, 1, 1, 1)
	var oc: Variant = def.get("overlay_color", Color(1, 1, 1, 1))
	var oa: float = float(def.get("overlay_alpha", 0.0))
	if oc is Color:
		_skin_overlay_color = Color((oc as Color).r, (oc as Color).g, (oc as Color).b, clampf(oa, 0.0, 1.0))
	else:
		_skin_overlay_color = Color(1, 1, 1, clampf(oa, 0.0, 1.0))
	if _skin_overlay and is_instance_valid(_skin_overlay):
		_skin_overlay.modulate = _skin_overlay_color
		_skin_overlay.visible = tex != null and _skin_overlay_color.a > 0.01
	var frc: Variant = def.get("fever_ring_color", _skin_fever_ring_color)
	if frc is Color:
		_skin_fever_ring_color = frc as Color
	# Immediately refresh shader params so the skin "feels" different.
	_update_shader_params()
	_update_instability_visuals()


func _ensure_skin_overlay() -> void:
	if _skin_overlay and is_instance_valid(_skin_overlay):
		return
	_skin_overlay = get_node_or_null("SkinOverlay") as Sprite2D
	if _skin_overlay and is_instance_valid(_skin_overlay):
		return
	_skin_overlay = Sprite2D.new()
	_skin_overlay.name = "SkinOverlay"
	_skin_overlay.centered = true
	_skin_overlay.visible = false
	_skin_overlay.z_index = (visuals.z_index + 2) if visuals else 2
	# Additive blend for a "skin glow" feel.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_skin_overlay.material = mat
	add_child(_skin_overlay)

@export var distort_start_level: int = 1     # 全螢幕扭曲效果開始的等級
@export var max_distort_radius: float = 1.0   # 扭曲效果最大擴散半徑 (1.0 = 全屏)
@export var max_distort_strength: float = 0.05 # 扭曲效果最大強度
@export var max_distort_speed: float = 0.25    # 扭曲漣漪最大速度（降速）

# Fullscreen fallback shader default parameters (editable in Inspector)
@export var fs_fallback_radius: float = 0.5
@export var fs_fallback_strength: float = 0.7
@export var fs_fallback_speed: float = 1.2
@export var fs_fallback_tint: Color = Color(1.0, 0.65, 0.2, 0.45)

# ----------------------------------------------------
# Fever Mode（爽快連吞模式）
# ----------------------------------------------------
signal fever_started(duration: float)
const DEBUG_ENABLE_GLOBAL_FULLSCREEN_TEST: bool = false
signal fever_ended()
signal fever_enemy_combo(combo: int, world_pos: Vector2)

@export var fever_duration_sec: float = 6.5
@export var fever_pull_radius_multiplier: float = 2.0
@export var fever_speed_multiplier: float = 1.5
@export var fever_projectile_absorb_radius: float = 360.0
@export var fever_projectile_absorb_interval_sec: float = 0.08

# Fever rewards: make “hunt mode” feel like Pac-Man.
@export var fever_enemy_score_multiplier: float = 2.0
@export var fever_enemy_time_bonus_sec: float = 0.9
@export var fever_time_cap_multiplier: float = 2.25

# Fever visuals: clear outer halo.
@export var fever_ring_scale_multiplier: float = 0.85
@export var fever_ring_alpha: float = 0.55

# Fullscreen ripple readability boosts.
@export var ripple_strength_boost: float = 1.75
@export var ripple_speed_boost: float = 0.8
@export var fever_ripple_strength_boost: float = 1.35
@export var fever_ripple_speed_boost: float = 1.0

var fever_active: bool = false
var _fever_time_left: float = 0.0
var _fever_absorb_accum: float = 0.0
var _base_visual_modulate: Color = Color(1, 1, 1, 1)
var _fever_particles_restore: Dictionary = {}
var _fever_ring: Sprite2D = null
var _fever_enemy_combo_count: int = 0
var _fever_enemy_scan_ms: int = 0
# ----------------------------------------------------
# 基礎參數
# ----------------------------------------------------
@export var pull_strength: float = 900.0
@export var base_kill_radius: float = 50.0
@export var base_pull_radius: float = 500.0
@export var base_visual_scale: float = 0.5

# High-level readability: reduce/disable the swallow bounce so the camera view doesn't feel like it's shaking/zooming.
@export var swallow_bounce_disable_level: int = 18
@export var swallow_bounce_min_level: int = 1
@export var swallow_bounce_max_k: float = 0.55
var _swallow_bounce_tween: Tween = null

# The black hole's gravity Area2D is huge; damage should only apply near the core.
@export var damage_radius: float = 140.0

# ----------------------------------------------------
# Risk/Reward：Overload（高穩定度獎勵） & 主動釋放熵
# ----------------------------------------------------
@export var overload_threshold: float = 0.8
@export var overload_pull_multiplier: float = 1.2
@export var overload_score_multiplier: float = 2.0

@export var shockwave_stability_cost: float = 28.0
@export var shockwave_radius: float = 420.0
@export var shockwave_push_impulse: float = 520.0
@export var shockwave_stun_time: float = 0.45

signal shockwave_triggered(intensity: float)

@export var base_growth_per_object: float = 6.0
@export var exponential_growth_factor: float = 0.06
@export var growth_per_level: int = 26

@export var max_level: int = 30
@export var final_max_radius: float = 2800.0
@export var visual_growth_factor: float = 1.5

# ----------------------------------------------------
# 【重要】熵值 / 穩定度系統參數
# ----------------------------------------------------
@export var max_stability: float = 100.0
var current_stability: float = 100.0
@export var base_decay_rate: float = 2.2  # 基礎衰減速度（玩家回饋：原本仍偏快）
@export var decay_level_scale: float = 0.08 # 等級額外衰減倍率（原本 0.15 偏重）

# ----------------------------------------------------
# 動態數值
# ----------------------------------------------------
var kill_radius: float = base_kill_radius
var max_pull_radius: float = base_pull_radius

var bodies_in_range: Array[Node2D] = []
var swallowed_count: int = 0
var current_level: int = 1

# Shader dirty-tracking: skip expensive param updates when inputs haven't changed
var _prev_shader_level: int = -1
var _prev_shader_stability: float = -1.0
var _prev_shader_fever: bool = false

# Clamp z indices to rendering server limits
const Z_MAX: int = int(RenderingServer.CANVAS_ITEM_Z_MAX)

# 訊號
signal object_swallowed(score_gain: int) # 傳遞本次獲得的分數增量
signal level_up(new_level: int)
signal reached_max_level()
signal stability_changed(current, max_val) 
signal stability_depleted() 
signal powerup_collected(powerup_type: StringName)
signal damaged(amount: float)
signal swallowed_feedback(energy_gain: float)
signal enemy_killed()  # 敵人被消滅時（Fever 吞噬/衝擊波等）
signal objective_swallowed(objective_id: StringName)


func get_damage_radius() -> float:
	return maxf(40.0, damage_radius)


func disable_fullscreen_distort() -> void:
	if not full_screen_distort_material:
		return
	full_screen_distort_material.set_shader_parameter("distort_radius", 0.0)
	full_screen_distort_material.set_shader_parameter("distort_strength", 0.0)
	full_screen_distort_material.set_shader_parameter("distort_speed", 0.0)
	# 中心點給個合理值，避免某些 shader 用到未更新中心
	full_screen_distort_material.set_shader_parameter("center_uv", Vector2(0.5, 0.5))


func set_fullscreen_distort_enabled(enabled: bool) -> void:
	fullscreen_distort_enabled = enabled
	if not fullscreen_distort_enabled:
		disable_fullscreen_distort()


func reset_for_new_run() -> void:
	# 重置核心數值（供 Main.gd 再來一次/回主頁使用）
	_end_fever(true)
	bodies_in_range.clear()
	swallowed_count = 0
	current_level = 1
	max_pull_radius = base_pull_radius
	kill_radius = base_kill_radius
	# Roguelike: max_stability_offset modifier (character-based)
	var stability_offset: float = 0.0
	if has_node("/root/RoguelikeUpgradeManager"):
		stability_offset = get_node("/root/RoguelikeUpgradeManager").get_modifier("max_stability_offset")
	var effective_max := maxf(20.0, max_stability + stability_offset)
	current_stability = effective_max
	stability_changed.emit(current_stability, effective_max)
	disable_fullscreen_distort()
	_update_collision_and_visuals()
	_update_shader_params()
	# 視覺進化重置
	if glitch_particles and glitch_particles is CPUParticles2D:
		glitch_particles.speed_scale = 1.0

# ----------------------------------------------------
# Godot 內建函式
# ----------------------------------------------------
func _ready():
	# 讓 Enemy / Projectile 可以用群組辨識玩家本體
	add_to_group("Player")
	if visuals:
		_base_visual_modulate = visuals.modulate
	# Prefer a dedicated Fever particle node if present (MainScene adds GlitchParticles2).
	# Otherwise fall back to the built-in GlitchParticles in black_hole.tscn.
	if not fever_particles:
		fever_particles = glitch_particles
	if fever_particles:
		_fever_particles_restore = {
			"texture": fever_particles.texture,
			"modulate": fever_particles.modulate,
			"emitting": fever_particles.emitting,
			"one_shot": fever_particles.one_shot,
			"explosiveness": fever_particles.explosiveness,
			"speed_scale": fever_particles.speed_scale,
			"amount": fever_particles.amount,
			"z_index": fever_particles.z_index,
			"emission_sphere_radius": fever_particles.emission_sphere_radius,
			"scale_amount_min": fever_particles.scale_amount_min,
			"scale_amount_max": fever_particles.scale_amount_max,
		}
	_ensure_skin_overlay()
	# Apply selected skin (if Main.gd provides a def). Otherwise keep default.
	if main_scene_node and main_scene_node.has_method("get_selected_skin_def"):
		var def: Dictionary = main_scene_node.call("get_selected_skin_def") as Dictionary
		if not def.is_empty():
			apply_skin_def(def)
	_ensure_fever_ring()
	# 開局時若有物體一開始就在吸引範圍內，Godot 不一定會發 body_entered
	# 這會導致「卡著不互動」；延遲一幀後主動掃描重疊物體加入追蹤清單
	call_deferred("_bootstrap_overlapping_bodies")

	# 取得黑洞自身材質（用於強度/半徑/色差參數更新）
	if visuals and visuals.material is ShaderMaterial:
		black_hole_material = visuals.material as ShaderMaterial


	# 你原本的所有 _ready 內容保持不變（到 main_scene_node 為止）
	main_scene_node = get_tree().get_first_node_in_group("MainScene")

	# ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
	# 新增：直接抓場景裡的 FullScreenEffect，並在必要時套用跨平台 fallback shader
	if full_screen_effect:
		var color_rect = full_screen_effect.get_node_or_null("CanvasLayer/ColorRect") as ColorRect
		var platform_name: String = OS.get_name()
		var need_fallback: bool = false
		if not color_rect:
			push_error("FullScreenEffect 的 ColorRect 找不到，將使用 fallback shader")
			need_fallback = true
		else:
			# Prefer the existing material unless running on JS/mobile or material missing
			var has_mat = color_rect.material != null

			# Debug override: 強制在編輯器或測試時套用 fallback（方便快速驗證）
			if debug_force_assign_fullscreen_fallback:
				need_fallback = true
				print("Debug: 強制套用 fullscreen fallback shader（debug_force_assign_fullscreen_fallback = true）")

			if not has_mat:
				need_fallback = true

		if fullscreen_distort_enabled:
			full_screen_effect.visible = true
		if need_fallback:
			var fallback_shader_res = ResourceLoader.load("res://Shaders/FullScreenFallback.gdshader")
			if fallback_shader_res and fallback_shader_res is Shader:
				var mat = ShaderMaterial.new()
				mat.shader = fallback_shader_res
				if color_rect:
					color_rect.material = mat
					# Ensure ColorRect is opaque so shader output is visible (alpha 1)
					color_rect.color = Color(1, 1, 1, 1)
					print("Assigned FullScreenFallback shader and set ColorRect alpha=1 so effect is visible")
					full_screen_distort_material = mat
					# apply initial parameters from exports
					_apply_fullscreen_material_defaults()
					print("已指派 fallback fullscreen shader (platform=%s)" % platform_name)
			else:
				push_error("找不到 fallback shader: res://Shaders/FullScreenFallback.gdshader")
		else:
			full_screen_distort_material = (color_rect.material as ShaderMaterial) if color_rect else null
			if color_rect:
				color_rect.color = Color(1, 1, 1, 1)
			print("全屏漣漪材質成功取得！")
	else:
		push_error("找不到 %FullScreenEffect 節點！請確認已拖進 MainScene 並設為 Unique Name")


func _bootstrap_overlapping_bodies() -> void:
	for body in get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if (body is RigidBody2D or body is CharacterBody2D or body is StaticBody2D) and body not in bodies_in_range:
			bodies_in_range.append(body)


func ensure_visuals_visible() -> void:
	# Public helper: enforce visuals are visible and sane for gameplay start
	if not visuals:
		return
	visuals.visible = true
	if visuals.texture == null:
		# try same fallback list as in _ready
		var fallback_paths: Array = [
			"res://Scenes/黑洞遊戲_敵人圖案.png",
			"res://Scenes/1763922312623.png",
			"res://Shaders/發光的星星.png",
			"res://star_background.png",
		]
		for p in fallback_paths:
			if FileAccess.file_exists(p):
				var tex = ResourceLoader.load(p)
				if tex and tex is Texture2D:
					visuals.texture = tex
					visuals.modulate = Color(1,1,1,1)
					_base_visual_modulate = visuals.modulate
					break
	# ensure reasonable scale
	if visuals.scale.length() < 0.01:
		visuals.scale = Vector2.ONE * base_visual_scale
	# ensure on top
	if visuals is CanvasItem:
		visuals.z_index = min(max(visuals.z_index, 100000), Z_MAX)
	print("ensure_visuals_visible: enforced visuals visible, scale=", visuals.scale, "z_index=", (visuals.z_index if visuals is CanvasItem else "N/A"))


func _apply_fullscreen_material_defaults() -> void:
	# Apply exported defaults to whatever material is assigned (handles both original and fallback param names)
	if not full_screen_distort_material:
		return
	# radius / distort_radius
	_full_set_param(full_screen_distort_material, ["distort_radius", "radius"], fs_fallback_radius)
	_full_set_param(full_screen_distort_material, ["distort_strength", "strength"], fs_fallback_strength)
	_full_set_param(full_screen_distort_material, ["distort_speed", "speed"], fs_fallback_speed)
	# tint / tint_color
	_full_set_param(full_screen_distort_material, ["tint_color", "color", "distort_tint"], fs_fallback_tint)


func _full_set_param(mat: ShaderMaterial, names: Array, value) -> void:
	if not mat:
		return
	for n in names:
		# attempt to set the parameter; if the shader doesn't use it, this is harmless
		mat.set_shader_parameter(n, value)


func set_fullscreen_params(radius: float, strength: float, speed: float, tint: Color) -> void:
	# Public method to update fullscreen shader parameters at runtime
	fs_fallback_radius = radius
	fs_fallback_strength = strength
	fs_fallback_speed = speed
	fs_fallback_tint = tint
	if full_screen_distort_material:
		_full_set_param(full_screen_distort_material, ["distort_radius", "radius"], radius)
		_full_set_param(full_screen_distort_material, ["distort_strength", "strength"], strength)
		_full_set_param(full_screen_distort_material, ["distort_speed", "speed"], speed)
		_full_set_param(full_screen_distort_material, ["tint_color", "color", "distort_tint"], tint)


func _process(delta):
	if full_screen_distort_material and not fullscreen_distort_enabled:
		disable_fullscreen_distort()
	elif full_screen_distort_material:
			var viewport = get_viewport()
			var camera = viewport.get_camera_2d()
			
			# 1. 計算並傳遞正確的中心 UV 座標 (保持不變)
			if is_instance_valid(camera):
				var vp_transform: Transform2D = camera.get_viewport_transform()
				var screen_position_px = vp_transform * global_position
				var viewport_size = viewport.get_visible_rect().size
				var real_center_uv = screen_position_px / viewport_size
				full_screen_distort_material.set_shader_parameter("center_uv", real_center_uv)

			# 2. 動態調整漣漪參數（只在 level/stability/fever 狀態變化時更新）
			var _shader_dirty: bool = (current_level != _prev_shader_level) or (absf(current_stability - _prev_shader_stability) > 0.5) or (fever_active != _prev_shader_fever)
			if _shader_dirty:
				_prev_shader_level = current_level
				_prev_shader_stability = current_stability
				_prev_shader_fever = fever_active
			if current_level >= distort_start_level and _shader_dirty:
				var progress = float(current_level - distort_start_level) / (max_level - distort_start_level)
				progress = clamp(progress, 0.0, 1.0)
				
				var stability_ratio = current_stability / max_stability # 穩定度比例 (1.0 = Max, 0.0 = Min)
				var instability_ratio = 1.0 - stability_ratio           # 不穩定比例 (0.0 = Max, 1.0 = Min)
				
				# A. 速度修正：【僅依等級成長】
				#    速度從基礎值 (0.5) 緩慢成長到最大速度 (max_distort_speed)
				var target_speed = lerp(0.15, max_distort_speed, progress)
				
				# B. 半徑修正：【僅依等級成長】(滿足你的需求)
				#    半徑從 0.0 成長到 max_distort_radius (通常為 1.0，即全螢幕)
				var target_radius = lerp(0.0, max_distort_radius, progress) 
				
				# C. 強度修正：【等級決定基礎強度 + 不穩定懲罰】
				#    穩定度越低，強度越強，作為視覺警示。
				var base_strength = lerp(0.0, max_distort_strength, progress)
				var target_strength = lerp(base_strength, max_distort_strength * 2.0, instability_ratio)
				
				# Readability boost: make the effect clearly visible.
				target_strength *= ripple_strength_boost
				target_speed *= ripple_speed_boost
				# Skin feel: different skins can have different ripple aggression.
				target_strength *= _skin_ripple_strength_mult
				target_speed *= _skin_ripple_speed_mult
				if fever_active:
					target_strength *= fever_ripple_strength_boost
					target_speed *= fever_ripple_speed_boost
				# Keep it sane across devices.
				target_strength = clamp(target_strength, 0.0, max_distort_strength * 4.0)
				target_speed = clamp(target_speed, 0.0, max_distort_speed * 3.0)

				# 傳遞參數
				full_screen_distort_material.set_shader_parameter("distort_radius", target_radius)
				full_screen_distort_material.set_shader_parameter("distort_strength", target_strength)
				full_screen_distort_material.set_shader_parameter("distort_speed", target_speed)

			else:
				# 等級不足時，平滑過渡到關閉效果 (保持不變)
				var decay_speed = delta * 2.0
				full_screen_distort_material.set_shader_parameter("distort_radius", lerp(full_screen_distort_material.get_shader_parameter("distort_radius"), 0.0, decay_speed))
				full_screen_distort_material.set_shader_parameter("distort_strength", lerp(full_screen_distort_material.get_shader_parameter("distort_strength"), 0.0, decay_speed))
				full_screen_distort_material.set_shader_parameter("distort_speed", lerp(full_screen_distort_material.get_shader_parameter("distort_speed"), 0.0, decay_speed))
	# 更新 Shader 中心點 (自身黑洞 Shader) - 這裡的函式體應該是空的或處理黑洞自身材質的
	update_shader_position(delta) 
	
	# 黑洞自轉
	if visuals:
		var rotation_speed = 100.0 + (current_level - 1) * 250.0
		rotation_speed = clamp(rotation_speed, 100.0, 5000.0)
		visuals.rotation_degrees += rotation_speed * delta 
		if fever_active:
			# Fever：金色/彩虹感（低成本：偏金色 + 輕微脈衝）
			# Make it obvious: brighter gold with a stronger pulse.
			var pulse: float = sin(Time.get_ticks_msec() / 120.0) * 0.35 + 1.0
			visuals.modulate = Color(1.0, 0.82, 0.22, 1.0) * clampf(pulse, 0.65, 1.35)
		else:
			# Apply skin tint outside Fever.
			visuals.modulate = Color(
				_base_visual_modulate.r * _skin_visual_tint.r,
				_base_visual_modulate.g * _skin_visual_tint.g,
				_base_visual_modulate.b * _skin_visual_tint.b,
				_base_visual_modulate.a
			)

	# Fever ring (outer halo) - make the mode switch obvious.
	if _fever_ring and is_instance_valid(_fever_ring) and visuals:
		_fever_ring.visible = fever_active
		if fever_active:
			_fever_ring.position = Vector2.ZERO
			_fever_ring.rotation_degrees = visuals.rotation_degrees * 0.65
			var base_scale: Vector2 = visuals.scale
			var pulse: float = sin(Time.get_ticks_msec() / 110.0) * 0.07 + 1.0
			_fever_ring.scale = base_scale * fever_ring_scale_multiplier * pulse
			# Alpha pulse makes it read without adding new assets.
			var a_pulse: float = sin(Time.get_ticks_msec() / 150.0) * 0.12 + 1.0
			var base_c: Color = _skin_fever_ring_color
			_fever_ring.modulate = Color(base_c.r, base_c.g, base_c.b, fever_ring_alpha) * clampf(a_pulse, 0.75, 1.25)

	# Skin overlay: rotate + keep aligned with visuals scale.
	if _skin_overlay and is_instance_valid(_skin_overlay) and visuals:
		_skin_overlay.position = Vector2.ZERO
		_skin_overlay.scale = visuals.scale
		if _skin_overlay_spin_deg_per_sec != 0.0:
			_skin_overlay.rotation_degrees += _skin_overlay_spin_deg_per_sec * delta

	# Fever hunt safety: Hourglass freezes enemy physics (no approach), so keep enemy-eat on contact
	# by scanning near the core while Fever is active.
	if fever_active:
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _fever_enemy_scan_ms >= 33:
			_fever_enemy_scan_ms = now_ms
			_swallow_enemies_in_core_radius()
		
	# 相機縮放：由 Main.gd 統一管理，避免雙方同時改 zoom 造成瞬間跳動
			
	# 處理熵值衰減和視覺效果
	_handle_entropy_decay(delta)
	_update_instability_visuals() # 處理色差和輝光閃爍 (更新 Shader: aberration)
	_update_size_by_stability(delta) # 根據穩定度平滑調整大小 (更新 Shader: radius)

func _physics_process(delta):
	apply_pull(delta)
	_update_fever(delta)
	update_shader_position()


func is_fever_active() -> bool:
	return fever_active


func get_fever_speed_multiplier() -> float:
	return fever_speed_multiplier if fever_active else 1.0


func start_fever(duration_sec: float = -1.0) -> void:
	var d: float = duration_sec
	if d <= 0.0:
		d = fever_duration_sec
	# Roguelike: fever_duration_bonus modifier
	if has_node("/root/RoguelikeUpgradeManager"):
		d += get_node("/root/RoguelikeUpgradeManager").get_modifier("fever_duration_bonus")
	fever_active = true
	_fever_time_left = d
	_fever_absorb_accum = 0.0
	_fever_enemy_combo_count = 0
	fever_started.emit(d)
	# Fever no longer auto-clears enemies/projectiles.
	# Enemies are only removed when they actually collide with the core.
	# Visual feedback: enable a bright aura so Fever is obvious.
	if fever_particles and is_instance_valid(fever_particles):
		# Use a round glow texture to avoid square-looking particles.
		fever_particles.texture = preload("res://Shaders/發光的星星.png")
		# Keep it as a subtle halo (don't cover the black hole).
		fever_particles.modulate = Color(1.0, 0.9, 0.35, 0.35)
		fever_particles.z_index = -20
		# Emit around the outer edge as an aura.
		fever_particles.emission_sphere_radius = 140.0
		# The texture is high-res; force particles to be small.
		fever_particles.scale_amount_min = 0.03
		fever_particles.scale_amount_max = 0.08
		fever_particles.one_shot = false
		fever_particles.explosiveness = 0.0
		fever_particles.speed_scale = 1.0
		fever_particles.amount = max(50, int(fever_particles.amount))
		fever_particles.emitting = true
	if _fever_ring and is_instance_valid(_fever_ring):
		_fever_ring.visible = true


func _end_fever(silent: bool = false) -> void:
	if not fever_active:
		return
	fever_active = false
	_fever_time_left = 0.0
	_fever_absorb_accum = 0.0
	_fever_enemy_combo_count = 0
	# Restore Fever visuals.
	if fever_particles and is_instance_valid(fever_particles) and not _fever_particles_restore.is_empty():
		fever_particles.texture = _fever_particles_restore.get("texture", fever_particles.texture)
		fever_particles.modulate = _fever_particles_restore.get("modulate", fever_particles.modulate)
		fever_particles.emitting = bool(_fever_particles_restore.get("emitting", false))
		fever_particles.one_shot = bool(_fever_particles_restore.get("one_shot", false))
		fever_particles.explosiveness = float(_fever_particles_restore.get("explosiveness", 1.0))
		fever_particles.speed_scale = float(_fever_particles_restore.get("speed_scale", 1.0))
		fever_particles.amount = int(_fever_particles_restore.get("amount", fever_particles.amount))
		fever_particles.z_index = int(_fever_particles_restore.get("z_index", fever_particles.z_index))
		fever_particles.emission_sphere_radius = float(_fever_particles_restore.get("emission_sphere_radius", fever_particles.emission_sphere_radius))
		fever_particles.scale_amount_min = float(_fever_particles_restore.get("scale_amount_min", fever_particles.scale_amount_min))
		fever_particles.scale_amount_max = float(_fever_particles_restore.get("scale_amount_max", fever_particles.scale_amount_max))
	if not silent:
		fever_ended.emit()
	if _fever_ring and is_instance_valid(_fever_ring):
		_fever_ring.visible = false


func _extend_fever_from_enemy() -> void:
	if not fever_active:
		return
	var cap: float = maxf(fever_duration_sec, fever_duration_sec * fever_time_cap_multiplier)
	_fever_time_left = minf(_fever_time_left + fever_enemy_time_bonus_sec, cap)


func _swallow_enemies_in_core_radius() -> void:
	# Called during extreme time stop (Engine.time_scale ~ 0) to keep Fever hunt responsive.
	var r: float = get_damage_radius()
	for e in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(e):
			continue
		if not (e is Node2D):
			continue
		var n: Node2D = e as Node2D
		if n.global_position.distance_to(global_position) > r:
			continue
		_swallow_body(n)


func _ensure_fever_ring() -> void:
	# Create once; no scene edits required.
	_fever_ring = get_node_or_null("FeverRing") as Sprite2D
	if _fever_ring:
		return
	_fever_ring = Sprite2D.new()
	_fever_ring.name = "FeverRing"
	_fever_ring.texture = preload("res://Shaders/發光的星星.png")
	_fever_ring.centered = true
	_fever_ring.z_index = (visuals.z_index + 1) if visuals else 1
	_fever_ring.visible = false
	# Additive blend so it reads as a glow/halo.
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fever_ring.material = m
	add_child(_fever_ring)


func _update_fever(delta: float) -> void:
	if not fever_active:
		return
	_fever_time_left -= delta
	if _fever_time_left <= 0.0:
		_end_fever(false)


func _absorb_overlapping_enemies_for_fever() -> void:
	# Fever: touching enemies should instantly count as swallowed.
	# Use get_overlapping_areas() to match actual collision overlap (not just distance).
	for a in get_overlapping_areas():
		if not is_instance_valid(a):
			continue
		if not (a is Node2D):
			continue
		var n: Node2D = a as Node2D
		# Identify enemies by either group or interface.
		var is_enemy_area: bool = false
		if (a is Node) and (a as Node).is_in_group("Enemies"):
			is_enemy_area = true
		elif a.has_method("is_enemy") and bool(a.call("is_enemy")):
			is_enemy_area = true
		if not is_enemy_area:
			continue
		_swallow_body(n)

# ----------------------------------------------------
# 核心吞噬與成長邏輯
# ----------------------------------------------------

# 當被敵人射擊或造成懲罰時呼叫
func shrink_and_eject(amount: float, eject_count: int):
	# 1. 減少吞噬總數 (體積代理)
	var old_count = swallowed_count
	swallowed_count = max(0, swallowed_count - int(amount))
	
	# 2. 減少引力半徑 (視覺/引力上的縮小感)
	var size_reduction = base_growth_per_object * amount * 0.5
	max_pull_radius = max(base_pull_radius, max_pull_radius - size_reduction)
	
	# 3. 觸發視覺效果 (Glitch Particles)
	# 取消白色方塊煙：不再觸發 GlitchParticles
	# if is_instance_valid(glitch_particles):
	# 	glitch_particles.restart()
		
	# 4. 噴出物體 (Eject Items / 噴裝)
	if main_scene_node and main_scene_node.has_method("get_object_scene"):
		var scene_ref = main_scene_node.get_object_scene() 
		var num_to_eject = min(eject_count, int(amount * 0.5))
		
		for i in range(num_to_eject):
			var obj = scene_ref.instantiate()
			get_parent().add_child(obj)
			obj.global_position = global_position
			
			# 給予隨機的噴射力道
			var eject_force = Vector2.RIGHT.rotated(randf_range(0, TAU)) * randf_range(200, 500)
			if obj is RigidBody2D:
				obj.apply_central_impulse(eject_force)

	# 5. 通知 Main.gd 更新分數/體積
	if old_count != swallowed_count:
		object_swallowed.emit(0) 

# 核心吞噬邏輯 (新增能量回復)
func _swallow_body(body: Node2D):
	# Campaign objective (e.g., Golden Core). Gate swallowing by required level.
	if body and body.has_method("is_core_objective") and bool(body.call("is_core_objective")):
		var req: int = 10
		if body.has_method("get_required_level"):
			req = int(body.call("get_required_level"))
		if current_level < req:
			# Not ready yet; do not swallow.
			return
		var obj_id: StringName = &"core"
		if body.has_method("get_objective_id"):
			obj_id = body.call("get_objective_id")
		var pos_obj: Vector2 = body.global_position
		body.queue_free()
		if body in bodies_in_range:
			bodies_in_range.erase(body)
		objective_swallowed.emit(obj_id)
		# Minimal feedback
		_play_swallow_particles(pos_obj)
		return

	# 【Boss 特殊處理：造成吞噬傷害但不消滅】
	if body.has_method("is_boss") and body.is_boss():
		var pull_dmg: float = GameConfig.BOSS_PULL_DAMAGE_PER_HIT
		if fever_active:
			pull_dmg *= 2.0 # Fever 期間雙倍傷害
		if body.has_method("take_pull_damage"):
			body.call("take_pull_damage", pull_dmg)
		_play_swallow_particles(body.global_position)
		swallowed_feedback.emit(pull_dmg * 0.3)
		_bounce_on_swallow(pull_dmg * 0.3)
		return # Boss 不被消滅，由其自身 HP 管理死亡

	# 【第一步：檢查是否為敵人】
	if body.has_method("is_enemy") and body.is_enemy():
		if not fever_active:
			# 敵人對黑洞核心造成破壞 (扣除大量穩定度)
			var damage = ENEMY_CONTACT_DAMAGE
			apply_damage(damage) # 使用統一的傷害接收函式
			# 敵人自我銷毀
			body.queue_free()
			if body in bodies_in_range:
				bodies_in_range.erase(body)
			return # 處理完敵人，立即退出函式
		# Fever：視為可吞噬目標（給分 + 回復穩定度）
		var enemy_gain: float = FEVER_ENEMY_STABILITY_GAIN
		if body.has_method("get_score_value"):
			enemy_gain = float(body.get_score_value())
		var score_gain_enemy: int = int(round(enemy_gain * fever_enemy_score_multiplier))
		_extend_fever_from_enemy()
		_fever_enemy_combo_count += 1
		# Roguelike: enemy_swallow_heal bonus
		var enemy_heal_bonus: float = 0.0
		if has_node("/root/RoguelikeUpgradeManager"):
			enemy_heal_bonus = get_node("/root/RoguelikeUpgradeManager").get_modifier("enemy_swallow_heal")
		current_stability = min(current_stability + enemy_gain + enemy_heal_bonus, max_stability)
		stability_changed.emit(current_stability, max_stability)
		var pos_enemy: Vector2 = body.global_position
		body.queue_free()
		if body in bodies_in_range:
			bodies_in_range.erase(body)
		object_swallowed.emit(score_gain_enemy)
		enemy_killed.emit()
		fever_enemy_combo.emit(_fever_enemy_combo_count, pos_enemy)
		swallowed_feedback.emit(enemy_gain)
		_bounce_on_swallow(enemy_gain)
		_play_swallow_particles(pos_enemy)
		return


	# 【第二步：處理普通物體/得分邏輯】
	
	# 吞噬前先獲取能量值
	var energy_gain = 5.0 
	if body.has_method("get_score_value"):
		energy_gain = body.get_score_value() * 1.0
	# 寶藏哥布林：額外穩定度回復
	if body.has_method("get_stability_bonus"):
		var bonus: float = float(body.get_stability_bonus())
		if bonus > 0.0:
			current_stability = minf(current_stability + bonus, max_stability)
			stability_changed.emit(current_stability, max_stability)
	var overload_active: bool = _is_overload_active()
	var score_mult: float = overload_score_multiplier if overload_active else 1.0
	var score_gain: int = int(round(energy_gain * score_mult))
	# 若是道具，先通知主控（Main.gd）觸發效果
	if body.has_method("get_powerup_type"):
		var t = body.get_powerup_type()
		if t != null:
			powerup_collected.emit(t)
	# 依照能量值換算「成長分數」：大物體推進成長更明顯
	# 玩家回饋：吃東西成長太快 -> 降低換算與上限
	var growth_points: int = int(round(energy_gain / GROWTH_ENERGY_DIVISOR))
	growth_points = clamp(growth_points, 1, 3)
	
	# Roguelike: swallow_heal bonus healing per swallow
	var bonus_heal: float = 0.0
	if has_node("/root/RoguelikeUpgradeManager"):
		var rum = get_node("/root/RoguelikeUpgradeManager")
		bonus_heal = rum.get_modifier("swallow_heal")
		rum.notify_swallow()
	current_stability += energy_gain + bonus_heal
	current_stability = min(current_stability, max_stability) 
	stability_changed.emit(current_stability, max_stability)
	
	# 確保在移除物體前取得位置，用於特效
	var swallow_position = body.global_position
	
	body.queue_free()
	if body in bodies_in_range:
		bodies_in_range.erase(body)
	
	swallowed_count += growth_points
	object_swallowed.emit(score_gain)	# 傳遞分數增量（Main 用來加總分數）
	# Juice：吞噬回饋（主場景震動/手機震動） + 黑洞果凍彈跳
	swallowed_feedback.emit(energy_gain)
	_bounce_on_swallow(energy_gain)
	
	_play_swallow_particles(swallow_position) # 播放吞噬特效
	
	# 升級與成長邏輯
	var required = growth_per_level * current_level
	if swallowed_count >= required and current_level < max_level:
		current_level += 1
		level_up.emit(current_level)
		
		max_pull_radius += base_growth_per_object * 15
		#kill_radius += base_growth_per_object * 8
		
		if current_level == max_level:
			reached_max_level.emit()
	
	var growth_this_time = base_growth_per_object * (1.0 + swallowed_count * exponential_growth_factor)
	max_pull_radius += growth_this_time
	#kill_radius += growth_this_time * 0.8
	#
	max_pull_radius = min(max_pull_radius, final_max_radius)
	kill_radius = base_kill_radius
	# Roguelike: kill_radius_mult & pull_radius_mult modifiers
	if has_node("/root/RoguelikeUpgradeManager"):
		var rum = get_node("/root/RoguelikeUpgradeManager")
		kill_radius *= rum.get_multiplier("kill_radius_mult")
		max_pull_radius *= rum.get_multiplier("pull_radius_mult")
		max_pull_radius = min(max_pull_radius, final_max_radius)
	#kill_radius = min(kill_radius, final_max_radius * 0.35)
	
	_update_collision_and_visuals()
	_update_shader_params() # 更新強度 (strength)

# ----------------------------------------------------
# 傷害與死亡邏輯
# ----------------------------------------------------
var _shield_active: bool = false
var _shield_tween: Tween = null

func set_shield_active(active: bool) -> void:
	_shield_active = active
	if _shield_tween and _shield_tween.is_valid():
		_shield_tween.kill()
		_shield_tween = null
	if active:
		# Looping cyan pulse to indicate shield
		_shield_tween = create_tween().set_loops()
		_shield_tween.tween_property(self, "modulate", Color(0.4, 0.8, 1.0, 1.0), 0.5)
		_shield_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)

func is_shield_active() -> bool:
	return _shield_active

# 當被敵人射擊或近戰撞擊時呼叫 (統一的傷害接收介面)
func apply_damage(amount: float, show_feedback: bool = true):
	# Shield: full immunity (no stability loss)
	if _shield_active:
		return
	# Fever：無敵（不扣穩定度，不紅閃）
	if fever_active:
		return
	# Roguelike: damage_reduction modifier
	var actual_amount := amount
	if has_node("/root/RoguelikeUpgradeManager"):
		var dr: float = get_node("/root/RoguelikeUpgradeManager").get_modifier("damage_reduction")
		actual_amount = maxf(0.0, amount * (1.0 - clampf(dr, 0.0, 0.8)))
	current_stability = max(0.0, current_stability - actual_amount)
	stability_changed.emit(current_stability, max_stability)
	# 只有真正「受傷」才做紅閃/震動；衝刺消耗穩定度屬於自損成本，不該一直干擾畫面
	if show_feedback and amount > 0.0:
		damaged.emit(amount)
	
	# 可以在這裡加入被擊中時的視覺震動效果
	
	if current_stability <= 0:
		_on_entropy_death()


func revive_to_ratio(ratio: float = 0.6) -> void:
	# 觀看廣告復活用：回復一定比例的穩定度
	ratio = clamp(ratio, 0.05, 1.0)
	current_stability = clamp(max_stability * ratio, 1.0, max_stability)
	stability_changed.emit(current_stability, max_stability)

# 核心穩定度耗盡時呼叫 (遊戲結束)
func _on_entropy_death():
	stability_depleted.emit() # 通知 Main.gd 處理遊戲結束 (Game Over)

# ----------------------------------------------------
# 熵值邏輯：維持生存壓力
# ----------------------------------------------------
func _handle_entropy_decay(delta):
	var level_penalty = 1.0 + (current_level * decay_level_scale)
	level_penalty = min(level_penalty, 2.6)
	# Roguelike: decay_rate_mult modifier (negative = slower decay)
	var decay_mult: float = 1.0
	if has_node("/root/RoguelikeUpgradeManager"):
		decay_mult = maxf(0.05, get_node("/root/RoguelikeUpgradeManager").get_multiplier("decay_rate_mult"))
		# Fever no-decay evolution
		if fever_active and get_node("/root/RoguelikeUpgradeManager").get_modifier("fever_no_decay") > 0.0:
			decay_mult = 0.0
	var actual_decay = base_decay_rate * level_penalty * decay_mult * delta
	
	current_stability -= actual_decay
	current_stability = max(current_stability, 0.0)
	stability_changed.emit(current_stability, max_stability)
	
	if current_stability <= 0:
		_on_entropy_death() # 呼叫遊戲結束函式

# ----------------------------------------------------
# 引力施加 (在 _physics_process 中呼叫)
# ----------------------------------------------------
func apply_pull(delta):
	# 重要：物體 queue_free 可能不會觸發 exited，避免無效引用累積造成後期卡頓
	for i in range(bodies_in_range.size() - 1, -1, -1):
		var b = bodies_in_range[i]
		if not is_instance_valid(b):
			bodies_in_range.remove_at(i)
			continue

	var overload_active: bool = _is_overload_active()
	var pull_mult: float = overload_pull_multiplier if overload_active else 1.0
	if fever_active:
		pull_mult *= fever_pull_radius_multiplier
	for body in bodies_in_range:
		# 道具不應被引力拉扯（玩家回饋：磁鐵/沙漏被吸進去太快）
		# 但仍允許玩家「碰到就吃到」(dist < kill_radius)
		var is_powerup: bool = false
		if body and body is Node:
			is_powerup = (body as Node).is_in_group("PowerUps")
		
		var dir = global_position - body.global_position
		var dist = dir.length()
		
		if dist < kill_radius:
			_swallow_body(body)
			continue
		if is_powerup:
			continue
			
		var current_pull_radius = _get_current_radius() * pull_mult
		if dist > current_pull_radius:
			continue
			
		var pull_factor = (current_pull_radius - dist) / current_pull_radius
		pull_factor = clamp(pull_factor, 0.0, 1.0)
		var force = dir.normalized() * pull_strength * pull_mult * pull_factor
		
		if body is RigidBody2D:
			body.apply_central_force(force * delta * 60)


func _is_overload_active() -> bool:
	if max_stability <= 0.0:
		return false
	return (current_stability / max_stability) >= overload_threshold


func _consume_stability(cost: float) -> bool:
	cost = maxf(0.0, cost)
	if cost <= 0.0:
		return true
	if current_stability < cost:
		return false
	current_stability = maxf(0.0, current_stability - cost)
	stability_changed.emit(current_stability, max_stability)
	if current_stability <= 0.0:
		_on_entropy_death()
	return true


func trigger_shockwave() -> bool:
	# 主動釋放 entropy：消耗穩定度推開/震暈周圍敵人與子彈
	# Roguelike: shockwave_cost_mult modifier (negative = cheaper)
	var cost: float = shockwave_stability_cost
	if has_node("/root/RoguelikeUpgradeManager"):
		cost *= maxf(0.0, get_node("/root/RoguelikeUpgradeManager").get_multiplier("shockwave_cost_mult"))
	if not _consume_stability(cost):
		return false
	var r: float = maxf(50.0, shockwave_radius)
	var intensity: float = clampf(r / 600.0, 0.4, 1.0)
	shockwave_triggered.emit(intensity)

	# Enemies
	for e in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(e):
			continue
		if not (e is Node2D):
			continue
		var n: Node2D = e as Node2D
		var to_n: Vector2 = n.global_position - global_position
		var d: float = to_n.length()
		if d > r:
			continue
		var dir: Vector2 = (to_n / d) if d > 0.001 else Vector2.RIGHT
		# 推開（更明顯，讓玩家覺得有放大招）
		n.global_position += dir * (140.0 + (r - d) * 0.35)
		# Boss 受衝擊波傷害
		if e.has_method("is_boss") and e.is_boss() and e.has_method("take_shockwave_damage"):
			e.call("take_shockwave_damage", GameConfig.BOSS_PULL_DAMAGE_PER_HIT * 1.5)
		# 短暫暈眩（若支援）
		if e.has_method("set_frozen"):
			e.call("set_frozen", true)
			call_deferred("_unfreeze_later", e, shockwave_stun_time)

	# Projectiles：直接清除半徑內子彈（最有感）
	for p in get_tree().get_nodes_in_group("EnemyProjectiles"):
		if not is_instance_valid(p):
			continue
		if not (p is Node2D):
			continue
		var n2: Node2D = p as Node2D
		var to_p: Vector2 = n2.global_position - global_position
		var d2: float = to_p.length()
		if d2 > r:
			continue
		p.queue_free()
	return true


func _unfreeze_later(node: Object, t: float) -> void:
	await get_tree().create_timer(max(0.05, t)).timeout
	if not is_instance_valid(node):
		return
	if node.has_method("set_frozen"):
		node.call("set_frozen", false)

# ----------------------------------------------------
# 視覺與碰撞更新 (Shader & Scale)
# ----------------------------------------------------

# 處理低穩定度時的視覺色差和輝光閃爍
func _update_instability_visuals():
	# Fever has its own strong visual feedback; keep shader effects consistent.
	if fever_active:
		if black_hole_material:
			black_hole_material.set_shader_parameter("aberration", 0.12 * _skin_aberration_mult)
		return
	var stability_ratio = current_stability / max_stability
	
	if stability_ratio < 0.3:
		var low_ratio = stability_ratio / 0.3 # 0.0 (最差) 到 1.0 (剛好 30%)
		
		# 1. 色差 (Chromatic Aberration) - 在 Shader 中調整
		if black_hole_material:
			# 穩定度越低，色差強度越大
			var max_aberration = 0.08
			var current_aberration = lerp(max_aberration, 0.02, low_ratio) * _skin_aberration_mult
			black_hole_material.set_shader_parameter("aberration", current_aberration)
			
		# 2. 輝光閃爍 (Glow Pulse) - 讓 WorldEnvironment 的 Glow 閃爍
		if main_scene_node and main_scene_node.has_node("WorldEnvironment"):
			var env = main_scene_node.get_node("WorldEnvironment").environment
			if env and env.glow_enabled:
				var pulse = sin(Engine.get_frames_drawn() * 0.2) * 0.5 + 0.5 # 0.0 到 1.0 的脈衝
				# 穩定度越低，輝光越強烈
				var glow_strength = lerp(2.5, 1.0, low_ratio) 
				env.glow_intensity = glow_strength * pulse 
	else:
		# 穩定度回復時，將 Aberration 重設回預設值
		if black_hole_material:
			black_hole_material.set_shader_parameter("aberration", 0.02 * _skin_aberration_mult)
		# NOTE: 重設 Glow 建議在 Main.gd 的 _on_stability_changed 裡進行。

# 根據穩定度平滑調整黑洞大小 (質量蒸發/恢復)
func _update_size_by_stability(delta): 
	var stability_ratio = current_stability / max_stability
	var penalty_threshold = 0.5
	
	# 1. 計算目標引力半徑
	var target_radius = max_pull_radius
	
	if stability_ratio < penalty_threshold:
		var penalty_ratio = stability_ratio / penalty_threshold
		# 穩定度低於 50% 時，目標半徑將縮小到 max_pull_radius 的 70%
		var penalty_factor = lerp(0.7, 1.0, penalty_ratio)
		target_radius = max_pull_radius * penalty_factor
		
	# 2. 平滑過渡設定
	var SHRINK_SPEED = 2.0 
	var RECOVERY_SPEED = 6.0 
	
	var current_smooth_speed = RECOVERY_SPEED
	
	if target_radius < _get_current_radius():
		current_smooth_speed = SHRINK_SPEED
	
	# 3. 平滑碰撞半徑 (引力範圍)
	var smoothed_radius = _get_current_radius()
	if collision_shape and collision_shape.shape is CircleShape2D:
		var circle = collision_shape.shape as CircleShape2D
		# 使用 lerp 平滑地從當前半徑移動到目標半徑
		circle.radius = lerp(circle.radius, target_radius, current_smooth_speed * delta)
		smoothed_radius = circle.radius 

	# 4. 平滑視覺大小和 Shader 參數
	if visuals:
		# A. 計算正常的視覺縮放值 (基於等級/吞噬量)
		var progress = (max_pull_radius - base_pull_radius) / (final_max_radius - base_pull_radius)
		var normal_scale_value = base_visual_scale + progress * visual_growth_factor * 2.5
		normal_scale_value = clamp(normal_scale_value, 0.5, 4.0)
		
		# B. 目標懲罰後的視覺縮放值
		var target_visual_scale = normal_scale_value * (smoothed_radius / max_pull_radius)
		var target_visual_scale_vec = Vector2.ONE * target_visual_scale
		
		# C. 平滑視覺縮放
		visuals.scale = visuals.scale.lerp(target_visual_scale_vec, current_smooth_speed * delta)
		
		# D. 平滑 Shader Radius
		if visuals.material:
			var mat = visuals.material as ShaderMaterial
			var target_shader_radius = _calc_shader_radius_uv(smoothed_radius)
			var current_shader_radius = mat.get_shader_parameter("radius")
			
			mat.set_shader_parameter("radius", lerp(current_shader_radius, target_shader_radius, current_smooth_speed * delta))

# 初始設定/成長時呼叫
# 初始設定/成長時呼叫
func _update_collision_and_visuals():
	# 【關鍵修改：鎖定尺寸】
	# 強制將最大引力半徑鎖定為基礎半徑，不再隨等級增加
	max_pull_radius = base_pull_radius 
	
	# 強制將視覺縮放鎖定為基礎縮放
	if visuals:
		visuals.scale = Vector2.ONE * base_visual_scale

	# 確保碰撞形狀也鎖定
	if collision_shape and collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = max_pull_radius
	
	_update_shader_params() # 更新 Shader 參數 (強度和紅光)ue

# 初始設定/成長時呼叫 (主要用於設定強度等非每影格變動參數)
func _update_shader_params():
	if black_hole_material:
		
		# 【關鍵修改：動態增加引力強度 (Pull Strength)】
		# 基礎力 900.0，每升一級增加 300.0 的力道
		# 這樣在 Lv.30 時，力道會是 900 + 29 * 300 = 9600.0，非常強大
		var base_force = 900.0
		# 玩家回饋：後期吸得太猛/節奏太快 -> 降低每級增幅
		var force_per_level = 140.0 
		pull_strength = base_force + (current_level - 1) * force_per_level
		# Roguelike: pull_strength_mult modifier
		if has_node("/root/RoguelikeUpgradeManager"):
			pull_strength *= get_node("/root/RoguelikeUpgradeManager").get_multiplier("pull_strength_mult")
		
		# 將拉取半徑轉換為 UV 座標；避免半徑過大導致整張 Sprite 變成方塊
		black_hole_material.set_shader_parameter("radius", _calc_shader_radius_uv(_get_current_radius()))
		
		# 強度隨等級提升 + Skin 倍率（讓不同 skin 有「手感差」）
		var strength = lerp(0.2, 2.5, float(current_level) / max_level) * _skin_strength_mult
		black_hole_material.set_shader_parameter("strength", strength)
			
		var red_intensity = 0.0
		if current_level > 15:
			red_intensity = lerp(0.0, 1.2, float(current_level - 15) / (max_level - 15))
		black_hole_material.set_shader_parameter("tint_intensity", red_intensity)
		
		# 視覺進化等級 (Phase 4B)
		_update_visual_tier()

# 視覺進化：根據等級改變邊緣光暈/色差/粒子
func _update_visual_tier() -> void:
	if not black_hole_material:
		return
	# Tier 1: Lv 1-5  → 無額外效果
	# Tier 2: Lv 6-10 → 紫/青光暈 + 輕微色差增強
	# Tier 3: Lv 11+  → 金色光暈 + 強色差 + 粒子加強
	var rim_col := Vector3(0.0, 0.0, 0.0)
	var rim_int: float = 0.0
	var aberr: float = 0.02
	
	if current_level >= 11:
		# Tier 3: 金色/橙色（像吸積盤）
		var t3: float = clampf(float(current_level - 11) / 10.0, 0.0, 1.0)
		rim_col = Vector3(1.0, 0.7 + t3 * 0.15, 0.15 + t3 * 0.1)
		rim_int = lerpf(0.35, 0.7, t3)
		aberr = lerpf(0.04, 0.08, t3)
		# 粒子加速
		if glitch_particles and glitch_particles is CPUParticles2D:
			glitch_particles.speed_scale = lerpf(1.2, 1.8, t3)
			glitch_particles.amount = clampi(int(lerpf(20.0, 40.0, t3)), 8, 60)
	elif current_level >= 6:
		# Tier 2: 紫/青
		var t2: float = clampf(float(current_level - 6) / 5.0, 0.0, 1.0)
		rim_col = Vector3(0.5 + t2 * 0.2, 0.3, 1.0)
		rim_int = lerpf(0.15, 0.35, t2)
		aberr = lerpf(0.025, 0.04, t2)
		if glitch_particles and glitch_particles is CPUParticles2D:
			glitch_particles.speed_scale = lerpf(1.0, 1.2, t2)
	else:
		# Tier 1: 預設
		if glitch_particles and glitch_particles is CPUParticles2D:
			glitch_particles.speed_scale = 1.0
	
	black_hole_material.set_shader_parameter("rim_color", rim_col)
	black_hole_material.set_shader_parameter("rim_intensity", rim_int)
	black_hole_material.set_shader_parameter("aberration", aberr)

# 更新 Shader 中心點
func update_shader_position(_delta: float = 0.0):
	if not black_hole_material:
		return

	# 以實際的非等比縮放做補正：若 X/Y scale 不一致，圓形會被拉成橢圓
	var s: Vector2 = Vector2.ONE
	if visuals:
		s = visuals.global_transform.get_scale()
	var aspect: float = 1.0
	if absf(s.y) > 0.0001:
		aspect = absf(s.x) / absf(s.y)
	black_hole_material.set_shader_parameter("aspect_ratio", aspect)
	black_hole_material.set_shader_parameter("center", Vector2(0.5, 0.5))


func _calc_shader_radius_uv(world_radius_px: float) -> float:
	var vp: Vector2 = get_viewport_rect().size
	var denom: float = maxf(vp.x, vp.y)
	if denom <= 1.0:
		denom = 1.0
	# UV 半徑：0.5 會剛好碰到邊，>0.707 會把四角都涵蓋變成方形
	return clampf(world_radius_px / denom, 0.05, 0.49)

# ----------------------------------------------------
# 輔助函式
# ----------------------------------------------------

# 輔助函式：取得當前引力半徑
func _get_current_radius() -> float:
	if collision_shape and collision_shape.shape is CircleShape2D:
		return (collision_shape.shape as CircleShape2D).radius
	return max_pull_radius

# 輔助函式：播放吞噬粒子特效
func _play_swallow_particles(_pos: Vector2):
	# 數據吞噬/Glitch 粒子特效 (假設 GlitchParticles 夠用)
	# 如果要單獨的吞噬特效，可以在這裡實作
	pass # 目前只使用 glitch_particles 處理懲罰


func _bounce_on_swallow(energy_gain: float) -> void:
	if not visuals:
		return
	if current_level >= swallow_bounce_disable_level:
		return
	# Avoid stacking tweens at high swallow rates.
	if _swallow_bounce_tween and _swallow_bounce_tween.is_valid():
		_swallow_bounce_tween.kill()
		_swallow_bounce_tween = null
	# 小果凍彈跳：吞越大，彈越明顯
	var k: float = clampf(energy_gain / 40.0, 0.12, swallow_bounce_max_k)
	# Gradually damp bounce as level rises, even before the hard disable.
	var lv_from: int = maxi(swallow_bounce_min_level, 1)
	var lv_to: int = maxi(swallow_bounce_disable_level, lv_from + 1)
	var damp: float = 1.0 - clampf(float(current_level - lv_from) / float(lv_to - lv_from), 0.0, 1.0)
	k *= lerpf(0.25, 1.0, damp)
	var from_scale: Vector2 = visuals.scale
	var up_scale: Vector2 = from_scale * (1.0 + k)
	var down_scale: Vector2 = from_scale * (1.0 - k * 0.35)
	_swallow_bounce_tween = create_tween()
	_swallow_bounce_tween.tween_property(visuals, "scale", up_scale, 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_swallow_bounce_tween.tween_property(visuals, "scale", down_scale, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swallow_bounce_tween.tween_property(visuals, "scale", from_scale, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ----------------------------------------------------
# Area2D 訊號 (Area2D callbacks)
# ----------------------------------------------------
func _on_black_hole_body_entered(body):
	# Include StaticBody2D so campaign objectives (e.g., Golden Core) can be swallowed.
	if (body is RigidBody2D or body is CharacterBody2D or body is StaticBody2D) and body not in bodies_in_range:
		bodies_in_range.append(body)

func _on_black_hole_body_exited(body):
	if body in bodies_in_range:
		bodies_in_range.erase(body)
