extends RigidBody2D

@export var textures: Array[Texture2D] 

# 目標視覺尺寸（世界單位≈像素）。用貼圖尺寸換算，確保不同貼圖看起來都夠小。
@export var target_visual_size_min: float = 6.0
@export var target_visual_size_max: float = 12.0

# Debug：若你回報「看起來沒變小」，把它勾成 true
@export var debug_print_size: bool = false

var _visual_size: float = 0.0

const PREY_VISUAL_SCALE_MULTIPLIER: float = 10.0

@onready var sprite = $Sprite2D


func _apply_visual_scale() -> void:
	# 強制以「貼圖像素尺寸」換算縮放，避免任何地方覆蓋 scale 後看起來沒變
	_visual_size = randf_range(target_visual_size_min, target_visual_size_max)
	var max_dim: float = 64.0
	var tex_path := ""
	if sprite and sprite.texture:
		var ts: Vector2 = sprite.texture.get_size()
		max_dim = maxf(ts.x, ts.y)
		tex_path = sprite.texture.resource_path
	max_dim = maxf(1.0, max_dim)
	var s: float = _visual_size / max_dim
	s *= PREY_VISUAL_SCALE_MULTIPLIER
	# 同時縮 Sprite2D（保證視覺會變小），並把 root scale 固定為 1（避免父層/物理行為干擾）
	scale = Vector2.ONE
	if sprite:
		sprite.scale = Vector2.ONE * s
	# 碰撞：用固定的小半徑（與視覺尺寸對齊），避免「看起來很大」的互動範圍
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		cs.scale = Vector2.ONE
		if cs.shape is CircleShape2D:
			(cs.shape as CircleShape2D).radius = maxf(4.0, (_visual_size * PREY_VISUAL_SCALE_MULTIPLIER) * 0.55)

	if debug_print_size:
		var sprite_scale: Vector2 = Vector2.ONE
		if sprite:
			sprite_scale = sprite.scale
		print("[Prey] tex=", tex_path, " max_dim=", max_dim, " target_px=", _visual_size, " sprite_scale=", sprite_scale)

func _ready():
	add_to_group("Prey")
	add_to_group("Swallowables")
	if textures.size() > 0:
		var random_index = randi() % textures.size()
		sprite.texture = textures[random_index]

	rotation = randf_range(0.0, TAU)
	_apply_visual_scale()
	# 保險：等被 add_child 之後再套一次，避免外部在同一幀覆蓋 scale
	call_deferred("_apply_visual_scale")
	angular_velocity = randf_range(-2.0, 2.0)
	
# 【新增】提供分數給黑洞
func get_score_value() -> float:
	# 用視覺尺寸估算能量值，避免不同貼圖尺寸導致分數偏差
	var k: float = clampf(_visual_size / 24.0, 0.4, 1.6)
	var area = maxf(0.05, k * k)
	return area * 60.0
