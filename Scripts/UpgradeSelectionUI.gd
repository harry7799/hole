extends CanvasLayer
## UpgradeSelectionUI — 升級時彈出的 3 選 1 介面
## 暫停遊戲，玩家選完後恢復。
## 由 Main.gd 在收到 level_up 信號時 instantiate + add_child。

signal upgrade_chosen(upgrade_id: String)
signal evolution_shown(evolution: Dictionary)

@export var card_width: float = 200.0
@export var card_height: float = 280.0
@export var card_spacing: float = 16.0

var _choices: Array[Dictionary] = []
var _card_buttons: Array[Button] = []
var _root: Control = null
var _dim: ColorRect = null
var _title_label: Label = null
var _cards_container: HBoxContainer = null
var _evolution_panel: PanelContainer = null
var _evolution_label: Label = null
var _selection_made: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


# Fallback input handler — ensures card clicks work even when the tree is paused.
# Godot's GUI hit-test may skip controls on paused nodes in some configurations,
# so we manually detect clicks on card buttons here.
func _input(event: InputEvent) -> void:
	if _card_buttons.is_empty() or _choices.is_empty():
		return
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pressed = true
			pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			pressed = true
			pos = st.position
	if not pressed:
		return
	for i in range(_card_buttons.size()):
		var btn := _card_buttons[i]
		if btn and is_instance_valid(btn) and btn.get_global_rect().has_point(pos):
			_on_card_pressed(i)
			get_viewport().set_input_as_handled()
			return


func setup(choices: Array[Dictionary]) -> void:
	_choices = choices
	_populate_cards()
	# Wait one frame so layout engine computes proper sizes
	await get_tree().process_frame
	_animate_in()


func _build_ui() -> void:
	layer = 150

	# Root (full screen)
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks behind
	add_child(_root)

	# Dim background — IGNORE so it never blocks card clicks
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	# Center container using margin for proper sizing
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var center_vbox := VBoxContainer.new()
	center_vbox.name = "CenterVBox"
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vbox.add_theme_constant_override("separation", 20)
	center_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center_vbox)

	# Title
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "⬆ 選擇升級 ⬆"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_vbox.add_child(_title_label)

	# Cards container
	_cards_container = HBoxContainer.new()
	_cards_container.name = "Cards"
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_container.add_theme_constant_override("separation", int(card_spacing))
	_cards_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_vbox.add_child(_cards_container)

	# Evolution reveal panel (hidden by default)
	_evolution_panel = PanelContainer.new()
	_evolution_panel.name = "EvolutionPanel"
	_evolution_panel.visible = false
	var evo_style := StyleBoxFlat.new()
	evo_style.bg_color = Color(0.12, 0.08, 0.2, 0.95)
	evo_style.border_color = Color(1.0, 0.8, 0.2)
	evo_style.set_border_width_all(3)
	evo_style.set_corner_radius_all(12)
	evo_style.set_content_margin_all(20)
	_evolution_panel.add_theme_stylebox_override("panel", evo_style)
	center_vbox.add_child(_evolution_panel)

	_evolution_label = Label.new()
	_evolution_label.name = "EvoLabel"
	_evolution_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_evolution_label.add_theme_font_size_override("font_size", 22)
	_evolution_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_evolution_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_evolution_panel.add_child(_evolution_label)


func _populate_cards() -> void:
	# Clear old
	for child in _cards_container.get_children():
		child.queue_free()
	_card_buttons.clear()

	for i in range(_choices.size()):
		var choice: Dictionary = _choices[i]
		var card := _create_card(choice, i)
		_cards_container.add_child(card)
		_card_buttons.append(card)


