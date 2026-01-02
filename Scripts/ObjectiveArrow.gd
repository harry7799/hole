extends Control

@export var arrow_color: Color = Color(0.25, 1.0, 0.25, 0.95)
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.22)
@export var size_px: float = 56.0
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.35)
@export var outline_width: float = 2.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(size_px, size_px)
	pivot_offset = size * 0.5
	queue_redraw()

func set_center_position(screen_pos: Vector2) -> void:
	position = screen_pos - pivot_offset

func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	var c: Vector2 = size * 0.5

	# Subtle backing so it reads on bright backgrounds.
	draw_circle(c, r, bg_color)
	if outline_width > 0.0:
		draw_arc(c, r - outline_width * 0.5, 0.0, TAU, 64, outline_color, outline_width, true)

	# Arrow points to +X by default. Rotation is controlled by parent.
	var tip := Vector2(size.x * 0.82, size.y * 0.50)
	var back_top := Vector2(size.x * 0.30, size.y * 0.28)
	var back_bottom := Vector2(size.x * 0.30, size.y * 0.72)
	var pts := PackedVector2Array([tip, back_bottom, back_top])
	var cols := PackedColorArray([arrow_color, arrow_color, arrow_color])
	draw_polygon(pts, cols)

	if outline_width > 0.0:
		draw_polyline(PackedVector2Array([tip, back_bottom, back_top, tip]), outline_color, outline_width, true)
