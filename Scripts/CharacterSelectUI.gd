extends CanvasLayer
## CharacterSelectUI — 開始遊戲前的黑洞類型選擇介面
## 由 Main.gd 在開始遊戲按鈕後、_start_game() 前彈出。
## 使用 2×3 Grid 佈局，適合 720×1280 手機直式螢幕。

signal character_chosen(character_id: String)
signal cancelled

var _root: Control = null
var _dim: ColorRect = null
var _title_label: Label = null
var _grid: GridContainer = null
var _cancel_button: Button = null
var _card_buttons: Array[Button] = []
var _character_ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_populate_characters()
	# Wait one frame so the layout engine computes proper sizes / rects
	await get_tree().process_frame
	_animate_in()


# ── UI Construction ──────────────────────────────────────────────

func _build_ui() -> void:
	layer = 150

	# Root covers full screen — STOP blocks all input behind the panel
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Semi-transparent dim — IGNORE so it never eats clicks
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	# MarginContainer for safe padding
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 50)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	# Vertical layout: title → grid → cancel
	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_theme_constant_override("separation", 24)
	outer_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(outer_vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "選擇黑洞類型"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_vbox.add_child(_title_label)

	# ScrollContainer for vertical overflow on small screens
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	outer_vbox.add_child(scroll)

	# 2-column grid
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_grid)

	# Cancel button
	_cancel_button = Button.new()
	_cancel_button.text = "返回"
	_cancel_button.custom_minimum_size = Vector2(200, 50)
	_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel_button.add_theme_font_size_override("font_size", 20)
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.15, 0.12, 0.25, 0.9)
	cancel_style.border_color = Color(0.5, 0.4, 0.7)
	cancel_style.set_border_width_all(2)
	cancel_style.set_corner_radius_all(8)
	cancel_style.set_content_margin_all(8)
	_cancel_button.add_theme_stylebox_override("normal", cancel_style)
	_cancel_button.pressed.connect(_on_cancel)
	outer_vbox.add_child(_cancel_button)


# ── Population ───────────────────────────────────────────────────

func _populate_characters() -> void:
	if not has_node("/root/RoguelikeUpgradeManager"):
		return
	var rum = get_node("/root/RoguelikeUpgradeManager")
	var defs: Dictionary = rum.get_character_defs()
	var unlocked: Array[String] = rum.get_unlocked_characters()

	_character_ids.clear()
	_card_buttons.clear()

	# Sort: standard first, then alphabetical
	var sorted_ids: Array[String] = []
	if defs.has("standard"):
		sorted_ids.append("standard")
	for cid in defs:
		if String(cid) != "standard":
			sorted_ids.append(String(cid))

	for cid in sorted_ids:
		var cdef: Dictionary = defs.get(cid, {}) as Dictionary
		var is_unlocked := cid in unlocked
		var card := _create_character_card(cdef, is_unlocked, cid)
		_grid.add_child(card)
		_card_buttons.append(card)
		_character_ids.append(cid)


# ── Card Factory ─────────────────────────────────────────────────

func _create_character_card(data: Dictionary, is_unlocked: bool, cid: String) -> Button:
	var btn := Button.new()
	# Each card fills half the grid width; height determined by content
	btn.custom_minimum_size = Vector2(0, 190)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = not is_unlocked
	btn.clip_text = false
	btn.text = ""

	# ── Style ──
	var bg_color := Color(0.08, 0.08, 0.18, 0.95) if is_unlocked else Color(0.05, 0.05, 0.08, 0.95)
	var border_color := Color(0.6, 0.5, 1.0) if is_unlocked else Color(0.3, 0.3, 0.3)

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style)

	var style_hover := style.duplicate() as StyleBoxFlat
	style_hover.bg_color = bg_color.lightened(0.15)
	style_hover.border_color = Color(0.8, 0.7, 1.0)
	style_hover.set_border_width_all(3)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style.duplicate() as StyleBoxFlat
	style_pressed.bg_color = bg_color.lightened(0.3)
	style_pressed.border_color = Color(1.0, 0.9, 0.5)
	style_pressed.set_border_width_all(3)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	var style_disabled := style.duplicate() as StyleBoxFlat
	style_disabled.bg_color = Color(0.04, 0.04, 0.06, 0.9)
	style_disabled.border_color = Color(0.2, 0.2, 0.2)
	btn.add_theme_stylebox_override("disabled", style_disabled)

	# ── Content VBox inside button ──
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	# Icon
	var icon_label := Label.new()
	icon_label.text = String(data.get("icon", "?")) if is_unlocked else "🔒"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 34)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_label)

	# Name
	var name_label := Label.new()
	name_label.text = String(data.get("name", "???")) if is_unlocked else "???"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1) if is_unlocked else Color(0.4, 0.4, 0.4))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = String(data.get("desc", "")) if is_unlocked else "（未解鎖）"
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7) if is_unlocked else Color(0.3, 0.3, 0.3))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	# Modifier summary
	if is_unlocked:
		var mods: Dictionary = data.get("modifiers", {}) as Dictionary
		if not mods.is_empty():
			var mod_text := ""
			for k in mods:
				var v: float = float(mods[k])
				var sign_str := "+" if v >= 0 else ""
				mod_text += "%s: %s%.0f%%\n" % [_modifier_display_name(String(k)), sign_str, v * 100.0]
			var mod_label := Label.new()
			mod_label.text = mod_text.strip_edges()
			mod_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mod_label.add_theme_font_size_override("font_size", 10)
			mod_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
			mod_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(mod_label)

	btn.pressed.connect(_on_character_selected.bind(cid))
	return btn


# ── Callbacks ────────────────────────────────────────────────────

func _on_character_selected(cid: String) -> void:
	if has_node("/root/RoguelikeUpgradeManager"):
		var rum = get_node("/root/RoguelikeUpgradeManager")
		rum.selected_character = cid
	character_chosen.emit(cid)
	_animate_out()


func _on_cancel() -> void:
	cancelled.emit()
	_animate_out()


# ── Animation ────────────────────────────────────────────────────

func _animate_in() -> void:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_dim, "color:a", 0.82, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in range(_card_buttons.size()):
		var card := _card_buttons[i]
		card.modulate.a = 0.0
		card.scale = Vector2(0.7, 0.7)
		card.pivot_offset = card.size * 0.5
		var ct := create_tween()
		ct.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ct.tween_interval(0.05 * i)
		ct.tween_property(card, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(card, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_out() -> void:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_dim, "color:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for card in _card_buttons:
		var ct := create_tween()
		ct.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ct.tween_property(card, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.25, true, true, true).timeout
	queue_free()


# ── Helpers ──────────────────────────────────────────────────────

func _modifier_display_name(key: String) -> String:
	match key:
		"pull_strength_mult": return "拉力"
		"decay_rate_mult": return "衰減"
		"pull_radius_mult": return "吸引範圍"
		"move_speed_mult": return "移速"
		"score_mult": return "分數"
		"passive_magnet": return "磁鐵"
		"kill_radius_mult": return "吞噬範圍"
		"fever_duration_bonus": return "Fever時間"
		"fever_threshold_reduction": return "Fever門檻"
		"max_stability_offset": return "穩定度上限"
	return key
