extends CanvasLayer

signal closed

# === 視覺演出時序控制 (Timing) ===
@export_group("Animation Timing")
## 前奏等待時間（黑洞開始震動到閃光前）
@export var prelude_duration: float = 0.65
## 全螢幕白閃觸發的時間點
@export var flash_trigger_time: float = 0.06
## 白閃淡出的持續時間
@export var flash_fade_duration: float = 0.22
## 粒子吸入能量的加速時間
@export var suction_ramp_duration: float = 0.55

# === 螢幕特效強度 (Shader FX) ===
@export_group("Shader Effects")
## 抽中稀有物時的徑向模糊強度
@export var max_radial_blur: float = 0.5
## 色差偏移強度（產生能量不穩定的視覺感）
@export var max_chroma_aberration: float = 2.0
## 螢幕染色亮度
@export var fx_tint_intensity: float = 0.3

# === 稀有度顏色配置 (Rarity Colors) ===
@export_group("Rarity Visuals")
@export var color_r: Color = Color(0.4, 0.6, 1.0) # 藍色
@export var color_ssr: Color = Color(1.0, 0.8, 0.2) # 金色

# === 全螢幕引力漣漪 (Ripple FX) ===
@export_group("Ripple FX")
@export var ripple_enabled: bool = true
## 建議保持低頻率（預設 5.0）避免頭暈
@export var ripple_frequency: float = 5.0
## RippleFX 的可見度（0=關閉, 1=完全）
@export var ripple_alpha: float = 0.22

@export_group("Ripple Preset (R)")
## 大範圍慢速漣漪（R）
@export var ripple_radius_r: float = 0.82
@export var ripple_strength_r: float = 0.010
@export var ripple_speed_r: float = 0.22

@export_group("Ripple Preset (SSR)")
## 大範圍慢速漣漪（SSR）
@export var ripple_radius_ssr: float = 1.00
@export var ripple_strength_ssr: float = 0.015
@export var ripple_speed_ssr: float = 0.28

# === Burst Rainbow (彩虹噴射) ===
@export_group("Burst Rainbow")
@export var burst_rainbow_enabled: bool = true
## 彩虹粒子透明度（越低越不遮畫面）
@export var burst_rainbow_alpha: float = 0.80

@onready var root: Control = $Root
@onready var dim: ColorRect = $Root/Dim
@onready var ripple_fx: ColorRect = $Root/RippleFX
@onready var screen_fx: ColorRect = $Root/ScreenFX
@onready var flash: ColorRect = $Root/WhiteFlash
@onready var center: Node2D = $Root/Center
@onready var hole: Sprite2D = $Root/Center/Hole
@onready var gather_particles: GPUParticles2D = $Root/Center/GatherParticles
@onready var burst_particles: GPUParticles2D = $Root/Center/BurstParticles
@onready var reveal_panel: PanelContainer = $Root/RevealPanel
@onready var result_texture: TextureRect = $Root/RevealPanel/Margin/VBox/ResultTexture
@onready var result_name: Label = $Root/RevealPanel/Margin/VBox/ResultName
@onready var result_rarity: Label = $Root/RevealPanel/Margin/VBox/ResultRarity
@onready var result_list: RichTextLabel = $Root/RevealPanel/Margin/VBox/ResultList
@onready var single_button: Button = $Root/Buttons/Single
@onready var ten_button: Button = $Root/Buttons/Ten
@onready var close_button: Button = $Root/Buttons/Close
@onready var info_label: Label = $Root/Info
@onready var sfx_ssr: AudioStreamPlayer = $SfxSSR

const STAR_TEX: Texture2D = preload("res://Shaders/發光的星星.png")
const SUCTION_TEX_PATHS: PackedStringArray = [
	"res://Shaders/S1.png",
	"res://Shaders/S2.png",
	"res://Shaders/S3.png",
]
const BURST_TEX_PATHS: PackedStringArray = [
	"res://Shaders/P1.png",
	"res://Shaders/P2.png",
	"res://Shaders/P3.png",
]

