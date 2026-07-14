extends Area2D

@export var speed: float = 400.0
@export var damage: float = 5.0

var velocity: Vector2 = Vector2.ZERO

const DIRECTION_EPSILON_SQUARED := 0.0001

# The black hole's gravity Area2D is large; we only apply damage near the core.
var _pending_hit_target: Node2D = null

@onready var _lifetime_timer := get_node_or_null("LifetimeTimer") as Timer
@onready var _sprite := get_node_or_null("Sprite2D") as Sprite2D


func setup_for_spawn(pos: Vector2, vel: Vector2, spd: float, dmg: float, tex: Texture2D) -> void:
	global_position = pos
	set_motion(vel)
	speed = spd
	damage = dmg
	_pending_hit_target = null
	if _sprite and tex:
		_sprite.texture = tex
	visible = true
	set_physics_process(true)
	set_process(true)
	monitoring = true
	monitorable = true
	_recalc_and_start_lifetime()


func set_motion(new_velocity: Vector2) -> void:
	velocity = new_velocity
	_sync_rotation_to_velocity()


func _sync_rotation_to_velocity() -> void:
	if velocity.length_squared() > DIRECTION_EPSILON_SQUARED:
		# Projectile art is authored nose-first along local +X.
		global_rotation = velocity.angle()


func _recalc_and_start_lifetime() -> void:
	# 讓子彈能飛過整個螢幕：依視窗大小/相機縮放估算存活時間
	var vp = get_viewport().get_visible_rect().size
	var cam = get_viewport().get_camera_2d()
	var zoom = cam.zoom if cam else Vector2.ONE
	var world_vp = Vector2(vp.x / max(0.001, zoom.x), vp.y / max(0.001, zoom.y))
	var diag = world_vp.length()
	var lifetime = diag / max(1.0, speed) + 1.5
	lifetime = clamp(lifetime, 2.0, 10.0)
	if _lifetime_timer:
		_lifetime_timer.stop()
		_lifetime_timer.wait_time = lifetime
		_lifetime_timer.one_shot = true
		if not _lifetime_timer.timeout.is_connected(_on_lifetime_timer_timeout):
			_lifetime_timer.timeout.connect(_on_lifetime_timer_timeout)
		_lifetime_timer.start()

func _ready():
	# 保險起見：確保 body_entered 有連到傷害回呼（避免場景未連線造成不扣血）
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	# 黑洞是 Area2D，需要 area_entered 才會觸發
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	add_to_group("EnemyProjectiles")

	_recalc_and_start_lifetime()

func _physics_process(delta):
	_sync_rotation_to_velocity()
	# Poll the core directly. The black hole's pull Area is intentionally huge,
	# so area_entered can fire once far away or be missed by pooled projectiles.
	if _try_apply_core_damage():
		return
	global_position += velocity * delta
	_try_apply_core_damage()


func _try_apply_core_damage() -> bool:
	if not _pending_hit_target or not is_instance_valid(_pending_hit_target):
		_pending_hit_target = get_tree().get_first_node_in_group("Player") as Node2D
		if not is_instance_valid(_pending_hit_target):
			_pending_hit_target = null
			return false
	var r: float = 140.0
	if _pending_hit_target.has_method("get_damage_radius"):
		r = float(_pending_hit_target.call("get_damage_radius"))
	var d: float = global_position.distance_to(_pending_hit_target.global_position)
	if d > r:
		return false
	# Fever: no damage, but the projectile is absorbed at the actual core.
	if _pending_hit_target.has_method("is_fever_active") and bool(_pending_hit_target.call("is_fever_active")):
		_pending_hit_target = null
		_recycle()
		return true
	if _pending_hit_target.has_method("apply_damage"):
		_pending_hit_target.apply_damage(damage)
	_pending_hit_target = null
	_recycle()
	return true

# 訊號：當撞到物體時
func _on_body_entered(body):
	_deal_hit(body)
	# 【新增】如果撞到其他 RigidBody2D（例如被吞噬物體）也應銷毀
	if body is RigidBody2D:
		_recycle()


func _on_area_entered(area: Area2D) -> void:
	_deal_hit(area)


func _deal_hit(hit: Object) -> void:
	if not hit:
		return
	if hit.is_in_group("Player") or hit.has_method("apply_damage"):
		# Fever：子彈不造成傷害，但也不會「自動消失」；等真的碰到核心才回收。
		if hit.has_method("is_fever_active") and bool(hit.call("is_fever_active")):
			if hit is Node2D:
				_pending_hit_target = hit as Node2D
				return
			_recycle()
			return
		if hit is Node2D:
			# If we entered the gravity area from far away, wait until we reach the core.
			_pending_hit_target = hit as Node2D
			_try_apply_core_damage()
			return
		# Fallback
		if hit.has_method("apply_damage"):
			hit.apply_damage(damage)
		_recycle()


# 訊號：LifetimeTimer 時間到 (已在編輯器連線)
func _on_lifetime_timer_timeout() -> void:
	# 【修正】時間到時，投射物銷毀
	_recycle()


func _recycle() -> void:
	_pending_hit_target = null
	# 若主場景支援物件池，就回收；否則照舊 queue_free
	var main = get_tree().get_current_scene()
	if main and main.has_method("recycle_enemy_projectile"):
		main.call("recycle_enemy_projectile", self)
		return
	queue_free()