func _create_card(data: Dictionary, index: int) -> Button:
	var btn := Button.new()
	btn.name = "Card_%d" % index
	btn.custom_minimum_size = Vector2(card_width, card_height)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Style
	var rarity := String(data.get("rarity", "common"))
	var border_color := Color(0.5, 0.5, 0.5)
	var bg_color := Color(0.08, 0.08, 0.15, 0.95)
	match rarity:
		"common":
			border_color = Color(0.5, 0.7, 1.0)
		"rare":
			border_color = Color(0.6, 0.3, 1.0)
			bg_color = Color(0.1, 0.05, 0.2, 0.95)
		"epic":
			border_color = Color(1.0, 0.7, 0.2)
			bg_color = Color(0.15, 0.1, 0.02, 0.95)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_color = border_color
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(10)
	style_normal.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := style_normal.duplicate() as StyleBoxFlat
	style_hover.bg_color = bg_color.lightened(0.15)
	style_hover.set_border_width_all(3)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style_normal.duplicate() as StyleBoxFlat
	style_pressed.bg_color = bg_color.lightened(0.25)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	# Content via VBoxContainer inside button
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	# Icon
	var icon_label := Label.new()
	icon_label.text = String(data.get("icon", "?"))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 42)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_label)

	# Name
	var name_label := Label.new()
	name_label.text = String(data.get("name", "???"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", border_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	# Rarity tag
	var rarity_label := Label.new()
	rarity_label.text = _rarity_display(rarity)
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_size_override("font_size", 13)
	rarity_label.add_theme_color_override("font_color", border_color.darkened(0.2))
	rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rarity_label)

	# Desc
	var desc_label := Label.new()
	desc_label.text = String(data.get("desc", ""))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.custom_minimum_size.x = card_width - 30
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	# Stack indicator (if already owned)
	var current_stack: int = 0
	if has_node("/root/RoguelikeUpgradeManager"):
		var rum = get_node("/root/RoguelikeUpgradeManager")
		current_stack = int(rum.active_upgrades.get(String(data.get("id", "")), 0))
	if current_stack > 0:
		var stack_label := Label.new()
		stack_label.text = "已持有：%d/%d" % [current_stack, int(data.get("max_stack", 1))]
		stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack_label.add_theme_font_size_override("font_size", 12)
		stack_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(stack_label)

	# Connect
	btn.pressed.connect(_on_card_pressed.bind(index))

	return btn


func _on_card_pressed(index: int) -> void:
	if _selection_made:
		return
	if index < 0 or index >= _choices.size():
		return
	_selection_made = true
	var choice: Dictionary = _choices[index]
	var uid := String(choice.get("id", ""))

	# Apply the upgrade
	if has_node("/root/RoguelikeUpgradeManager"):
		var rum = get_node("/root/RoguelikeUpgradeManager")
		rum.apply_upgrade(uid)

		# Check for evolutions
		var evolutions: Array[Dictionary] = rum.check_evolutions()
		if not evolutions.is_empty():
			await _show_evolution_reveal(evolutions)

	upgrade_chosen.emit(uid)
	_animate_out()


func _show_evolution_reveal(evolutions: Array[Dictionary]) -> void:
	for evo in evolutions:
		_evolution_panel.visible = true
		_evolution_label.text = "%s %s\n%s" % [
			String(evo.get("icon", "⭐")),
			String(evo.get("name", "???")),
			String(evo.get("desc", "")),
		]
		_evolution_panel.modulate.a = 0.0
		_evolution_panel.scale = Vector2(0.7, 0.7)
		_evolution_panel.pivot_offset = _evolution_panel.size * 0.5
		var t := create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(_evolution_panel, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(_evolution_panel, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Input.vibrate_handheld(60)
		evolution_shown.emit(evo)
		await get_tree().create_timer(2.5, true, true, true).timeout
		_evolution_panel.visible = false


func _animate_in() -> void:
	# Fade in dim + scale cards from small
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_dim, "color:a", 0.7, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	for i in range(_card_buttons.size()):
		var card := _card_buttons[i]
		card.modulate.a = 0.0
		card.scale = Vector2(0.6, 0.6)
		card.pivot_offset = card.size * 0.5
		var ct := create_tween()
		ct.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ct.tween_interval(0.08 * i)
		ct.tween_property(card, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(card, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	Input.vibrate_handheld(25)


func _animate_out() -> void:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_dim, "color:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for card in _card_buttons:
		var ct := create_tween()
		ct.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ct.tween_property(card, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.2, true, true, true).timeout
	queue_free()


func _rarity_display(rarity: String) -> String:
	match rarity:
		"common":
			return "◆ 普通"
		"rare":
			return "◆◆ 稀有"
		"epic":
			return "◆◆◆ 史詩"
	return "◆ 普通"