# Suction motion: ellipse with X major axis, Y minor axis, rotating while pulling into the hole.
const SUCTION_ELLIPSE_SCALE: Vector2 = Vector2(1.45, 0.75)
const SUCTION_ORBIT_SPEED_RAD: float = deg_to_rad(260.0)
const SUCTION_MIN_DURATION_SEC: float = 1.5

const SSR_BURST_SPREAD_DEG: float = 120.0

const SSR_FILL_TOTAL_BURST_AMOUNT: int = 1100
const N_TOTAL_BURST_AMOUNT: int = 360

var _burst_rainbow_ramp: Texture2D = null
var _burst_mono_ramp: Texture2D = null

var _gather_emitters: Array[GPUParticles2D] = []
var _burst_emitters: Array[GPUParticles2D] = []

var _suction_orbit: Node2D = null
var _suction_orbit_speed: float = 0.0

var _awaiting_ssr_click: bool = false
var _ssr_click_received: bool = false

var _prev_root_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP
var _prev_dim_mouse_filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP

var _host: Node = null
var _skin_defs: Dictionary = {}

var _state: String = "idle" # idle / rolling / anim
var _spin_speed: float = 0.0
var _center_base_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_center_base_pos = center.position
	# Default: don't let fullscreen overlays swallow button clicks.
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_suction_orbit()
	_build_burst_rainbow_ramp()
	_build_burst_mono_ramp()
	_init_texture_mix_emitters()
	_configure_particles()
	_reset_visuals()

	if not single_button.pressed.is_connected(_on_single_pressed):
		single_button.pressed.connect(_on_single_pressed)
	if not ten_button.pressed.is_connected(_on_ten_pressed):
		ten_button.pressed.connect(_on_ten_pressed)
	if not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if not root.gui_input.is_connected(_on_root_gui_input):
		root.gui_input.connect(_on_root_gui_input)


func setup(host: Node, skin_defs: Dictionary) -> void:
	_host = host
	_skin_defs = skin_defs
	_reset_visuals()
	_open_anim()
	_refresh_ui()


func _process(delta: float) -> void:
	if _spin_speed != 0.0:
		hole.rotation += _spin_speed * delta
	if _suction_orbit and _suction_orbit_speed != 0.0:
		_suction_orbit.rotation += _suction_orbit_speed * delta
	_update_ripple_center_uv()


func _input(event: InputEvent) -> void:
	# Use _input to reliably capture taps even if UI consumes them.
	if not _awaiting_ssr_click:
		return
	var pressed := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed = st.pressed
	if pressed:
		_ssr_click_received = true
		get_viewport().set_input_as_handled()


func _on_root_gui_input(event: InputEvent) -> void:
	if not _awaiting_ssr_click:
		return
	var pressed := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed = st.pressed
	if pressed:
		_ssr_click_received = true
		root.accept_event()


func _reset_visuals() -> void:
	visible = true
	dim.color.a = 0.0
	# Keep interactive UI clickable.
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ripple_fx:
		ripple_fx.modulate.a = 0.0
	flash.color.a = 0.0
	reveal_panel.visible = false
	reveal_panel.modulate.a = 1.0
	reveal_panel.scale = Vector2.ONE
	_set_emitters_emitting(_gather_emitters, false)
	_set_emitters_emitting(_burst_emitters, false)
	_configure_particles()
	_state = "idle"
	_spin_speed = 0.0
	_suction_orbit_speed = 0.0
	if _suction_orbit:
		_suction_orbit.rotation = 0.0
		_suction_orbit.scale = Vector2.ONE
	_awaiting_ssr_click = false
	_ssr_click_received = false
	center.position = _center_base_pos
	_set_fx(0.0, 0.0, Color(1, 1, 1, 1), 0.0)
	_set_ripple(0.0, 0.0, 0.0, 0.0)


