extends Node2D

@export var black_hole_path: NodePath = "../BlackHole"

# 單手操作（跟隨手指 / Drag-to-move）
@export var max_speed: float = 950.0
@export var speed_factor: float = 2.2 # 距離->速度倍率
@export var acceleration: float = 12.0
@export var deceleration: float = 14.0
@export var dead_zone_px: float = 18.0

# 虛擬搖桿設定（手機）
@export var virtual_joystick_enabled: bool = true
@export var joystick_radius_px: float = 110.0
@export var joystick_deadzone_px: float = 10.0
@export var joystick_left_half_only: bool = false

@onready var joystick_bg = get_node_or_null("%VirtualJoystickBG") as Control
@onready var joystick_knob = get_node_or_null("%VirtualJoystickKnob") as Control

var _joystick_active: bool = false
var _joystick_touch_index: int = -1
var _joystick_origin_screen: Vector2 = Vector2.ZERO

# 桌機支援
@export var keyboard_speed: float = 650.0
@export var desktop_mouse_follow_without_click: bool = true

# 加速（Shift / 左下角加速鍵）
@export var boost_multiplier: float = 1.6
@export var boost_stability_cost_per_sec: float = 8.0

@onready var black_hole = get_node(black_hole_path) as Area2D

var _base_max_speed: float = 0.0
var _base_keyboard_speed: float = 0.0

var _base_acceleration: float = 0.0
var _base_deceleration: float = 0.0

var _last_tap_msec: int = -1
var _last_tap_pos: Vector2 = Vector2.ZERO
@export var double_tap_window_sec: float = 0.28
@export var double_tap_max_distance_px: float = 80.0

var _velocity: Vector2 = Vector2.ZERO
var _touch_active: bool = false
var _touch_screen_pos: Vector2 = Vector2.ZERO
var _touch_target_world: Vector2 = Vector2.ZERO
var _move_touch_index: int = -1


func _ready() -> void:
	_base_max_speed = max_speed
	_base_keyboard_speed = keyboard_speed
	_base_acceleration = acceleration
	_base_deceleration = deceleration
	# 黑洞升級時，相機/視覺可能變動；清掉速度避免「瞬移感」
	if black_hole and black_hole.has_signal("level_up"):
		if not black_hole.level_up.is_connected(_on_black_hole_level_up):
			black_hole.level_up.connect(_on_black_hole_level_up)


func _on_black_hole_level_up(_new_level: int) -> void:
	_velocity = Vector2.ZERO
	# 物理權重感：等級越高，轉向/停下來稍微慢一點（更重）
	var lv: int = _new_level
	if lv <= 0:
		lv = 1
	var weight: float = 1.0 + float(lv - 1) * 0.03
	weight = clampf(weight, 1.0, 1.9)
	acceleration = _base_acceleration / weight
	deceleration = _base_deceleration / weight


func apply_speed_multiplier(mult: float) -> void:
	mult = clampf(mult, 0.5, 3.0)
	max_speed = _base_max_speed * mult
	keyboard_speed = _base_keyboard_speed * mult


func _input(event):
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			# 雙擊：主動釋放 Shockwave（消耗穩定度）
			var now_msec: int = Time.get_ticks_msec()
			if _last_tap_msec >= 0:
				var dt_sec: float = float(now_msec - _last_tap_msec) / 1000.0
				if dt_sec <= double_tap_window_sec and e.position.distance_to(_last_tap_pos) <= double_tap_max_distance_px:
					if black_hole and black_hole.has_method("trigger_shockwave"):
						black_hole.call("trigger_shockwave")
						# 避免同一次雙擊又把觸控移動目標設掉
						_last_tap_msec = -1
						return
			_last_tap_msec = now_msec
			_last_tap_pos = e.position

			# decide if this touch should be a joystick touch or a free-follow touch
			if virtual_joystick_enabled:
				_joystick_touch_index = e.index
				_joystick_active = true
				_joystick_origin_screen = e.position
				_touch_active = true
				_touch_screen_pos = e.position
				# show joystick visuals if present
				if joystick_bg:
					joystick_bg.visible = true
					joystick_bg.position = _joystick_origin_screen
				if joystick_knob:
					joystick_knob.visible = true
					joystick_knob.position = _joystick_origin_screen
			else:
				_move_touch_index = e.index
				_touch_active = true
				_touch_screen_pos = e.position
				_touch_target_world = _screen_to_world(e.position)
		else:
			if e.index == _move_touch_index:
				_move_touch_index = -1
				_touch_active = false
			if e.index == _joystick_touch_index:
				_joystick_touch_index = -1
				_joystick_active = false
				_touch_active = false
				if joystick_bg:
					joystick_bg.visible = false
				if joystick_knob:
					joystick_knob.visible = false
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _move_touch_index:
			_touch_active = true
			_touch_screen_pos = d.position
			_touch_target_world = _screen_to_world(d.position)
		if d.index == _joystick_touch_index:
			_touch_active = true
			_touch_screen_pos = d.position
			# update knob visual
			var disp := d.position - _joystick_origin_screen
			var len := disp.length()
			var clamped := disp
			if len > joystick_radius_px:
				clamped = disp.normalized() * joystick_radius_px
			if joystick_knob:
				joystick_knob.position = _joystick_origin_screen + clamped
		return


func _physics_process(delta):
	if not black_hole:
		return

	# 掉幀/卡頓時 delta 可能非常大，會讓位置一次加很多，玩家會感覺「瞬移」
	# 這裡只限制移動積分用的 dt，不影響計時/扣穩定度等邏輯時間
	var move_dt: float = minf(delta, 1.0 / 30.0)

	var boost_active: bool = _is_boost_active()

	# 1) 鍵盤控制（桌機 fallback）
	var input_vec := Vector2.ZERO
	input_vec.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	input_vec.y = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	if input_vec != Vector2.ZERO:
		input_vec = input_vec.normalized()
		var desired_vel_keyboard: Vector2 = input_vec * keyboard_speed
		if boost_active:
			desired_vel_keyboard *= boost_multiplier
			_apply_boost_cost(delta)
		_velocity = _velocity.lerp(desired_vel_keyboard, acceleration * move_dt)
		black_hole.global_position += _velocity * move_dt
		return

	# 2) 指標/觸控跟隨
	var mouse_follow: bool = desktop_mouse_follow_without_click or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var has_pointer: bool = _touch_active or mouse_follow
	if not has_pointer:
		_velocity = _velocity.lerp(Vector2.ZERO, deceleration * move_dt)
		black_hole.global_position += _velocity * move_dt
		return

	# 避免點擊 UI 時黑洞也跟著跑：僅阻擋「互動型 UI」(按鈕/滑桿/輸入框)
	if not _touch_active:
		var hovered: Control = get_viewport().gui_get_hovered_control()
		var hovering_interactive_ui: bool = false
		if hovered:
			hovering_interactive_ui = (hovered is BaseButton) or (hovered is Range) or (hovered is LineEdit)
		if hovering_interactive_ui:
			_velocity = _velocity.lerp(Vector2.ZERO, deceleration * move_dt)
			black_hole.global_position += _velocity * move_dt
			return

	# 如果虛擬搖桿啟用且處於活動狀態，使用搖桿向量
	if virtual_joystick_enabled and _joystick_active:
		var disp: Vector2 = _touch_screen_pos - _joystick_origin_screen
		var disp_len: float = disp.length()
		if disp_len < joystick_deadzone_px:
			_velocity = _velocity.lerp(Vector2.ZERO, deceleration * move_dt)
			black_hole.global_position += _velocity * move_dt
			return
		var dir: Vector2 = disp.normalized()
		var desired_speed: float = minf(disp_len * speed_factor, max_speed)
		var desired_vel: Vector2 = dir * desired_speed
		if boost_active:
			desired_vel *= boost_multiplier
			_apply_boost_cost(delta)
		_velocity = _velocity.lerp(desired_vel, acceleration * move_dt)
		black_hole.global_position += _velocity * move_dt
		return

	var target_world: Vector2 = _get_pointer_world_position()
	var to_target: Vector2 = target_world - black_hole.global_position
	var dist: float = to_target.length()
	if dist < dead_zone_px:
		_velocity = _velocity.lerp(Vector2.ZERO, deceleration * move_dt)
		black_hole.global_position += _velocity * move_dt
		return

	var dir: Vector2 = to_target / dist
	var desired_speed: float = minf(dist * speed_factor, max_speed)
	var desired_vel: Vector2 = dir * desired_speed
	if boost_active:
		desired_vel *= boost_multiplier
		_apply_boost_cost(delta)
	_velocity = _velocity.lerp(desired_vel, acceleration * move_dt)
	black_hole.global_position += _velocity * move_dt


func _is_boost_active() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)


func _apply_boost_cost(delta: float) -> void:
	if boost_stability_cost_per_sec <= 0.0:
		return
	var cost: float = boost_stability_cost_per_sec * delta
	if black_hole and black_hole.has_method("apply_damage"):
		black_hole.call("apply_damage", cost, false)


func _get_pointer_world_position() -> Vector2:
	# 觸控：使用「按下/拖曳事件」時快取的世界座標
	# 這可避免 Camera2D zoom/transform 改變時目標點跟著跳，造成黑洞瞬移感
	if _touch_active:
		return _touch_target_world
	# 桌機：直接用世界滑鼠位置（會包含 Camera2D 變換）
	return get_global_mouse_position()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	# 用 canvas transform 反解（避免 Variant 回傳導致型別推斷失敗）
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	return inv * screen_pos