func _open_anim() -> void:
	_state = "idle"
	_spin_speed = deg_to_rad(40.0)
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(dim, "color:a", 0.72, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if ripple_fx and ripple_enabled:
		t.parallel().tween_property(ripple_fx, "modulate:a", clamp(ripple_alpha, 0.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(hole, "scale", Vector2(0.95, 0.95), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_single_pressed() -> void:
	_start_roll(1)


func _on_ten_pressed() -> void:
	_start_roll(10)


func _on_close_pressed() -> void:
	if _state != "idle":
		return
	queue_free()
	closed.emit()


func _refresh_ui() -> void:
	var coins := 0
	if _host and _host.has_method("get_meta_coins"):
		coins = int(_host.get_meta_coins())
	var pity := 0
	var pity_max := 30
	var total := 0
	var single_cost := 500
	var ten_cost := 4500
	var rate_note := ""
	if has_node("/root/GachaManager"):
		var gm = get_node("/root/GachaManager")
		pity = int(gm.get_ssr_pity_counter())
		pity_max = int(gm.ssr_pity_max)
		total = int(gm.get_total_rolls())
		single_cost = int(gm.single_cost_coins)
		ten_cost = int(gm.ten_cost_coins)
		var rates: Dictionary = gm.get_rarity_rate_map()
		if not rates.is_empty():
			var r_rate := float(rates.get("R", 0.0))
			var ssr_rate := float(rates.get("SSR", 0.0))
			rate_note = "   機率 R %.1f%% / SSR %.1f%%" % [r_rate * 100.0, ssr_rate * 100.0]

	info_label.text = "金幣：%d   SSR 保底：%d/%d   總抽數：%d%s" % [coins, pity, max(1, pity_max), total, rate_note]
	single_button.text = "單抽（%d）" % single_cost
	ten_button.text = "十連（%d）" % ten_cost

	var can_interact := (_state == "idle")
	single_button.disabled = (not can_interact) or coins < single_cost
	ten_button.disabled = (not can_interact) or coins < ten_cost
	close_button.disabled = not can_interact


func _start_roll(count: int) -> void:
	if _state != "idle":
		return
	if not _host or not _host.has_method("do_gacha_roll"):
		return

	_state = "rolling"
	_refresh_ui()

	var result: Dictionary = _host.do_gacha_roll(count)
	if not bool(result.get("ok", false)):
		_state = "idle"
		_refresh_ui()
		return

	var pack: Dictionary = result.get("pack", {}) as Dictionary
	var best: Dictionary = _pick_best_result(pack)
	await _play_sequence(pack, best, clampi(count, 1, 10))

	_state = "idle"
	_refresh_ui()


func _pick_best_result(pack: Dictionary) -> Dictionary:
	var results: Array = pack.get("results", []) as Array
	var best: Dictionary = {}
	for r_v in results:
		var r := r_v as Dictionary
		if best.is_empty():
			best = r
			continue
		var rr := String(r.get("rarity", "R"))
		var br := String(best.get("rarity", "R"))
		if br != "SSR" and rr == "SSR":
			best = r
	return best


func _play_sequence(pack: Dictionary, best: Dictionary, count: int) -> void:
	_state = "anim"
	_refresh_ui()

	var results: Array = pack.get("results", []) as Array
	var has_ssr := false
	for r_v in results:
		var r := r_v as Dictionary
		if String(r.get("rarity", "R")) == "SSR":
			has_ssr = true
			break

	# Stage 1: Anticipation (elliptical rotating suction)
	reveal_panel.visible = false
	_configure_particles()
	_set_emitters_emitting(_gather_emitters, true)
	_spin_speed = deg_to_rad(120.0)
	_suction_orbit_speed = SUCTION_ORBIT_SPEED_RAD
	if _suction_orbit:
		_suction_orbit.scale = SUCTION_ELLIPSE_SCALE
	var tint_color := color_r
	if has_ssr:
		tint_color = color_ssr
	_set_fx(0.35, 0.25, tint_color, 0.22)
	if ripple_enabled:
		var rr: float = ripple_radius_ssr if has_ssr else ripple_radius_r
		var rs: float = ripple_strength_ssr if has_ssr else ripple_strength_r
		var rv: float = ripple_speed_ssr if has_ssr else ripple_speed_r
		_set_ripple(rr, rs, rv, ripple_alpha)

	# Ramp up the suction a bit during the prelude.
	# Ramp up suction on all gather emitters.
	for e in _gather_emitters:
		var gmat := e.process_material as ParticleProcessMaterial
		if not gmat:
			continue
		var t_suck := create_tween()
		t_suck.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_tween_set_if_has(t_suck, gmat, "radial_accel_min", -1600.0, suction_ramp_duration)
		_tween_set_if_has(t_suck, gmat, "radial_accel_max", -900.0, suction_ramp_duration)

	var shake := create_tween()
	shake.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for _i in range(10):
		shake.tween_property(center, "position", _center_base_pos + Vector2(randf_range(-7, 7), randf_range(-7, 7)), 0.05)
	shake.tween_property(center, "position", _center_base_pos, 0.06)
	Input.vibrate_handheld(35)
	var suction_duration: float = max(prelude_duration, SUCTION_MIN_DURATION_SEC)
	await get_tree().create_timer(suction_duration, true, true, true).timeout

	# Stage 2: Burst (N vs SSR)
	_set_emitters_emitting(_gather_emitters, false)
	_suction_orbit_speed = 0.0
	_restart_emitters(_burst_emitters)
	_apply_burst_style(has_ssr, tint_color)
	_set_emitters_emitting(_burst_emitters, true)
	if has_ssr and sfx_ssr:
		sfx_ssr.play()
	Input.vibrate_handheld(60)
	_set_fx(0.95 if has_ssr else 0.85, 0.70 if has_ssr else 0.55, tint_color, 0.42 if has_ssr else 0.32)
	if ripple_enabled:
		var rr2: float = ripple_radius_ssr if has_ssr else ripple_radius_r
		var rs2: float = (ripple_strength_ssr if has_ssr else ripple_strength_r) * 1.25
		var rv2: float = ripple_speed_ssr if has_ssr else ripple_speed_r
		_set_ripple(rr2, rs2, rv2, ripple_alpha)

	var t2 := create_tween()
	t2.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t2.tween_property(flash, "color:a", 1.0, flash_trigger_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t2.tween_property(flash, "color:a", 0.0, flash_fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(flash_trigger_time + flash_fade_duration, true, true, true).timeout

	# SSR: keep bursting until player taps/clicks.
	if has_ssr:
		await _wait_for_ssr_click()

	# Stage 3: Reveal
	_set_emitters_emitting(_gather_emitters, false)
	_spin_speed = deg_to_rad(60.0)
	_set_fx(0.22 if has_ssr else 0.18, 0.26 if has_ssr else 0.18, Color(1, 1, 1, 1), 0.14 if has_ssr else 0.12)
	_set_ripple(0.0, 0.0, 0.0, 0.0)
	# N/R: stop burst right before reveal to keep it readable.
	if not has_ssr:
		_set_emitters_emitting(_burst_emitters, false)
	if count >= 10:
		await _show_reveal_sequential(pack, has_ssr)
	else:
		_show_reveal(pack, best, has_ssr)


func _show_reveal(pack: Dictionary, best: Dictionary, has_ssr: bool) -> void:
	reveal_panel.visible = true
	reveal_panel.modulate.a = 0.0
	reveal_panel.scale = Vector2(0.78, 0.78)

	var skin_id := String(best.get("skin_id", ""))
	var def: Dictionary = _skin_defs.get(skin_id, {}) as Dictionary
	var nm := String(def.get("name", skin_id))
	var rarity := String(best.get("rarity", "R"))

	result_texture.texture = def.get("texture") as Texture2D
	result_name.text = nm
	result_rarity.text = "SSR" if rarity == "SSR" else "R"
	result_rarity.modulate = color_ssr if rarity == "SSR" else color_r

	result_list.clear()
	result_list.append_text("本次結果：\n")
	var results: Array = pack.get("results", []) as Array
	for r_v in results:
		var r := r_v as Dictionary
		var sid := String(r.get("skin_id", ""))
		var rr := String(r.get("rarity", "R"))
		var is_dup := bool(r.get("is_duplicate", false))
		var ddef: Dictionary = _skin_defs.get(sid, {}) as Dictionary
		var dnm := String(ddef.get("name", sid))
		var tag := "[SSR]" if rr == "SSR" else "[R]"
		var suffix := "（重複）" if is_dup else "（NEW）"
		result_list.append_text("- %s %s %s\n" % [tag, dnm, suffix])

	var refund: int = int(pack.get("total_refund_coins", 0))
	if refund > 0:
		result_list.append_text("\n重複轉換：+%d 金幣\n" % refund)

	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(reveal_panel, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(reveal_panel, "scale", Vector2(1.0, 1.0), 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if has_ssr:
		Input.vibrate_handheld(40)


func _show_reveal_sequential(pack: Dictionary, has_ssr_in_pack: bool) -> void:
	# Ten-pull: flip through each result with a small flash and punchy easing.
	var results: Array = pack.get("results", []) as Array
	if results.is_empty():
		return

	reveal_panel.visible = true
	reveal_panel.modulate.a = 1.0
	reveal_panel.scale = Vector2.ONE

	result_list.clear()
	result_list.append_text("十連結果：\n")

	for i in range(results.size()):
		var r := results[i] as Dictionary
		var sid := String(r.get("skin_id", ""))
		var rr := String(r.get("rarity", "R"))
		var is_dup := bool(r.get("is_duplicate", false))
		var def: Dictionary = _skin_defs.get(sid, {}) as Dictionary
		var nm := String(def.get("name", sid))

		# Mini flash (low alpha) to hide texture swap.
		var mini_flash := create_tween()
		mini_flash.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		mini_flash.tween_property(flash, "color:a", 0.28 if rr == "SSR" else 0.18, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		mini_flash.tween_property(flash, "color:a", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		# Swap card content right after peak.
		result_texture.texture = def.get("texture") as Texture2D
		result_name.text = nm
		result_rarity.text = "SSR" if rr == "SSR" else "R"
		result_rarity.modulate = color_ssr if rr == "SSR" else color_r
		if rr == "SSR" and sfx_ssr:
			sfx_ssr.play()

		# Punch scale for the card.
		result_texture.scale = Vector2(0.92, 0.92)
		var punch := create_tween()
		punch.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		punch.tween_property(result_texture, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		punch.tween_property(result_texture, "scale", Vector2(1.0, 1.0), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		var tag := "[SSR]" if rr == "SSR" else "[R]"
		var suffix := "（重複）" if is_dup else "（NEW）"
		result_list.append_text("- %s %s %s\n" % [tag, nm, suffix])

		await get_tree().create_timer(0.18, true, true, true).timeout

	var refund: int = int(pack.get("total_refund_coins", 0))
	if refund > 0:
		result_list.append_text("\n重複轉換：+%d 金幣\n" % refund)
	if has_ssr_in_pack:
		Input.vibrate_handheld(45)


func _set_fx(blur: float, ca: float, tint_color: Color, fade_alpha: float) -> void:
	screen_fx.modulate.a = clamp(fade_alpha, 0.0, 1.0)
	var mat := screen_fx.material as ShaderMaterial
	if not mat:
		return
	var blur_scaled: float = float(clamp(blur, 0.0, 1.0)) * max(0.0, max_radial_blur)
	var ca_scaled: float = float(clamp(ca, 0.0, 1.0)) * max(0.0, max_chroma_aberration)
	var tint_mix: float = float(clamp(fx_tint_intensity, 0.0, 1.0))
	var tint_final := Color(1, 1, 1, 1).lerp(Color(tint_color.r, tint_color.g, tint_color.b, 1.0), tint_mix)
	mat.set_shader_parameter("center_uv", Vector2(0.5, 0.5))
	mat.set_shader_parameter("radial_blur_strength", blur_scaled)
	mat.set_shader_parameter("chroma_aberration", ca_scaled)
	mat.set_shader_parameter("tint", tint_final)


func _set_ripple(radius: float, strength: float, speed: float, alpha: float) -> void:
	if not ripple_fx:
		return
	if not ripple_enabled:
		ripple_fx.modulate.a = 0.0
		return
	var mat := ripple_fx.material as ShaderMaterial
	if not mat:
		ripple_fx.modulate.a = 0.0
		return

	ripple_fx.modulate.a = clamp(alpha, 0.0, 1.0)
	mat.set_shader_parameter("distort_radius", clamp(radius, 0.0, 1.0))
	mat.set_shader_parameter("distort_strength", max(0.0, strength))
	mat.set_shader_parameter("distort_speed", max(0.0, speed))
	# Frequency is optional (default in shader is 5.0); we keep it low to reduce dizziness.
	mat.set_shader_parameter("distort_frequency", clamp(ripple_frequency, 0.5, 8.0))
	_update_ripple_center_uv()


func _update_ripple_center_uv() -> void:
	if not ripple_fx:
		return
	var mat := ripple_fx.material as ShaderMaterial
	if not mat:
		return
	var viewport := get_viewport()
	if not viewport:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return
	var screen_pos: Vector2 = center.global_position
	var uv := Vector2(screen_pos.x / viewport_size.x, screen_pos.y / viewport_size.y)
	mat.set_shader_parameter("center_uv", uv)


func _configure_particles() -> void:
	# Use mixed textures: suction=S1/S2/S3 + star; burst=P1/P2/P3 + star.
	# Keep sizes consistent with star settings.
	if _gather_emitters.is_empty():
		_init_texture_mix_emitters()
	if _burst_emitters.is_empty():
		_init_texture_mix_emitters()

	# Gather (suction) materials
	for e in _gather_emitters:
		var gmat := e.process_material as ParticleProcessMaterial
		if not gmat:
			continue
		_set_if_has(gmat, "emission_shape", ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE)
		_set_if_has(gmat, "emission_sphere_radius", 520.0)
		_set_if_has(gmat, "lifetime_randomness", 0.25)
		_set_if_has(gmat, "initial_velocity_min", 10.0)
		_set_if_has(gmat, "initial_velocity_max", 80.0)
		_set_if_has(gmat, "radial_accel_min", -1100.0)
		_set_if_has(gmat, "radial_accel_max", -650.0)
		_set_if_has(gmat, "tangential_accel_min", -520.0)
		_set_if_has(gmat, "tangential_accel_max", 520.0)
		_set_if_has(gmat, "angular_velocity_min", -260.0)
		_set_if_has(gmat, "angular_velocity_max", 260.0)
		_set_if_has(gmat, "scale_min", 0.03)
		_set_if_has(gmat, "scale_max", 0.12)
		_set_if_has(gmat, "color", Color(color_r.r, color_r.g, color_r.b, 0.55))

	# Burst materials
	for e in _burst_emitters:
		var bmat := e.process_material as ParticleProcessMaterial
		if not bmat:
			continue
		_set_if_has(bmat, "emission_shape", ParticleProcessMaterial.EMISSION_SHAPE_SPHERE)
		_set_if_has(bmat, "emission_sphere_radius", 8.0)
		_set_if_has(bmat, "lifetime_randomness", 0.08)
		_set_if_has(bmat, "initial_velocity_min", 320.0)
		_set_if_has(bmat, "initial_velocity_max", 1150.0)
		_set_if_has(bmat, "direction", Vector3(0, -1, 0))
		_set_if_has(bmat, "spread", 32.0)
		_set_if_has(bmat, "gravity", Vector3(0, 220, 0))
		_set_if_has(bmat, "angular_velocity_min", -520.0)
		_set_if_has(bmat, "angular_velocity_max", 520.0)
		_set_if_has(bmat, "scale_min", 0.06)
		_set_if_has(bmat, "scale_max", 0.18)
		# Per-rarity burst style is applied at runtime in _apply_burst_style().
		_set_if_has(bmat, "color", Color(1, 1, 1, 0.8))

	# Keep total counts conservative for mobile; distribute across emitters.
	_distribute_amounts(_gather_emitters, maxi(220, gather_particles.amount))
	_distribute_amounts(_burst_emitters, maxi(280, burst_particles.amount))


func _init_texture_mix_emitters() -> void:
	# Build extra emitters so we can mix multiple textures (S1..S3 / P1..P3) plus original star.
	_ensure_suction_orbit()
	if _gather_emitters.is_empty():
		_gather_emitters = [gather_particles]
		gather_particles.texture = STAR_TEX
		if _suction_orbit:
			_reparent_keep_transform(gather_particles, _suction_orbit)
		for p in SUCTION_TEX_PATHS:
			var tex := _safe_load_texture(p)
			if tex:
				_gather_emitters.append(_clone_particles(gather_particles, "Gather_" + p.get_file().get_basename(), tex, _suction_orbit))

	if _burst_emitters.is_empty():
		_burst_emitters = [burst_particles]
		burst_particles.texture = STAR_TEX
		for p in BURST_TEX_PATHS:
			var tex := _safe_load_texture(p)
			if tex:
				_burst_emitters.append(_clone_particles(burst_particles, "Burst_" + p.get_file().get_basename(), tex, center))

	# Ensure emitters start off.
	_set_emitters_emitting(_gather_emitters, false)
	_set_emitters_emitting(_burst_emitters, false)


func _safe_load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as Texture2D


func _clone_particles(src: GPUParticles2D, new_name: String, tex: Texture2D, parent: Node) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = new_name
	p.emitting = false
	p.one_shot = src.one_shot
	p.amount = src.amount
	p.lifetime = src.lifetime
	p.texture = tex
	p.modulate = Color.WHITE
	# Duplicate material so each emitter can have its own ramp/props safely.
	if src.process_material:
		p.process_material = src.process_material.duplicate()
	parent.add_child(p)
	return p


func _ensure_suction_orbit() -> void:
	if _suction_orbit and is_instance_valid(_suction_orbit):
		return
	_suction_orbit = Node2D.new()
	_suction_orbit.name = "SuctionOrbit"
	_suction_orbit.position = Vector2.ZERO
	_suction_orbit.scale = Vector2.ONE
	center.add_child(_suction_orbit)


func _reparent_keep_transform(node: Node2D, new_parent: Node2D) -> void:
	var g := node.global_transform
	var old_parent := node.get_parent()
	if old_parent:
		old_parent.remove_child(node)
	new_parent.add_child(node)
	node.global_transform = g


func _apply_burst_style(is_ssr: bool, tint_color: Color) -> void:
	if is_ssr:
		# Keep rainbow vivid.
		for e in _burst_emitters:
			e.one_shot = false
			e.modulate = Color.WHITE
			var bmat := e.process_material as ParticleProcessMaterial
			if bmat:
				_set_if_has(bmat, "spread", SSR_BURST_SPREAD_DEG)
			if bmat and _burst_rainbow_ramp and _has_prop(bmat, "color_ramp"):
				bmat.set("color_ramp", _burst_rainbow_ramp)
				_set_if_has(bmat, "color", Color(1, 1, 1, clamp(burst_rainbow_alpha, 0.05, 1.0)))
		_distribute_amounts(_burst_emitters, maxi(SSR_FILL_TOTAL_BURST_AMOUNT, burst_particles.amount))
		return

	# N/R: monochrome burst.
	for e in _burst_emitters:
		e.one_shot = true
		e.modulate = tint_color
		var bmat2 := e.process_material as ParticleProcessMaterial
		if bmat2:
			_set_if_has(bmat2, "spread", 32.0)
		if bmat2 and _burst_mono_ramp and _has_prop(bmat2, "color_ramp"):
			bmat2.set("color_ramp", _burst_mono_ramp)
			_set_if_has(bmat2, "color", Color(1, 1, 1, 0.9))
	_distribute_amounts(_burst_emitters, maxi(N_TOTAL_BURST_AMOUNT, burst_particles.amount))


func _wait_for_ssr_click() -> void:
	_awaiting_ssr_click = true
	_ssr_click_received = false
	# Temporarily intercept taps anywhere on screen.
	_prev_root_mouse_filter = root.mouse_filter
	_prev_dim_mouse_filter = dim.mouse_filter
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# Reuse existing label to hint the interaction without adding new UI.
	info_label.text = "點擊畫面揭曉"
	while not _ssr_click_received:
		await get_tree().process_frame
	_awaiting_ssr_click = false
	# Restore defaults so buttons work again.
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_ui()


func _set_emitters_emitting(list: Array[GPUParticles2D], enabled: bool) -> void:
	for e in list:
		if e:
			e.emitting = enabled


func _restart_emitters(list: Array[GPUParticles2D]) -> void:
	for e in list:
		if e:
			e.restart()


func _distribute_amounts(list: Array[GPUParticles2D], total: int) -> void:
	if list.is_empty():
		return
	var n := list.size()
	var base := int(total / n)
	var rem := int(total - base * n)
	for i in range(n):
		var v := base + (1 if i < rem else 0)
		list[i].amount = max(1, v)


func _set_if_has(obj: Object, prop: StringName, value: Variant) -> void:
	if _has_prop(obj, prop):
		obj.set(prop, value)


func _tween_set_if_has(tween: Tween, obj: Object, prop: StringName, to_value: float, duration: float) -> void:
	if not _has_prop(obj, prop):
		return
	var from_value := float(obj.get(prop))
	tween.tween_method(Callable(self, "_set_obj_prop_float").bind(obj, prop), from_value, to_value, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_obj_prop_float(value: float, obj: Object, prop: StringName) -> void:
	if obj:
		obj.set(prop, value)


func _has_prop(obj: Object, prop: StringName) -> bool:
	if not obj:
		return false
	for p in obj.get_property_list():
		if StringName(p.get("name", "")) == prop:
			return true
	return false


func _build_burst_rainbow_ramp() -> void:
	# Build once; used by BurstParticles to ensure >=10 distinct colors.
	var g: Gradient = Gradient.new()
	# 10+ rainbow-ish stops (including pink/white highlights for sparkle).
	var colors: Array[Color] = [
		Color(1.00, 0.20, 0.20, 1.0), # red
		Color(1.00, 0.55, 0.15, 1.0), # orange
		Color(1.00, 0.92, 0.20, 1.0), # yellow
		Color(0.35, 1.00, 0.35, 1.0), # green
		Color(0.20, 1.00, 0.95, 1.0), # cyan
		Color(0.25, 0.55, 1.00, 1.0), # blue
		Color(0.55, 0.30, 1.00, 1.0), # violet
		Color(1.00, 0.25, 0.95, 1.0), # magenta
		Color(1.00, 0.70, 0.95, 1.0), # pink
		Color(0.95, 0.95, 1.00, 1.0), # near-white sparkle
	]
	var n: int = maxi(2, colors.size())
	for i in range(n):
		var t: float = float(i) / float(n - 1)
		g.add_point(t, colors[i])
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	_burst_rainbow_ramp = tex


func _build_burst_mono_ramp() -> void:
	# N/R burst: black/gray/white.
	var g: Gradient = Gradient.new()
	var colors: Array[Color] = [
		Color(0.0, 0.0, 0.0, 1.0),
		Color(0.35, 0.35, 0.35, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
	]
	var n: int = maxi(2, colors.size())
	for i in range(n):
		var t: float = float(i) / float(n - 1)
		g.add_point(t, colors[i])
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = g
	tex.width = 128
	_burst_mono_ramp = tex
