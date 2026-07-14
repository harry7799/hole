extends Node2D

# ----------------------------------------------------
# UI 節點引用 (請確保場景中這些節點都有設定 Unique Name %)
# ----------------------------------------------------
@onready var score_label = get_node_or_null("%ScoreLabel") as Label
@onready var level_label = get_node_or_null("%LevelLabel") as Label
@onready var camera      = %Camera2D
@onready var time_label  = %TimeLabel        
@onready var stability_bar = %StabilityBar    # 能量條 (ProgressBar)
@onready var wanted_label = %WantedLabel    
@onready var emp_button = %EMP_Button # 假設你已在 MainScene.tscn 設置 Unique Name
@onready var settings_button = %SettingsButton
@onready var menu_settings_button = get_node_or_null("%MenuSettingsButton") as Button
@onready var hud = %HUD
@onready var main_menu = %MainMenu
@onready var start_button = %StartButton
@onready var campaign_start_button = get_node_or_null("%CampaignStartButton") as Button
@onready var endless_button = get_node_or_null("%EndlessButton") as Button
@onready var coins_label = get_node_or_null("%CoinsLabel") as Label
@onready var skins_button = get_node_or_null("%SkinsButton") as Button
@onready var gacha_button = get_node_or_null("%GachaButton") as Button
@onready var upgrades_button = get_node_or_null("%UpgradesButton") as Button
@onready var toast_label = %ToastLabel
@onready var damage_flash = %DamageFlash
@onready var shockwave_ring = get_node_or_null("%ShockwaveRing") as Line2D
@onready var wanted_overlay = get_node_or_null("%WantedOverlay") as ColorRect
@onready var campaign_gold_overlay = get_node_or_null("%CampaignGoldOverlay") as ColorRect
@onready var objective_arrow = get_node_or_null("%ObjectiveArrow") as Control
@onready var shockwave_button = get_node_or_null("%ShockwaveButton") as Button
@onready var idle_rewards_button = get_node_or_null("%IdleRewardsButton") as Button
@onready var fever_bar = get_node_or_null("%FeverBar") as ProgressBar
var music_pitch_toggle: CheckBox = null

@onready var sfx_level_up: AudioStreamPlayer = get_node_or_null("%SfxLevelUp") as AudioStreamPlayer
@onready var sfx_wanted_up: AudioStreamPlayer = get_node_or_null("%SfxWantedUp") as AudioStreamPlayer

@export var rewarded_time_bonus: float = 20.0

# -----------------------------
# 音樂
# -----------------------------
@export var menu_music: AudioStream
@export var battle_music: AudioStream
# 可選：打開設定視窗時播放的音樂（不指定就沿用當前音樂）
@export var settings_music: AudioStream
@export var battle_music_volume_db: float = -6.0
@export var sfx_volume_db: float = -6.0
var _music_player: AudioStreamPlayer = null
var _current_music_stream: AudioStream = null
var _settings_dialog: AcceptDialog = null
var _settings_layer: CanvasLayer = null
var _music_slider: HSlider = null
var _music_value_label: Label = null
var _sfx_slider: HSlider = null
var _sfx_value_label: Label = null

var _paused_by_settings: bool = false
var _settings_modal_active: bool = false
var _prev_main_menu_mouse_filter: int = Control.MOUSE_FILTER_STOP
var _prev_hud_mouse_filter: int = Control.MOUSE_FILTER_STOP

@export var enable_dynamic_bgm_pitch: bool = false

# 特效：全螢幕引力漣漪（可在設定中關閉）
@export var gravity_ripple_enabled: bool = true
var _ripple_checkbox: CheckBox = null
var _abandon_button: Button = null
var _abandon_confirm_dialog: ConfirmationDialog = null
var _settings_root_vbox: VBoxContainer = null
var _settings_mission_container: VBoxContainer = null

# ----------------------------------------------------
# Meta Game（局外成長 / 變現點）
# ----------------------------------------------------
const META_SAVE_PATH_EDITOR: String = "user://meta.cfg"
const META_SAVE_PATH_RUNTIME: String = "user://meta_runtime.cfg"

func _get_meta_save_path() -> String:
	# Avoid shipping/testing with the developer's existing progress.
	# In Godot editor: keep using the main meta file.
	# In exported builds: use a separate save file so friends start fresh.
	return META_SAVE_PATH_EDITOR if OS.has_feature("editor") else META_SAVE_PATH_RUNTIME

var meta_coins: int = 0
var meta_selected_skin: String = "classic"
var meta_unlocked_skins: Dictionary = {"classic": true}

var meta_selected_map: String = "default"
var meta_unlocked_maps: Dictionary = {"default": true}

var meta_selected_menu_map: String = "default"

# Campaign progression
var meta_campaign_cleared: bool = false
var meta_campaign_max_unlocked: int = 1

var upgrade_gravity_level: int = 0

# ----------------------------------------------------
# Game Mode（自由無盡 / 關卡制）
# ----------------------------------------------------
enum GameMode { INFINITE, CAMPAIGN, ENDLESS }
var game_mode: int = GameMode.INFINITE
var _upgrade_selection_ui: CanvasLayer = null
var _character_select_ui: CanvasLayer = null
var _paused_by_upgrade: bool = false
var _pending_game_mode: int = GameMode.INFINITE
var campaign_level_id: int = 1

# Frame-level group query cache (avoids re-allocating arrays every frame)
var _cached_groups: Dictionary = {}
var _cache_frame: int = -1
var _spawn_mgr: SpawnManager = null

# Boss 系統
var _boss_hp_container: PanelContainer = null
var _boss_hp_bar: ProgressBar = null
var _boss_hp_label: Label = null

# 地圖事件系統
var _map_event_manager: MapEventManager = null
var _map_event_label: Label = null

# 任務系統 UI（嵌入設定視窗）
var _mission_items: Array[Dictionary] = []  # [{label: Label, bar: ProgressBar, id: String}]
var _run_enemies_killed: int = 0
var _run_shockwave_count: int = 0

func _get_cached_group(group_name: String) -> Array:
	var frame := Engine.get_frames_drawn()
	if frame != _cache_frame:
		_cache_frame = frame
		_cached_groups.clear()
	if not _cached_groups.has(group_name):
		_cached_groups[group_name] = get_tree().get_nodes_in_group(group_name)
	return _cached_groups[group_name]

const CAMPAIGN_MAP_ID: String = "golden singularity"
const CAMPAIGN_MAP_PATH: String = "res://Maps/Golden Singularity.png"
const CAMPAIGN_MUSIC_PATH: String = "res://Maps/Golden Singularity.mp3"

const CAMPAIGN_LEVEL_COUNT: int = 4
var _campaign_levels_dialog: AcceptDialog = null
var _campaign_level_preview: TextureRect = null
var _campaign_level_name_label: Label = null
var _campaign_level_locked_label: TextureRect = null
var _campaign_level_start_button: Button = null
var _campaign_level_selected_index: int = 0
var _campaign_levels_swipe_active: bool = false
var _campaign_levels_swipe_start_x: float = 0.0
var _campaign_levels_swipe_last_x: float = 0.0

const GOLDEN_CORE_SCENE: PackedScene = preload("res://Scenes/GoldenCoreObjective.tscn")

var _campaign_center: Vector2 = Vector2.ZERO
var _campaign_objective: Node2D = null
var _campaign_clear_dialog: ConfirmationDialog = null
var _campaign_reached_lv7: bool = false

var _campaign_vortex_enabled: bool = false
var _campaign_vortex_tangential_strength: float = 900.0
var _campaign_vortex_radial_strength: float = 420.0
var _campaign_vortex_max_radius: float = 2200.0

var _campaign_forced_map_texture: Texture2D = null
var _campaign_forced_music_stream: AudioStream = null

var _campaign_atmosphere_root: Node2D = null
var _campaign_sand_particles: GPUParticles2D = null
var _campaign_flow_lines: Line2D = null
var _campaign_flow_time: float = 0.0
var _campaign_prev_proximity: float = -1.0

# Campaign readability / pacing
@export var campaign_guidance_edge_margin_px: float = 56.0
@export var campaign_gold_overlay_max_alpha: float = 0.18
@export var campaign_extra_enemy_spawn_enabled: bool = true
@export var campaign_extra_enemy_min_interval: float = 0.65
@export var campaign_extra_enemy_max_interval: float = 3.0
@export var campaign_extra_enemy_min_proximity: float = 0.25
var _campaign_extra_enemy_accum: float = 0.0
var upgrade_speed_level: int = 0
var upgrade_magnet_level: int = 0

var _run_score_claimed: bool = false

var _skins_dialog: AcceptDialog = null
var _skins_option: OptionButton = null
var _skins_preview: TextureRect = null
var _skins_unlock_button: Button = null
var _skins_coin_unlock_button: Button = null

var _gacha_dialog: AcceptDialog = null
var _gacha_info_label: Label = null
var _gacha_result_label: RichTextLabel = null
var _gacha_single_button: Button = null
var _gacha_ten_button: Button = null

const GACHA_SCENE: PackedScene = preload("res://Scenes/GachaScene.tscn")
var _gacha_overlay: CanvasLayer = null
var _paused_by_gacha: bool = false

var _maps_dialog: AcceptDialog = null
var _maps_option: OptionButton = null
var _maps_preview: TextureRect = null
var _maps_name_label: Label = null
var _maps_swipe_active: bool = false
var _maps_swipe_start_x: float = 0.0
var _maps_swipe_last_x: float = 0.0
var _maps_use_game_button: Button = null
var _maps_use_menu_button: Button = null
var _maps_buy_button: Button = null

var _bgm_option: OptionButton = null
var meta_selected_bgm_id: String = "default"
var _bgm_stream_cache: Dictionary = {}

@onready var menu_background = get_node_or_null("%MenuBackground") as TextureRect
var _builtin_menu_bg_texture: Texture2D = null

var _upgrades_dialog: AcceptDialog = null
var _upgrade_labels: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _reset_upgrades_button: Button = null
var _reset_upgrades_confirm_dialog: ConfirmationDialog = null

var _skin_defs: Dictionary = {
	# NOTE: BlackHole visuals are screen-distortion; skins are expressed as an additive overlay + shader multipliers.
	"classic": {
		"name": "Classic",
		"texture": preload("res://Shaders/M.png"),
		"price": 0,
		"overlay_color": Color(1.0, 1.0, 1.0, 1.0),
		"overlay_alpha": 0.18,
		"overlay_spin": 55.0,
		"strength_mult": 1.0,
		"aberration_mult": 1.0,
		"fever_ring_color": Color(1.0, 0.86, 0.25, 1.0),
	},
	"vortex": {
		"name": "Vortex",
		"texture": preload("res://Shaders/M2.png"),
		"price": 800,
		"overlay_color": Color(0.35, 0.85, 1.0, 1.0),
		"overlay_alpha": 0.55,
		"overlay_spin": -170.0,
		"strength_mult": 1.25,
		"aberration_mult": 1.35,
		"fever_ring_color": Color(0.45, 0.9, 1.0, 1.0),
	},
	"neon": {
		"name": "Neon",
		"texture": preload("res://Shaders/M4.png"),
		"price": 1200,
		"overlay_color": Color(1.0, 0.25, 0.85, 1.0),
		"overlay_alpha": 0.62,
		"overlay_spin": 240.0,
		"strength_mult": 1.45,
		"aberration_mult": 1.65,
		"ripple_strength_mult": 1.25,
		"ripple_speed_mult": 1.2,
		"visual_tint": Color(1.0, 0.95, 1.0, 1.0),
		"fever_ring_color": Color(1.0, 0.25, 0.85, 1.0),
	},

	# SSR tier (for future gacha): extremely obvious, premium feel.
	"ssr_eclipse": {
		"name": "SSR: Eclipse",
		"texture": preload("res://Shaders/11.png"),
		"price": 999999,
		"gacha_only": true,
		"overlay_color": Color(0.65, 0.9, 1.0, 1.0),
		"overlay_alpha": 0.78,
		"overlay_spin": -420.0,
		"strength_mult": 1.85,
		"aberration_mult": 2.25,
		"ripple_strength_mult": 1.7,
		"ripple_speed_mult": 1.35,
		"visual_tint": Color(0.9, 1.0, 1.05, 1.0),
		"fever_ring_color": Color(0.55, 0.95, 1.0, 1.0),
	},
	"ssr_singularity": {
		"name": "SSR: Singularity",
		"texture": preload("res://Shaders/15.png"),
		"price": 999999,
		"gacha_only": true,
		"overlay_color": Color(1.0, 0.45, 0.18, 1.0),
		"overlay_alpha": 0.82,
		"overlay_spin": 520.0,
		"strength_mult": 2.05,
		"aberration_mult": 2.5,
		"ripple_strength_mult": 1.85,
		"ripple_speed_mult": 1.45,
		"visual_tint": Color(1.05, 0.95, 0.9, 1.0),
		"fever_ring_color": Color(1.0, 0.55, 0.18, 1.0),
	}
}

var _builtin_skin_defs: Dictionary = {}

var _map_defs: Dictionary = {
	"default": {"name": "Default", "texture": null, "price": 0, "music_path": ""}
}


func _get_skin_price(skin_id: String) -> int:
	var def: Dictionary = _skin_defs.get(skin_id, {}) as Dictionary
	if def.is_empty():
		return 999999
	return int(def.get("price", 999999))

var _emp_reward_dialog: AcceptDialog = null

@export var revive_stability_ratio: float = 0.6
var _revive_used: bool = false
var _revive_dialog: ConfirmationDialog = null
var _revive_prompt_open: bool = false

# 背景視差設定
@export var background_path: NodePath
@export var parallax_strength: float = 0.35 # 0 = 完全固定背景, 1 = 背景跟相機同步移動（通常用 0.15~0.6）
@onready var background_node = get_node_or_null(background_path)
var _prev_camera_pos: Vector2 = Vector2.ZERO
var _camera_origin: Vector2 = Vector2.ZERO
var _bg_origin: Vector2 = Vector2.ZERO
var _bg_tiles_parent: Node2D = null
var _bg_tile_size: Vector2 = Vector2.ZERO
@export var use_parallax_background: bool = false # 如果為 true，會用 ParallaxBackground 替代 3x3 磁磚池
var _bg_tiles: Array = []
var _parallax_bg: ParallaxBackground = null
var _bg_repeat_sprite: Sprite2D = null
var _bg_repeat_last_world_vp: Vector2 = Vector2.ZERO
@export var tile_pool_radius: int = 3 # 半徑 r → 會建立 (2r+1)^2 磁磚 (預設 3 -> 7x7)

# ----------------------------------------------------
# 資源與參數
# ----------------------------------------------------
@export var object_scene: PackedScene = null  
@export var enemy_scene: PackedScene = null   # 【請務必在編輯器中拖入你的敵人場景】

# 獵物生成密度
@export var prey_base_spawn_count: int = 2
@export var prey_max_spawn_count: int = 5

# 後期效能保護：場上物件上限（避免生成失控造成卡頓）
@export var max_prey_alive: int = 90
@export var max_enemies_alive: int = 22
@export var max_enemy_projectiles_alive: int = 90

# Preload the engine-imported FontFile resource to ensure it's included in exported builds
const IMPORTED_FONTDATA := preload("res://.godot/imported/NotoSansCJKtc-Regular.otf-9beee6b2e697d80eb91e284f740aefad.fontdata")

# 道具（磁鐵/沙漏）
@export var powerup_spawn_interval: float = 14.0
@export var magnet_duration: float = 10.0
@export var hourglass_duration: float = 15.0
@export var magnet_strength: float = 6500.0

# 遊戲狀態
var is_game_over: bool = false
const ENDLESS_TIME_LIMIT: float = 180.0
const CAMPAIGN_TIME_LIMIT: float = 150.0
var game_duration: float = ENDLESS_TIME_LIMIT
var time_left: float = 0.0
var wanted_level: int = 0
var current_score: int = 0

# 進入場景先顯示主選單；按「開始遊戲」才正式開始
var game_started: bool = false

# 【新增變數】用於追蹤 EMP 按鈕的閃爍動畫 (解決 Tween 錯誤的關鍵)
var emp_button_tween: Tween = null 

var _toast_tween: Tween = null
var _flash_tween: Tween = null

var _game_over_dialog: ConfirmationDialog = null
var _game_over_seq: int = 0

var _shake_time_left: float = 0.0
var _shake_strength: float = 0.0

var _hit_stop_seq: int = 0

# -----------------------------
# Object Pooling（手機效能）：EnemyProjectile
# -----------------------------
@export var enable_projectile_pooling: bool = true
@export var projectile_pool_prewarm: int = 40

# -----------------------------
# Meta：試用體驗 / 離線收益
# -----------------------------
@export var trial_skin_chance: float = 0.35
@export var idle_coin_rate_per_min: float = 3.0
@export var idle_coin_cap_minutes: int = 240
@export var idle_coin_daily_cap: int = 600
var _trial_skin_id: String = ""
var _pending_idle_reward_coins: int = 0

var _idle_rewards_dialog: AcceptDialog = null
var _idle_rewards_claim_button: Button = null

@export var bgm_pitch_min: float = 0.90
@export var bgm_pitch_drop_per_level: float = 0.004

# -----------------------------
# Fever Mode（連吞觸發）
# -----------------------------
@export var fever_combo_required: int = 10
@export var fever_combo_chain_window_sec: float = 2.2
@export var fever_music_pitch_multiplier: float = 1.18
@export var fever_music_max_pitch: float = 1.25

var _fever_combo_count: int = 0
var _fever_combo_last_sec: float = -9999.0
var _fever_time_left: float = 0.0
var _fever_duration: float = 8.0

# -----------------------------
# Swallow Combo（連吞得分倍率）
# -----------------------------
const COMBO_WINDOW: float = 1.5  # seconds between swallows to maintain combo
const COMBO_MULTIPLIERS: Array[float] = [1.0, 1.0, 1.5, 2.0, 3.0, 5.0]  # index = combo level (0-5)
var _combo_count: int = 0
var _combo_timer: float = 0.0
var _combo_label: Label = null
var _combo_tween: Tween = null

# -----------------------------
# 背景動態磁磚池/Parallax 支援函式
# -----------------------------
func _init_background() -> void:
	if not background_node:
		return

	# 清理舊背景實作（避免重複疊加）
	if _bg_repeat_sprite and is_instance_valid(_bg_repeat_sprite):
		_bg_repeat_sprite.queue_free()
		_bg_repeat_sprite = null
	if _parallax_bg and is_instance_valid(_parallax_bg):
		_parallax_bg.queue_free()
		_parallax_bg = null
	if _bg_tiles_parent and is_instance_valid(_bg_tiles_parent):
		_bg_tiles_parent.queue_free()
		_bg_tiles_parent = null
	_bg_tiles.clear()

	# 儲存背景初始 global 位置作為參考
	_bg_origin = background_node.global_position

	# 若背景為 Sprite2D，使用「可重複貼圖 + 大型 region」實作無限背景
	if background_node is Sprite2D and background_node.texture:
		var src_sprite := background_node as Sprite2D
		var tex_size = src_sprite.texture.get_size()
		var spr_scale = src_sprite.scale
		_bg_tile_size = Vector2(tex_size.x * spr_scale.x, tex_size.y * spr_scale.y)
		_setup_repeat_region_background(src_sprite)
		src_sprite.visible = false
		return

	# 後備：不是 Sprite2D 時，用複製平鋪
	if background_node is Node2D:
		_bg_tiles_parent = Node2D.new()
		add_child(_bg_tiles_parent)
		_bg_tiles_parent.global_position = _bg_origin
		var est_size = Vector2(1024, 1024)
		if background_node.has_node("Sprite2D"):
			var s = background_node.get_node("Sprite2D")
			if s is Sprite2D and s.texture:
				est_size = s.texture.get_size() * s.scale
		var grid = 8
		for ix in range(-grid, grid + 1):
			for iy in range(-grid, grid + 1):
				var tile = background_node.duplicate()
				_bg_tiles_parent.add_child(tile)
				tile.position = Vector2(ix * est_size.x, iy * est_size.y)
				_bg_tiles.append(tile)
		background_node.visible = false


func _setup_repeat_region_background(src_sprite: Sprite2D) -> void:
	# 建立一個會在巨大 region 內重複貼圖的 Sprite2D，確保畫面永遠被覆蓋
	if _bg_repeat_sprite and is_instance_valid(_bg_repeat_sprite):
		_bg_repeat_sprite.queue_free()
		_bg_repeat_sprite = null

	var spr := Sprite2D.new()
	spr.texture = src_sprite.texture
	spr.scale = src_sprite.scale
	spr.centered = true
	spr.z_as_relative = false
	spr.z_index = -1000
	# 讓 UV 可重複（避免超出貼圖範圍變透明）
	spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	spr.region_enabled = true
	# 重要：region_enabled=true 但 region_rect 預設是 0x0，主選單時不跑 _process 會導致背景整片消失。
	# 先依 viewport/zoom 設一個足夠大的 region，之後遊戲中會再動態擴大。
	var vp_size: Vector2 = get_viewport_rect().size
	var z: Vector2 = camera.zoom if camera else Vector2.ONE
	var world_vp := Vector2(vp_size.x / max(0.001, z.x), vp_size.y / max(0.001, z.y))
	# region_rect 是「貼圖像素空間」，會再乘上 spr.scale 變成世界尺寸；所以要除以 scale 才不會露底
	# 緩衝倍率：太大會讓 region_rect 極端巨大；太小則可能在高速移動/縮放時露底。
	# 因為背景會跟著相機移動，這裡用較保守的倍率即可。
	var buffer: float = 3.0
	var sx: float = max(0.001, absf(spr.scale.x))
	var sy: float = max(0.001, absf(spr.scale.y))
	var w: float = (world_vp.x * buffer) / sx
	var h: float = (world_vp.y * buffer) / sy
	# 硬上限：避免產生超大 region 導致渲染卡死
	var max_region: float = 50000.0
	w = minf(w, max_region)
	h = minf(h, max_region)
	spr.region_rect = Rect2(-w * 0.5, -h * 0.5, w, h)
	spr.global_position = _bg_origin
	add_child(spr)
	_bg_repeat_sprite = spr
	_bg_repeat_last_world_vp = Vector2.ZERO

func _setup_parallax_background(src_sprite: Sprite2D) -> void:
	# 建立一個 ParallaxBackground + 一個 ParallaxLayer，將 src_sprite 的 texture 放進去
	if _parallax_bg and is_instance_valid(_parallax_bg):
		_parallax_bg.queue_free()
		_parallax_bg = null
	var pb = ParallaxBackground.new()
	# 放在最底層
	pb.layer = -1000
	add_child(pb)
	_parallax_bg = pb
	pb.scroll_base_offset = Vector2.ZERO
	var layer = ParallaxLayer.new()
	layer.motion_scale = Vector2(parallax_strength, parallax_strength)

	# 啟用鏡像 (motion_mirroring) 以重複貼圖，避免露空（Godot 4 屬性名）
	var tex_size = src_sprite.texture.get_size()
	var spr_scale = src_sprite.scale
	layer.motion_mirroring = Vector2(tex_size.x * spr_scale.x, tex_size.y * spr_scale.y)

	pb.add_child(layer)
	var spr = Sprite2D.new()
	spr.texture = src_sprite.texture
	spr.scale = src_sprite.scale
	spr.centered = true
	spr.position = Vector2.ZERO
	# ParallaxBackground 在 Godot 4 是 CanvasLayer；不要用 global_* 來對齊
	layer.add_child(spr)

	# 隱藏原始節點
	src_sprite.visible = false

func _update_tile_pool(cam_pos: Vector2) -> void:
	# 將磁磚位置重新排到以攝影機為中心的格子上（可處理任意半徑）
	if _bg_tile_size.x <= 0 or _bg_tile_size.y <= 0: return

	# 根據當前 viewport 與攝影機縮放估算需要的半徑，若不足則重建池
	var vp_size = get_viewport_rect().size
	var cam_zoom = camera.zoom if camera else Vector2(1, 1)
	var world_vp = Vector2(vp_size.x / max(0.001, cam_zoom.x), vp_size.y / max(0.001, cam_zoom.y))
	var need_x = int(ceil(world_vp.x / max(1, _bg_tile_size.x))) + 4
	var need_y = int(ceil(world_vp.y / max(1, _bg_tile_size.y))) + 4
	var needed = max(need_x, need_y)
	var required_r = max(1, int(ceil(float(needed) / 2.0)))
	required_r = clamp(required_r, 1, 16)
	if required_r > tile_pool_radius:
		_rebuild_tile_pool(required_r)

	var r = max(1, tile_pool_radius)

	# 使用視差偏移來計算「期望的背景原點」
	var cam_offset = cam_pos - _camera_origin
	var par_offset = cam_offset * parallax_strength
	var desired_origin = _bg_origin - par_offset

	# 計算以期望原點為基準的格子起點，確保貼圖邊界對齊
	var base_x = floor((cam_pos.x - desired_origin.x) / _bg_tile_size.x) * _bg_tile_size.x + desired_origin.x
	var base_y = floor((cam_pos.y - desired_origin.y) / _bg_tile_size.y) * _bg_tile_size.y + desired_origin.y

	var idx = 0
	var total = _bg_tiles.size()
	for ix in range(-r, r + 1):
		for iy in range(-r, r + 1):
			if idx >= total:
				return # 所有磁磚已排完
			var tile = _bg_tiles[idx]
			var pos = Vector2(base_x + ix * _bg_tile_size.x, base_y + iy * _bg_tile_size.y)
			tile.global_position = pos
			idx += 1


func _rebuild_tile_pool(r: int) -> void:
	# 移除舊的磁磚並依新半徑重建池
	if not _bg_tiles_parent:
		_bg_tiles_parent = Node2D.new()
		add_child(_bg_tiles_parent)
		_bg_tiles_parent.global_position = _bg_origin

	# 清理舊節點
	for t in _bg_tiles:
		if is_instance_valid(t):
			t.queue_free()
	_bg_tiles.clear()

	# 建立新的磁磚池
	for ix in range(-r, r + 1):
		for iy in range(-r, r + 1):
			var tile = background_node.duplicate() if background_node else null
			if tile:
				_bg_tiles_parent.add_child(tile)
				# 放在原始背景附近，實際位置會在下一次更新時調整
				tile.global_position = _bg_origin + Vector2(ix * _bg_tile_size.x, iy * _bg_tile_size.y)
				_bg_tiles.append(tile)

	# 記錄新的半徑
	tile_pool_radius = r


# ----------------------------------------------------
# 初始化
# ----------------------------------------------------
func _ready():
	randomize()
	time_left = game_duration
	current_score = 0
	_load_meta()
	_apply_sfx_volume_db(sfx_volume_db)
	_grant_idle_rewards_if_any()

	_setup_emp_reward_dialog()
	_setup_revive_dialog()
	_setup_game_over_dialog()
	_setup_campaign_clear_dialog()
	_setup_music()
	_setup_settings_menu()
	_setup_meta_dialogs()

	# 初始化背景視差追蹤
	if camera:
		_prev_camera_pos = camera.global_position
		_camera_origin = camera.global_position
	if not background_node:
		# 嘗試自動尋找常見的背景節點 (例如 StarBackground)
		var found_bg = find_child("StarBackground", true, false)
		if found_bg:
			background_node = found_bg
			background_path = background_node.get_path()
			_bg_origin = background_node.global_position
			print("[Main.gd] 自動設定背景節點為: %s" % str(background_path))
			_init_background()
		else:
			print("[Main.gd] 背景節點未指定：請在 Inspector 設定 `background_path` 指向場景中的背景 Node2D。")
	else:
		_init_background()

	# If a game isn't running yet, ensure the main menu is entered/shown
	if not game_started:
		call_deferred("_enter_main_menu")
	_init_ui()
	_connect_signals()
	_ensure_enemy_combo_ui()
	_ensure_combo_ui()
	# 保險：避免按鈕被 UI 擋住或被設為忽略滑鼠
	if emp_button and emp_button is Control:
		emp_button.disabled = false
		emp_button.mouse_filter = Control.MOUSE_FILTER_STOP
		# 依規格：通緝等級 >= 2 才顯示
		emp_button.hide()
	# ScoreLabel 是 Label(Control)，保險起見不要攔截滑鼠事件
	if score_label and score_label is Control:
		score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# SpawnManager: owns timers, pools, spawn logic
	_spawn_mgr = SpawnManager.new()
	_spawn_mgr.name = "SpawnManager"
	add_child(_spawn_mgr)
	_spawn_mgr.setup(self, camera, %BlackHole, object_scene, enemy_scene, enable_projectile_pooling, projectile_pool_prewarm)

	# 主選單：一進入先停在選單
	_enter_main_menu()

	# 嘗試載入專案內的中文字型（若已放入 res://Fonts/）並將其應用到主要 UI 控件
	_ensure_project_font_applied()


func _ensure_project_font_applied() -> void:
	var font_path := "res://Fonts/NotoSansTC-Regular.otf"
	# 如果字型存在，載入該資源並覆蓋主要 UI 字體
	if FileAccess.file_exists(font_path):
		var font_res = load(font_path)
		if not font_res:
			print("Failed to load font resource at %s" % font_path)
			return
		# 遍歷整個場景樹並套用字型到常見 UI 控件（避免使用 lambda/嵌套函式）
		var stack: Array = [self]
		while stack.size() > 0:
			var node = stack.pop_back()
			if node is Label:
				node.add_theme_font_override("font", font_res)
			elif node is Button:
				node.add_theme_font_override("font", font_res)
			elif node is RichTextLabel:
				node.add_theme_font_override("normal_font", font_res)
			for c in node.get_children():
				if c is Node:
					stack.append(c)
		# 為了處理之後動態新增的 UI 節點，連接到根節點的 node_added 事件，
		# 只在遊戲執行階段連接（避免編輯器重複觸發）
		if not Engine.is_editor_hint():
			var root = get_tree().root
			if not root.is_connected("node_added", Callable(self, "_on_tree_node_added")):
				root.node_added.connect(Callable(self, "_on_tree_node_added"))
		_start_font_reapply()
		print("Applied project font to UI controls.")
	else:
		print("Project font not found at %s. To install, run tools/install_noto.gd in the Editor or place the TTF into res://Fonts/" % font_path)
		print("Attempting runtime fallback: scanning imported fontdata...")
		_force_apply_theme_fallback()




func _on_tree_node_added(node: Node) -> void:
	# 當場景樹新增 Control 類型的節點時，立即套用專案字型覆蓋（支援動態生成的 UI）
	if not node:
		return
	var font_path := "res://Fonts/NotoSansTC-Regular.otf"
	if not FileAccess.file_exists(font_path):
		return
	var font_res = load(font_path)
	if not font_res:
		return
	if node is Label:
		node.add_theme_font_override("font", font_res)
	elif node is Button:
		node.add_theme_font_override("font", font_res)
	elif node is RichTextLabel:
		node.add_theme_font_override("normal_font", font_res)


# --- 字型重試應用：在啟動後短時間內重複套用字型，捕捉延後建立的 UI ---
var _font_reapply_timer: Timer = null
var _font_reapply_attempts: int = 0
var _font_reapply_max_attempts: int = 6
var _font_reapply_interval: float = 0.5

func _start_font_reapply() -> void:
	if Engine.is_editor_hint():
		return
	if _font_reapply_timer and is_instance_valid(_font_reapply_timer):
		return
	_font_reapply_attempts = 0
	_font_reapply_timer = Timer.new()
	_font_reapply_timer.one_shot = false
	_font_reapply_timer.wait_time = _font_reapply_interval
	add_child(_font_reapply_timer)
	_font_reapply_timer.timeout.connect(Callable(self, "_on_font_reapply_timeout"))
	_font_reapply_timer.start()

func _on_font_reapply_timeout() -> void:
	_font_reapply_attempts += 1
	_apply_font_once()
	if _font_reapply_attempts >= _font_reapply_max_attempts:
		if _font_reapply_timer and is_instance_valid(_font_reapply_timer):
			_font_reapply_timer.stop()
			_font_reapply_timer.queue_free()
			_font_reapply_timer = null

func _apply_font_once() -> void:
	var font_res: Font = null
	if IMPORTED_FONTDATA:
		font_res = IMPORTED_FONTDATA
	else:
		var scanned := _locate_imported_fontdata()
		if scanned:
			font_res = scanned
		else:
			var font_path := "res://Fonts/NotoSansTC-Regular.otf"
			if FileAccess.file_exists(font_path):
				font_res = load(font_path)
	if not font_res:
		return
	var stack: Array = [self]
	while stack.size() > 0:
		var node = stack.pop_back()
		if node is Control:
			# 強制為大多數 Control 類型加入字型覆寫
			node.add_theme_font_override("font", font_res)
			# RichTextLabel 使用 normal_font
			if node is RichTextLabel:
				node.add_theme_font_override("normal_font", font_res)
		for c in node.get_children():
			if c is Node:
				stack.append(c)

func _force_apply_theme_fallback() -> void:
	# 建立一個簡單的 Theme，強制把字型套用到主要 Control 類型，作為匯出後的最後保險措施
	# Prefer the imported fontdata resource (fontdata) for exported builds
	var font_res: Font = null
	if IMPORTED_FONTDATA:
		font_res = IMPORTED_FONTDATA
	else:
		# 嘗試自動掃描 res://.godot/imported 以找到引擎匯入的 fontdata（有時匯出後路徑或名稱會不同）
		var scanned := _locate_imported_fontdata()
		if scanned:
			font_res = scanned
		else:
			var font_path := "res://Fonts/NotoSansTC-Regular.otf"
			if FileAccess.file_exists(font_path):
				font_res = load(font_path)
	if not font_res:
		return
	var theme := Theme.new()
	# 設定常見 Control 類型的預設字型
	var control_types := ["Label", "Button", "LineEdit", "TextEdit", "OptionButton", "CheckBox", "TabContainer", "PopupMenu", "SpinBox", "WindowDialog", "PopupPanel", "MenuButton"]
	for t in control_types:
		theme.set_font("font", t, font_res)
	# RichTextLabel 使用 normal_font
	theme.set_font("normal_font", "RichTextLabel", font_res)
	# 套用到場景樹根節點，讓 Control 繼承此 Theme
	var root = get_tree().root
	if root:
		# Apply to root (inheritance) and also force-assign to existing Controls
		root.theme = theme
		# 强制把 theme 指派給所有已存在的 Control 節點，並額外用 add_theme_font_override 強制覆寫
		var stack: Array = [root]
		while stack.size() > 0:
			var n = stack.pop_back()
			if n is Control:
				n.theme = theme
				# 補強：直接覆寫常見 font 屬性，避免某些控件忽略 Theme
				n.add_theme_font_override("font", font_res)
				if n is RichTextLabel:
					n.add_theme_font_override("normal_font", font_res)
			for ch in n.get_children():
				if ch is Node:
					stack.append(ch)
		print("Applied runtime Theme fallback with project font to root and all Controls.")


func _locate_imported_fontdata() -> Font:
	# 在 res://.godot/imported 中掃描 .fontdata 檔案，回傳第一個看起來像 NotoSans 的 Font 資源
	var dir = DirAccess.open("res://.godot/imported")
	if dir == null:
		return null
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var lower = fname.to_lower()
			if lower.ends_with(".fontdata") and (lower.find("notosans") != -1 or lower.find("noto") != -1):
				var fullpath = "res://.godot/imported/" + fname
				print("Found imported fontdata candidate:", fullpath)
				var res = ResourceLoader.load(fullpath)
				if res and res is Font:
					return res
		fname = dir.get_next()
	dir.list_dir_end()
	return null


func spawn_enemy_projectile(projectile_scene: PackedScene, pos: Vector2, vel: Vector2, spd: float, dmg: float, tex: Texture2D) -> void:
	if _spawn_mgr:
		_spawn_mgr.spawn_enemy_projectile(projectile_scene, pos, vel, spd, dmg, tex)


func recycle_enemy_projectile(p: Area2D) -> void:
	if _spawn_mgr:
		_spawn_mgr.recycle_enemy_projectile(p)


func _grant_idle_rewards_if_any() -> void:
	# 最小版離線收益：根據離線分鐘給金幣，上限 cap
	var cfg := ConfigFile.new()
	var err := cfg.load(_get_meta_save_path())
	if err != OK:
		return
	var last_seen: int = int(cfg.get_value("meta", "last_seen", 0))
	var now: int = int(Time.get_unix_time_from_system())
	if last_seen <= 0 or now <= last_seen:
		return
	@warning_ignore("integer_division")
	var minutes: int = (now - last_seen) / 60
	minutes = clampi(minutes, 0, idle_coin_cap_minutes)
	if minutes <= 0:
		return
	var mult: float = 1.0 + float(upgrade_gravity_level) * 0.05
	var reward: int = int(round(float(minutes) * idle_coin_rate_per_min * mult))
	if reward <= 0:
		return
	# 每日上限（簡化版）：可領取總額達到上限後不再累積
	var cap: int = maxi(0, idle_coin_daily_cap)
	if cap > 0:
		var remaining: int = maxi(0, cap - maxi(0, _pending_idle_reward_coins))
		reward = mini(reward, remaining)
	if reward <= 0:
		return
	_pending_idle_reward_coins += reward
	_save_meta()


func _setup_music() -> void:
	if _music_player and is_instance_valid(_music_player):
		return
	# 讓「地圖綁定音樂」在開局/進入主選單時就能生效
	_reload_map_defs_from_folder()
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = battle_music_volume_db
	_music_player.autoplay = false
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	# Auto-loop: replay when the stream finishes.
	if not _music_player.finished.is_connected(_on_music_finished):
		_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)
	_refresh_music_by_state()
	_update_meta_ui()


func _on_music_finished() -> void:
	# Replay the currently selected music when it reaches the end.
	if not _music_player or not is_instance_valid(_music_player):
		return
	if not _current_music_stream:
		return
	# Only loop if we are still on the same stream.
	if _music_player.stream != _current_music_stream:
		return
	_music_player.play()


func _play_music(stream: AudioStream) -> void:
	if not _music_player or not is_instance_valid(_music_player):
		return
	if _current_music_stream == stream:
		return
	_current_music_stream = stream
	if not stream:
		_music_player.stop()
		_music_player.stream = null
		return
	_music_player.stop()
	_music_player.stream = stream
	_music_player.play()


func _refresh_music_by_state() -> void:
	# 設定視窗顯示時：如果有指定 settings_music 就用它
	if _settings_dialog and _settings_dialog.visible and settings_music:
		_play_music(settings_music)
		return
	# Campaign is bound to its own music.
	if game_started and game_mode == GameMode.CAMPAIGN and _campaign_forced_music_stream:
		_play_music(_campaign_forced_music_stream)
		return
	# 主選單優先
	if not game_started:
		var base_stream: AudioStream = menu_music if menu_music else battle_music
		_play_music(_get_selected_bgm_stream(base_stream))
		return
	# 遊戲中
	_play_music(_get_selected_bgm_stream(battle_music))


func _setup_settings_menu() -> void:
	if _settings_dialog:
		return
	if not _settings_layer or not is_instance_valid(_settings_layer):
		_settings_layer = CanvasLayer.new()
		_settings_layer.name = "SettingsLayer"
		# Higher than FeedbackLayer (200) and FullScreenEffect (100)
		_settings_layer.layer = 1000
		add_child(_settings_layer)
	_settings_dialog = AcceptDialog.new()
	_settings_dialog.title = "設定"
	_settings_dialog.dialog_text = ""
	# Make it modal without relying on popup_exclusive_* APIs.
	_settings_dialog.exclusive = true
	# Settings must be interactive both in main menu (not paused) and in-game (paused).
	_settings_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	# 視窗質感：固定較大尺寸 + 不可調整大小
	_settings_dialog.unresizable = true
	_settings_dialog.min_size = Vector2i(620, 520)
	_settings_dialog.size = Vector2i(620, 520)
	_settings_dialog.ok_button_text = "關閉"
	# Put the dialog on a dedicated CanvasLayer so it can't be covered by overlays.
	_settings_layer.add_child(_settings_dialog)
	if not _settings_dialog.visibility_changed.is_connected(_on_settings_visibility_changed):
		_settings_dialog.visibility_changed.connect(_on_settings_visibility_changed)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_settings_dialog.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	_settings_root_vbox = root

	var title := Label.new()
	title.text = "音樂音量"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)

	var slider := HSlider.new()
	slider.min_value = -30.0
	slider.max_value = 0.0
	slider.step = 0.5
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_music_slider = slider
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(92, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 20)
	_music_value_label = value_label
	row.add_child(value_label)

	# 初始值：以目前播放的 volume_db 為準
	var initial_db := battle_music_volume_db
	if _music_player and is_instance_valid(_music_player):
		initial_db = _music_player.volume_db
	slider.value = initial_db
	slider.value_changed.connect(_on_music_volume_changed)
	_update_music_value_label(initial_db)

	# 背景音樂選擇（解鎖地圖可解鎖音樂：res://Maps/<map>.(ogg/mp3/wav)）
	var bgm_title := Label.new()
	bgm_title.text = "背景音樂"
	bgm_title.add_theme_font_size_override("font_size", 22)
	root.add_child(bgm_title)

	var bgm_opt := OptionButton.new()
	bgm_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bgm_option = bgm_opt
	root.add_child(bgm_opt)
	if not bgm_opt.item_selected.is_connected(_on_bgm_selected):
		bgm_opt.item_selected.connect(_on_bgm_selected)
	_refresh_bgm_options()

	# 音效音量
	var sep_audio := HSeparator.new()
	root.add_child(sep_audio)

	var sfx_title := Label.new()
	sfx_title.text = "音效音量"
	sfx_title.add_theme_font_size_override("font_size", 26)
	root.add_child(sfx_title)

	var sfx_row := HBoxContainer.new()
	sfx_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_row.add_theme_constant_override("separation", 12)
	root.add_child(sfx_row)

	var sfx_slider := HSlider.new()
	sfx_slider.min_value = -30.0
	sfx_slider.max_value = 0.0
	sfx_slider.step = 0.5
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sfx_slider = sfx_slider
	sfx_row.add_child(sfx_slider)

	var sfx_value_label := Label.new()
	sfx_value_label.custom_minimum_size = Vector2(92, 0)
	sfx_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sfx_value_label.add_theme_font_size_override("font_size", 20)
	_sfx_value_label = sfx_value_label
	sfx_row.add_child(sfx_value_label)

	var initial_sfx_db := sfx_volume_db
	if sfx_level_up and is_instance_valid(sfx_level_up):
		initial_sfx_db = sfx_level_up.volume_db
	sfx_slider.value = initial_sfx_db
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_update_sfx_value_label(initial_sfx_db)

	# 引力漣漪開關
	var ripple_toggle := CheckBox.new()
	ripple_toggle.text = "關閉引力漣漪"
	ripple_toggle.button_pressed = not gravity_ripple_enabled
	ripple_toggle.add_theme_font_size_override("font_size", 20)
	_ripple_checkbox = ripple_toggle
	root.add_child(ripple_toggle)
	ripple_toggle.toggled.connect(_on_ripple_toggle_changed)

	# 動態 BGM 變速功能已停用（暫時不顯示開關）

	# 放棄本局並回主選單
	var sep := HSeparator.new()
	root.add_child(sep)

	var abandon_btn := Button.new()
	abandon_btn.text = "回主選單（放棄本局）"
	abandon_btn.add_theme_font_size_override("font_size", 22)
	abandon_btn.disabled = not game_started
	_abandon_button = abandon_btn
	root.add_child(abandon_btn)
	abandon_btn.pressed.connect(_on_abandon_pressed)

	# ── 每日任務區塊 ──
	var mission_sep := HSeparator.new()
	root.add_child(mission_sep)
	var mission_title := Label.new()
	mission_title.text = "📋 每日任務"
	mission_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_title.add_theme_font_size_override("font_size", 22)
	mission_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	root.add_child(mission_title)
	_settings_mission_container = VBoxContainer.new()
	_settings_mission_container.add_theme_constant_override("separation", 4)
	root.add_child(_settings_mission_container)

	var btn = settings_button
	if not btn:
		btn = find_child("SettingsButton", true, false)
	if btn and btn is BaseButton:
		if not (btn as BaseButton).pressed.is_connected(_on_settings_pressed):
			(btn as BaseButton).pressed.connect(_on_settings_pressed)

	# 主選單也要能開啟音量設定
	var menu_btn: Button = menu_settings_button
	if not menu_btn:
		menu_btn = find_child("MenuSettingsButton", true, false) as Button
	if menu_btn and not menu_btn.pressed.is_connected(_on_settings_pressed):
		menu_btn.pressed.connect(_on_settings_pressed)


func _setup_meta_dialogs() -> void:
	_setup_skins_dialog()
	_setup_upgrades_dialog()
	_setup_maps_dialog()
	_setup_campaign_levels_dialog()
	_setup_idle_rewards_dialog()
	# 保險：按鈕可能被使用者改名/移位，用 unique 或 find_child
	if not skins_button:
		skins_button = find_child("SkinsButton", true, false) as Button
	if skins_button and not skins_button.pressed.is_connected(_on_skins_pressed):
		skins_button.pressed.connect(_on_skins_pressed)
	if not gacha_button:
		gacha_button = find_child("GachaButton", true, false) as Button
	if gacha_button and not gacha_button.pressed.is_connected(_on_gacha_pressed):
		gacha_button.pressed.connect(_on_gacha_pressed)
	if not upgrades_button:
		upgrades_button = find_child("UpgradesButton", true, false) as Button
	if upgrades_button and not upgrades_button.pressed.is_connected(_on_upgrades_pressed):
		upgrades_button.pressed.connect(_on_upgrades_pressed)
	if not idle_rewards_button:
		idle_rewards_button = find_child("IdleRewardsButton", true, false) as Button
	if idle_rewards_button and not idle_rewards_button.pressed.is_connected(_on_idle_rewards_pressed):
		idle_rewards_button.pressed.connect(_on_idle_rewards_pressed)


func _setup_idle_rewards_dialog() -> void:
	if _idle_rewards_dialog:
		return
	_idle_rewards_dialog = AcceptDialog.new()
	_idle_rewards_dialog.title = "⭐ 銀河銀行 ⭐"
	_idle_rewards_dialog.dialog_text = ""
	_idle_rewards_dialog.unresizable = true
	_idle_rewards_dialog.min_size = Vector2i(640, 320)
	_idle_rewards_dialog.size = Vector2i(640, 320)
	_idle_rewards_dialog.ok_button_text = "關閉"
	_idle_rewards_claim_button = _idle_rewards_dialog.add_button("✨ 領取 ✨", false, "CLAIM") as Button
	add_child(_idle_rewards_dialog)
	if not _idle_rewards_dialog.custom_action.is_connected(_on_idle_rewards_dialog_action):
		_idle_rewards_dialog.custom_action.connect(_on_idle_rewards_dialog_action)


func _on_idle_rewards_pressed() -> void:
	if not _idle_rewards_dialog:
		_setup_idle_rewards_dialog()
	_update_idle_rewards_dialog_text()
	_idle_rewards_dialog.popup_centered()


func _update_idle_rewards_dialog_text() -> void:
	if not _idle_rewards_dialog:
		return
	var pending: int = maxi(0, _pending_idle_reward_coins)
	var cap: int = maxi(0, idle_coin_daily_cap)
	var cap_note := "📦 每日離線收益上限：%d" % cap
	var pending_note := "💰 目前可領取：%d 金幣" % pending
	var hint := "（每天回來領取，讓黑洞持續進化！）"
	_idle_rewards_dialog.dialog_text = "\n%s\n\n%s\n\n%s" % [pending_note, cap_note, hint]
	if _idle_rewards_claim_button and is_instance_valid(_idle_rewards_claim_button):
		_idle_rewards_claim_button.disabled = (pending <= 0)


func _on_idle_rewards_dialog_action(action: StringName) -> void:
	if String(action) != "CLAIM":
		return
	var pending: int = maxi(0, _pending_idle_reward_coins)
	if pending <= 0:
		_show_toast("目前沒有可領取的離線收益", Color(1, 1, 1))
		_update_idle_rewards_dialog_text()
		return
	meta_coins += pending
	_pending_idle_reward_coins = 0
	_save_meta()
	_update_meta_ui()
	# 金幣飛入動畫
	_play_coin_fly_animation(mini(pending, 10))
	_show_toast("已領取離線收益 +%d 金幣" % pending, Color(0.2, 1, 1))
	_update_idle_rewards_dialog_text()


func _play_coin_fly_animation(count: int) -> void:
	# 產生金幣飛向畫面中心的粒子動畫
	var vp_size := get_viewport().get_visible_rect().size
	var target_pos := Vector2(vp_size.x * 0.5, vp_size.y * 0.12)  # 金幣 UI 位置
	for i in range(count):
		var coin_label := Label.new()
		coin_label.text = "⭐"
		coin_label.add_theme_font_size_override("font_size", 36)
		coin_label.z_index = 200
		# 從螢幕隨機位置出發
		var start_x := randf_range(vp_size.x * 0.2, vp_size.x * 0.8)
		var start_y := randf_range(vp_size.y * 0.4, vp_size.y * 0.7)
		coin_label.position = Vector2(start_x, start_y)
		coin_label.modulate = Color(1.0, 0.85, 0.2, 1.0)
		coin_label.scale = Vector2(1.5, 1.5)
		add_child(coin_label)
		var tw := create_tween()
		tw.set_parallel(true)
		var delay := i * 0.07
		tw.tween_property(coin_label, "position", target_pos, 0.55 + delay).set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(coin_label, "scale", Vector2(0.3, 0.3), 0.55 + delay).set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(coin_label, "modulate:a", 0.0, 0.15).set_delay(0.45 + delay)
		tw.chain().tween_callback(coin_label.queue_free)


func _load_meta() -> void:
	# Delegate to MetaManager autoload, then sync local vars
	if has_node("/root/MetaManager"):
		var mm = get_node("/root/MetaManager")
		mm.load_meta()
		_sync_from_meta_manager()
	else:
		_load_meta_legacy()

func _sync_from_meta_manager() -> void:
	var mm = get_node("/root/MetaManager")
	meta_coins = mm.coins
	_pending_idle_reward_coins = mm.pending_idle_reward_coins
	meta_selected_skin = mm.selected_skin
	meta_unlocked_skins = mm.unlocked_skins
	meta_selected_map = mm.selected_map
	meta_selected_menu_map = mm.selected_menu_map
	meta_unlocked_maps = mm.unlocked_maps
	upgrade_gravity_level = mm.upgrade_gravity_level
	upgrade_speed_level = mm.upgrade_speed_level
	upgrade_magnet_level = mm.upgrade_magnet_level
	enable_dynamic_bgm_pitch = mm.dynamic_bgm_pitch
	meta_selected_bgm_id = mm.selected_bgm_id
	battle_music_volume_db = mm.music_volume_db
	sfx_volume_db = mm.sfx_volume_db
	meta_campaign_cleared = mm.campaign_cleared
	meta_campaign_max_unlocked = mm.campaign_max_unlocked
	_apply_meta_to_session()

func _sync_to_meta_manager() -> void:
	var mm = get_node("/root/MetaManager")
	mm.coins = meta_coins
	mm.pending_idle_reward_coins = _pending_idle_reward_coins
	mm.selected_skin = meta_selected_skin
	mm.unlocked_skins = meta_unlocked_skins
	mm.selected_map = meta_selected_map
	mm.selected_menu_map = meta_selected_menu_map
	mm.unlocked_maps = meta_unlocked_maps
	mm.upgrade_gravity_level = upgrade_gravity_level
	mm.upgrade_speed_level = upgrade_speed_level
	mm.upgrade_magnet_level = upgrade_magnet_level
	mm.dynamic_bgm_pitch = enable_dynamic_bgm_pitch
	mm.selected_bgm_id = meta_selected_bgm_id
	mm.music_volume_db = battle_music_volume_db
	mm.sfx_volume_db = sfx_volume_db
	mm.campaign_cleared = meta_campaign_cleared
	mm.campaign_max_unlocked = meta_campaign_max_unlocked

func _load_meta_legacy() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(_get_meta_save_path())
	if err == OK:
		meta_coins = int(cfg.get_value("meta", "coins", 0))
		_pending_idle_reward_coins = int(cfg.get_value("meta", "pending_idle_reward_coins", 0))
		meta_selected_skin = String(cfg.get_value("skins", "selected", "classic"))
		var unlocked: Variant = cfg.get_value("skins", "unlocked", {"classic": true})
		if typeof(unlocked) == TYPE_DICTIONARY:
			meta_unlocked_skins = unlocked as Dictionary
		else:
			meta_unlocked_skins = {"classic": true}

		meta_selected_map = String(cfg.get_value("maps", "selected", "default"))
		meta_selected_menu_map = String(cfg.get_value("maps", "menu_selected", "default"))
		var unlocked_maps_v: Variant = cfg.get_value("maps", "unlocked", {"default": true})
		if typeof(unlocked_maps_v) == TYPE_DICTIONARY:
			meta_unlocked_maps = unlocked_maps_v as Dictionary
		else:
			meta_unlocked_maps = {"default": true}
		upgrade_gravity_level = int(cfg.get_value("upgrades", "gravity", 0))
		upgrade_speed_level = int(cfg.get_value("upgrades", "speed", 0))
		upgrade_magnet_level = int(cfg.get_value("upgrades", "magnet", 0))
		# 讀取使用者設定：是否啟用動態 BGM 變速
		enable_dynamic_bgm_pitch = bool(cfg.get_value("settings", "dynamic_bgm_pitch", enable_dynamic_bgm_pitch))
		meta_selected_bgm_id = String(cfg.get_value("settings", "bgm_id", meta_selected_bgm_id))
		battle_music_volume_db = float(cfg.get_value("settings", "music_volume_db", battle_music_volume_db))
		sfx_volume_db = float(cfg.get_value("settings", "sfx_volume_db", sfx_volume_db))
		meta_campaign_cleared = bool(cfg.get_value("campaign", "cleared", false))
		meta_campaign_max_unlocked = int(cfg.get_value("campaign", "max_unlocked", 1))
		if has_node("/root/GachaManager"):
			var gm = get_node("/root/GachaManager")
			gm.load_from_config(cfg)
	else:
		meta_coins = 0
		_pending_idle_reward_coins = 0
		meta_selected_skin = "classic"
		meta_unlocked_skins = {"classic": true}
		meta_selected_map = "default"
		meta_selected_menu_map = "default"
		meta_unlocked_maps = {"default": true}
		upgrade_gravity_level = 0
		upgrade_speed_level = 0
		upgrade_magnet_level = 0
		# 若沒有 meta 檔，保留 enable_dynamic_bgm_pitch 的預設（export 值）
		meta_selected_bgm_id = "default"
		meta_campaign_cleared = false
		meta_campaign_max_unlocked = 1
		if has_node("/root/GachaManager"):
			var gm2 = get_node("/root/GachaManager")
			gm2.load_from_config(cfg)

	meta_campaign_max_unlocked = clampi(meta_campaign_max_unlocked, 1, CAMPAIGN_LEVEL_COUNT)

	# 防呆：選到未解鎖皮膚 -> 回到 classic
	if not meta_unlocked_skins.has(meta_selected_skin) or not bool(meta_unlocked_skins[meta_selected_skin]):
		meta_selected_skin = "classic"
	# 防呆：選到未解鎖地圖 -> 回到 default
	if not meta_unlocked_maps.has(meta_selected_map) or not bool(meta_unlocked_maps[meta_selected_map]):
		meta_selected_map = "default"
	if not meta_unlocked_maps.has(meta_selected_menu_map) or not bool(meta_unlocked_maps[meta_selected_menu_map]):
		meta_selected_menu_map = "default"
	# 防呆：選到未解鎖/不存在音樂 -> 回到預設
	if meta_selected_bgm_id != "default" and meta_selected_bgm_id.begins_with("map:"):
		var map_id := meta_selected_bgm_id.substr(4)
		if not (meta_unlocked_maps.has(map_id) and bool(meta_unlocked_maps[map_id])):
			meta_selected_bgm_id = "default"
	_apply_meta_to_session()


func _save_meta() -> void:
	# Sync local vars to MetaManager, then delegate save
	if has_node("/root/MetaManager"):
		_sync_to_meta_manager()
		var mm = get_node("/root/MetaManager")
		mm.save_meta()
		return
	# Legacy fallback
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "coins", meta_coins)
	cfg.set_value("meta", "pending_idle_reward_coins", _pending_idle_reward_coins)
	cfg.set_value("meta", "last_seen", int(Time.get_unix_time_from_system()))
	cfg.set_value("skins", "selected", meta_selected_skin)
	cfg.set_value("skins", "unlocked", meta_unlocked_skins)
	cfg.set_value("maps", "selected", meta_selected_map)
	cfg.set_value("maps", "menu_selected", meta_selected_menu_map)
	cfg.set_value("maps", "unlocked", meta_unlocked_maps)
	cfg.set_value("upgrades", "gravity", upgrade_gravity_level)
	cfg.set_value("upgrades", "speed", upgrade_speed_level)
	cfg.set_value("upgrades", "magnet", upgrade_magnet_level)
	cfg.set_value("settings", "dynamic_bgm_pitch", enable_dynamic_bgm_pitch)
	cfg.set_value("settings", "bgm_id", meta_selected_bgm_id)
	cfg.set_value("settings", "music_volume_db", battle_music_volume_db)
	cfg.set_value("settings", "sfx_volume_db", sfx_volume_db)
	cfg.set_value("campaign", "cleared", meta_campaign_cleared)
	cfg.set_value("campaign", "max_unlocked", meta_campaign_max_unlocked)
	if has_node("/root/GachaManager"):
		var gm3 = get_node("/root/GachaManager")
		gm3.save_to_config(cfg)
	cfg.save(_get_meta_save_path())


func _setup_gacha_dialog() -> void:
	if _gacha_dialog:
		return
	_gacha_dialog = AcceptDialog.new()
	_gacha_dialog.title = "抽獎"
	_gacha_dialog.dialog_text = ""
	_gacha_dialog.unresizable = true
	_gacha_dialog.min_size = Vector2i(720, 420)
	_gacha_dialog.size = Vector2i(720, 420)
	_gacha_dialog.ok_button_text = "關閉"
	add_child(_gacha_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_gacha_dialog.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var info := Label.new()
	info.add_theme_font_size_override("font_size", 20)
	info.text = ""
	_gacha_info_label = info
	root.add_child(info)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	root.add_child(btn_row)

	var single_btn := Button.new()
	single_btn.text = "單抽"
	btn_row.add_child(single_btn)
	_gacha_single_button = single_btn
	single_btn.pressed.connect(func():
		_on_gacha_roll_pressed(1)
	)

	var ten_btn := Button.new()
	ten_btn.text = "十連"
	btn_row.add_child(ten_btn)
	_gacha_ten_button = ten_btn
	ten_btn.pressed.connect(func():
		_on_gacha_roll_pressed(10)
	)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(0.9, 0.9, 0.9)
	hint.text = "抽到的 Skin 會自動解鎖，可至 Skins 套用。重複獲得會轉換為金幣。"
	root.add_child(hint)

	var res := RichTextLabel.new()
	res.fit_content = true
	res.scroll_active = true
	res.size_flags_vertical = Control.SIZE_EXPAND_FILL
	res.custom_minimum_size = Vector2(0, 220)
	_gacha_result_label = res
	root.add_child(res)

	_update_gacha_ui()


func _on_gacha_pressed() -> void:
	_open_gacha_scene()


func _open_gacha_scene() -> void:
	if _gacha_overlay and is_instance_valid(_gacha_overlay):
		return
	_reload_skin_defs_from_folder()
	var overlay := GACHA_SCENE.instantiate() as CanvasLayer
	_gacha_overlay = overlay
	add_child(overlay)
	if overlay.has_signal("closed"):
		overlay.connect("closed", _on_gacha_scene_closed)
	# Pause gameplay while the animation runs (if in-game).
	if game_started and not is_game_over and not get_tree().paused:
		get_tree().paused = true
		_paused_by_gacha = true
	# Initialize.
	if overlay.has_method("setup"):
		overlay.call("setup", self, _skin_defs)


func _on_gacha_scene_closed() -> void:
	if _paused_by_gacha:
		get_tree().paused = false
		_paused_by_gacha = false
	_gacha_overlay = null
	# Refresh meta UI in case coins/unlocks changed.
	_update_meta_ui()
	_refresh_skins_ui()


func get_meta_coins() -> int:
	return meta_coins


func do_gacha_roll(count: int) -> Dictionary:
	# Called by GachaScene overlay.
	if not has_node("/root/GachaManager"):
		return {"ok": false, "error": "GachaManager missing"}
	var gm = get_node("/root/GachaManager")
	var cost := int(gm.single_cost_coins if count == 1 else gm.ten_cost_coins)
	if meta_coins < cost:
		_show_toast("金幣不足", Color.ORANGE)
		return {"ok": false, "error": "not_enough_coins"}

	meta_coins -= cost
	var pack: Dictionary = gm.roll(count, meta_unlocked_skins)
	var new_unlocks: Array = pack.get("new_unlocks", []) as Array
	var total_refund: int = int(pack.get("total_refund_coins", 0))
	for skin_id_v in new_unlocks:
		var skin_id := String(skin_id_v)
		meta_unlocked_skins[skin_id] = true
	if total_refund > 0:
		meta_coins += total_refund

	_save_meta()
	_update_meta_ui()
	_refresh_skins_ui()

	return {"ok": true, "pack": pack}


func _update_gacha_ui() -> void:
	if not _gacha_dialog:
		return
	var pity := 0
	var total := 0
	var single_cost := 500
	var ten_cost := 4500
	var rate_note := ""
	if has_node("/root/GachaManager"):
		var gm = get_node("/root/GachaManager")
		pity = int(gm.get_ssr_pity_counter())
		total = int(gm.get_total_rolls())
		single_cost = int(gm.single_cost_coins)
		ten_cost = int(gm.ten_cost_coins)
		var rates: Dictionary = gm.get_rarity_rate_map()
		if not rates.is_empty():
			var r_rate := float(rates.get("R", 0.0))
			var ssr_rate := float(rates.get("SSR", 0.0))
			rate_note = "   機率：R %.1f%% / SSR %.1f%%" % [r_rate * 100.0, ssr_rate * 100.0]
	if _gacha_info_label:
		var pity_max := 30
		if has_node("/root/GachaManager"):
			var gm4 = get_node("/root/GachaManager")
			pity_max = int(gm4.ssr_pity_max)
		_gacha_info_label.text = "金幣：%d   SSR 保底累計：%d/%d   總抽數：%d%s" % [meta_coins, pity, max(1, pity_max), total, rate_note]
	if _gacha_single_button:
		_gacha_single_button.text = "單抽（%d 金幣）" % single_cost
		_gacha_single_button.disabled = meta_coins < single_cost
	if _gacha_ten_button:
		_gacha_ten_button.text = "十連（%d 金幣）" % ten_cost
		_gacha_ten_button.disabled = meta_coins < ten_cost


func _on_gacha_roll_pressed(count: int) -> void:
	if not has_node("/root/GachaManager"):
		_show_toast("GachaManager 未啟用", Color.ORANGE)
		return
	var gm = get_node("/root/GachaManager")
	var cost := int(gm.single_cost_coins if count == 1 else gm.ten_cost_coins)
	if meta_coins < cost:
		_show_toast("金幣不足", Color.ORANGE)
		return

	meta_coins -= cost
	var pack: Dictionary = gm.roll(count, meta_unlocked_skins)
	var new_unlocks: Array = pack.get("new_unlocks", []) as Array
	var total_refund: int = int(pack.get("total_refund_coins", 0))

	for skin_id_v in new_unlocks:
		var skin_id := String(skin_id_v)
		meta_unlocked_skins[skin_id] = true

	if total_refund > 0:
		meta_coins += total_refund

	_save_meta()
	_update_meta_ui()
	_refresh_skins_ui()

	_render_gacha_results(pack)
	_update_gacha_ui()


func _render_gacha_results(pack: Dictionary) -> void:
	if not _gacha_result_label:
		return
	_gacha_result_label.clear()
	var results: Array = pack.get("results", []) as Array
	var new_unlocks: Array = pack.get("new_unlocks", []) as Array
	var refund: int = int(pack.get("total_refund_coins", 0))

	_gacha_result_label.append_text("本次結果：\n")
	for r_v in results:
		var r := r_v as Dictionary
		var skin_id := String(r.get("skin_id", ""))
		var rarity := String(r.get("rarity", "R"))
		var is_dup := bool(r.get("is_duplicate", false))
		var def: Dictionary = _skin_defs.get(skin_id, {}) as Dictionary
		var nm := String(def.get("name", skin_id))
		var tag := "[SSR]" if rarity == "SSR" else "[R]"
		var suffix := "（重複）" if is_dup else "（NEW）"
		_gacha_result_label.append_text("- %s %s %s\n" % [tag, nm, suffix])

	if refund > 0:
		_gacha_result_label.append_text("\n重複轉換：+%d 金幣\n" % refund)
	if new_unlocks.size() > 0:
		_gacha_result_label.append_text("\n已解鎖 %d 個 Skin：可至 Skins 套用\n" % new_unlocks.size())



func _update_meta_ui() -> void:
	if not coins_label:
		coins_label = find_child("CoinsLabel", true, false) as Label
	if coins_label:
		coins_label.text = "金幣：%d" % meta_coins


func _apply_meta_to_session() -> void:
	# MenuBackground 預設沿用場景設定（避免 default 時被清空）
	if menu_background and _builtin_menu_bg_texture == null:
		if menu_background.texture:
			_builtin_menu_bg_texture = menu_background.texture
		elif background_node and (background_node is Sprite2D):
			_builtin_menu_bg_texture = (background_node as Sprite2D).texture
		# 確保滿版不變形
		menu_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		menu_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	# 皮膚：主選單/遊戲都套用
	_reload_skin_defs_from_folder()
	_apply_selected_skin()
	# 地圖：主選單/遊戲都套用
	_reload_map_defs_from_folder()
	_apply_selected_map()
	_apply_selected_menu_map()
	# 升級：會在每局開始時再套一次（確保對局中變更也生效）
	_apply_upgrades_to_runtime()
	_update_meta_ui()
	_refresh_skins_ui()
	_refresh_upgrades_ui()
	_refresh_maps_ui()

	# UI/Styling: 微調右上資訊的風格（提高可讀性）
	if level_label:
		level_label.modulate = Color(1.0, 0.95, 0.82)
		# 若有字體大小屬性可用，主要由場景設定控制
	if score_label:
		score_label.modulate = Color(0.95, 1.0, 0.95)

	# 初始化 music pitch toggle 狀態（若 UI 已建立，_connect_signals 也會再同步）
	if music_pitch_toggle and music_pitch_toggle is CheckBox:
		music_pitch_toggle.set_pressed(enable_dynamic_bgm_pitch)

	# （MenuBackground 的預設貼圖已在本函式一開始快照）


func _reload_skin_defs_from_folder() -> void:
	# 保留內建 skins（避免你沒放檔案也能用）
	if _builtin_skin_defs.is_empty():
		_builtin_skin_defs = _skin_defs.duplicate(true)
	_skin_defs = _builtin_skin_defs.duplicate(true)

	var dir := DirAccess.open("res://Skins")
	if not dir:
		return
	dir.list_dir_begin()
	while true:
		var fn := dir.get_next()
		if fn == "":
			break
		if dir.current_is_dir():
			continue
		var lower := fn.to_lower()
		if not (lower.ends_with(".png") or lower.ends_with(".webp") or lower.ends_with(".jpg") or lower.ends_with(".jpeg")):
			continue
		var id := lower.get_basename()
		# 避免覆蓋內建 id
		if _skin_defs.has(id):
			continue
		var tex: Texture2D = load("res://Skins/%s" % fn) as Texture2D
		if not tex:
			continue
		# Default profile for custom skins (texture + readable glow).
		_skin_defs[id] = {
			"name": id,
			"texture": tex,
			"price": 800,
			"overlay_color": Color(0.9, 0.9, 0.9, 1.0),
			"overlay_alpha": 0.5,
			"overlay_spin": 120.0,
			"strength_mult": 1.15,
			"aberration_mult": 1.25,
			"fever_ring_color": Color(1.0, 0.92, 0.35, 1.0),
		}
	dir.list_dir_end()


func _reload_map_defs_from_folder() -> void:
	# 基礎地圖
	_map_defs = {"default": {"name": "Default", "texture": null, "price": 0, "music_path": ""}}

	var dir := DirAccess.open("res://Maps")
	if not dir:
		return
	dir.list_dir_begin()
	while true:
		var fn := dir.get_next()
		if fn == "":
			break
		if dir.current_is_dir():
			continue
		var lower := fn.to_lower()
		if not (lower.ends_with(".png") or lower.ends_with(".webp") or lower.ends_with(".jpg") or lower.ends_with(".jpeg")):
			continue
		var id := lower.get_basename()
		# 避免與 default 衝突
		if id == "default":
			continue
		# Campaign reward map: only appears after clearing campaign.
		if id == CAMPAIGN_MAP_ID and not meta_campaign_cleared:
			continue
		var tex: Texture2D = load("res://Maps/%s" % fn) as Texture2D
		if not tex:
			continue
		# 可選：同檔名音樂（res://Maps/<basename>.(ogg/mp3/wav)）
		var music_path := ""
		var base := fn.get_basename()
		for ext in [".ogg", ".mp3", ".wav"]:
			var candidate := "res://Maps/%s%s" % [base, ext]
			if ResourceLoader.exists(candidate):
				music_path = candidate
				break
		# 價格先用固定值，之後你要做 per-map 定價再擴充即可
		_map_defs[id] = {"name": id, "texture": tex, "price": 800, "music_path": music_path}
	dir.list_dir_end()
	_bgm_stream_cache.clear()


func _refresh_bgm_options() -> void:
	if not _bgm_option or not is_instance_valid(_bgm_option):
		return
	# 確保最新 map defs（含 music_path）
	_reload_map_defs_from_folder()
	_bgm_option.clear()
	_bgm_option.add_item("預設")
	_bgm_option.set_item_metadata(0, "default")
	var selected_idx := 0
	var idx := 1
	for map_id in _map_defs.keys():
		if map_id == "default":
			continue
		if not (meta_unlocked_maps.has(map_id) and bool(meta_unlocked_maps[map_id])):
			continue
		var def: Dictionary = _map_defs.get(map_id, {}) as Dictionary
		var music_path: String = String(def.get("music_path", ""))
		if music_path == "":
			continue
		var nm: String = String(def.get("name", map_id))
		_bgm_option.add_item(nm)
		var music_id := "map:%s" % map_id
		_bgm_option.set_item_metadata(idx, music_id)
		if meta_selected_bgm_id == music_id:
			selected_idx = idx
		idx += 1
	_bgm_option.select(selected_idx)
	# 防呆：選到不存在的音樂 -> 回到預設
	meta_selected_bgm_id = String(_bgm_option.get_item_metadata(_bgm_option.selected))


func _get_selected_bgm_stream(fallback_stream: AudioStream) -> AudioStream:
	if meta_selected_bgm_id == "" or meta_selected_bgm_id == "default":
		return fallback_stream
	if not meta_selected_bgm_id.begins_with("map:"):
		return fallback_stream
	var map_id := meta_selected_bgm_id.substr(4)
	var def: Dictionary = _map_defs.get(map_id, {}) as Dictionary
	var music_path: String = String(def.get("music_path", ""))
	if music_path == "":
		return fallback_stream
	if _bgm_stream_cache.has(meta_selected_bgm_id):
		var cached: AudioStream = _bgm_stream_cache[meta_selected_bgm_id] as AudioStream
		if cached:
			return cached
	var s: AudioStream = load(music_path) as AudioStream
	if s:
		_bgm_stream_cache[meta_selected_bgm_id] = s
		return s
	return fallback_stream


func _apply_selected_map() -> void:
	if not background_node:
		return
	if not (background_node is Sprite2D):
		return
	var bg := background_node as Sprite2D
	# default：沿用場景原本貼圖
	if meta_selected_map == "default":
		# 重新初始化 repeat sprite（確保回到原本背景也能鋪滿）
		_init_background()
		return
	var def: Dictionary = _map_defs.get(meta_selected_map, {}) as Dictionary
	if def.is_empty():
		return
	var tex: Texture2D = def.get("texture") as Texture2D
	if tex:
		bg.texture = tex
		_init_background()


func _apply_selected_menu_map() -> void:
	if not menu_background:
		return
	# default：回到場景預設
	if meta_selected_menu_map == "default":
		if _builtin_menu_bg_texture:
			menu_background.texture = _builtin_menu_bg_texture
		return
	var def: Dictionary = _map_defs.get(meta_selected_menu_map, {}) as Dictionary
	if def.is_empty():
		return
	var tex: Texture2D = def.get("texture") as Texture2D
	if tex:
		menu_background.texture = tex


func _apply_selected_skin() -> void:
	var def: Dictionary = _skin_defs.get(meta_selected_skin, {}) as Dictionary
	if def.is_empty():
		return
	var black_hole = %BlackHole
	if black_hole and black_hole.has_method("apply_skin_def"):
		black_hole.apply_skin_def(def)
	elif black_hole and black_hole.has_method("apply_skin_texture"):
		var tex: Texture2D = def.get("texture") as Texture2D
		black_hole.apply_skin_texture(tex)


func get_selected_skin_def() -> Dictionary:
	# Called by BlackHole.gd at runtime to apply the currently selected skin profile.
	return _skin_defs.get(meta_selected_skin, {}) as Dictionary


func _apply_upgrades_to_runtime() -> void:
	# 1) 初始引力大小（以 base_pull_radius 控制）
	var black_hole = %BlackHole
	if black_hole:
		var base_radius := 500.0
		var radius_per_level := 70.0
		black_hole.base_pull_radius = base_radius + float(upgrade_gravity_level) * radius_per_level
		# 讓鎖定半徑機制立即反映
		if black_hole.has_method("reset_for_new_run") and game_started == false:
			black_hole.reset_for_new_run()

	# 2) 移動速度 (combine meta upgrade + roguelike modifiers)
	var pc = get_node_or_null("PlayerController")
	if pc and pc.has_method("apply_speed_multiplier"):
		var speed_mult := 1.0 + float(upgrade_speed_level) * 0.08
		# Layer roguelike speed modifier on top of meta upgrade
		var rum_speed = get_node_or_null("/root/RoguelikeUpgradeManager")
		if rum_speed and rum_speed.has_method("get_multiplier"):
			speed_mult *= rum_speed.get_multiplier("move_speed_mult")
		pc.apply_speed_multiplier(speed_mult)

	# 3) 磁鐵持續時間
	magnet_duration = 10.0 + float(upgrade_magnet_level) * 2.0


func _upgrade_cost(kind: String, level: int) -> int:
	# 簡單直覺：每升一級成本增加
	match kind:
		"gravity":
			return 120 + level * 90
		"speed":
			return 150 + level * 110
		"magnet":
			return 140 + level * 100
		_:
			return 999999


func _setup_skins_dialog() -> void:
	if _skins_dialog:
		return
	_skins_dialog = AcceptDialog.new()
	_skins_dialog.title = "Skins"
	_skins_dialog.dialog_text = ""
	_skins_dialog.unresizable = true
	_skins_dialog.min_size = Vector2i(620, 360)
	_skins_dialog.size = Vector2i(620, 360)
	_skins_dialog.ok_button_text = "關閉"
	add_child(_skins_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_skins_dialog.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skins_option = opt
	row.add_child(opt)
	opt.item_selected.connect(_on_skin_selected)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(180, 180)
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skins_preview = preview
	row.add_child(preview)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	root.add_child(btn_row)

	var apply_btn := Button.new()
	apply_btn.text = "使用"
	btn_row.add_child(apply_btn)
	apply_btn.pressed.connect(_on_skin_apply_pressed)

	var unlock_btn := Button.new()
	unlock_btn.text = "看廣告解鎖"
	btn_row.add_child(unlock_btn)
	_skins_unlock_button = unlock_btn
	unlock_btn.pressed.connect(_on_skin_unlock_pressed)

	var coin_btn := Button.new()
	coin_btn.text = "用金幣解鎖"
	btn_row.add_child(coin_btn)
	_skins_coin_unlock_button = coin_btn
	coin_btn.pressed.connect(_on_skin_coin_unlock_pressed)

	_refresh_skins_ui()


func _setup_upgrades_dialog() -> void:
	if _upgrades_dialog:
		return
	_upgrades_dialog = AcceptDialog.new()
	_upgrades_dialog.title = "Upgrades"
	_upgrades_dialog.dialog_text = ""
	_upgrades_dialog.unresizable = true
	_upgrades_dialog.min_size = Vector2i(720, 420)
	_upgrades_dialog.size = Vector2i(720, 420)
	_upgrades_dialog.ok_button_text = "關閉"
	add_child(_upgrades_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_upgrades_dialog.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var coins := Label.new()
	coins.name = "CoinsInUpgrades"
	coins.add_theme_font_size_override("font_size", 22)
	root.add_child(coins)
	_upgrade_labels["coins"] = coins

	_add_upgrade_row(root, "gravity", "初始引力大小")
	_add_upgrade_row(root, "speed", "移動速度")
	_add_upgrade_row(root, "magnet", "磁鐵持續時間")

	# Maps entry (open separate dialog)
	var maps_row := HBoxContainer.new()
	maps_row.add_theme_constant_override("separation", 12)
	root.add_child(maps_row)
	var maps_lbl := Label.new()
	maps_lbl.text = "地圖"
	maps_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maps_lbl.add_theme_font_size_override("font_size", 20)
	maps_row.add_child(maps_lbl)
	var maps_btn := Button.new()
	maps_btn.text = "開啟地圖商店"
	maps_btn.custom_minimum_size = Vector2(180, 42)
	maps_row.add_child(maps_btn)
	maps_btn.pressed.connect(_on_maps_pressed)

	# Reset upgrades
	var reset_row := HBoxContainer.new()
	reset_row.add_theme_constant_override("separation", 12)
	root.add_child(reset_row)
	var reset_lbl := Label.new()
	reset_lbl.text = "能力"
	reset_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_lbl.add_theme_font_size_override("font_size", 20)
	reset_row.add_child(reset_lbl)
	var reset_btn := Button.new()
	reset_btn.text = "重製能力"
	reset_btn.custom_minimum_size = Vector2(180, 42)
	reset_row.add_child(reset_btn)
	_reset_upgrades_button = reset_btn
	reset_btn.pressed.connect(_on_reset_upgrades_pressed)

	_reset_upgrades_confirm_dialog = ConfirmationDialog.new()
	_reset_upgrades_confirm_dialog.title = "重製能力"
	_reset_upgrades_confirm_dialog.dialog_text = "確定要重製所有能力升級到 Lv.0 嗎？\n（會返還已花費的升級金幣）"
	_reset_upgrades_confirm_dialog.ok_button_text = "確認"
	_reset_upgrades_confirm_dialog.cancel_button_text = "取消"
	_upgrades_dialog.add_child(_reset_upgrades_confirm_dialog)
	if not _reset_upgrades_confirm_dialog.confirmed.is_connected(_on_reset_upgrades_confirmed):
		_reset_upgrades_confirm_dialog.confirmed.connect(_on_reset_upgrades_confirmed)

	_refresh_upgrades_ui()
	_refresh_maps_ui()


func _upgrade_total_spent(kind: String, level: int) -> int:
	var total := 0
	for i in range(level):
		total += _upgrade_cost(kind, i)
	return total


func _on_reset_upgrades_pressed() -> void:
	if _reset_upgrades_confirm_dialog:
		_reset_upgrades_confirm_dialog.popup_centered(Vector2i(520, 220))


func _on_reset_upgrades_confirmed() -> void:
	var refund := 0
	refund += _upgrade_total_spent("gravity", upgrade_gravity_level)
	refund += _upgrade_total_spent("speed", upgrade_speed_level)
	refund += _upgrade_total_spent("magnet", upgrade_magnet_level)

	upgrade_gravity_level = 0
	upgrade_speed_level = 0
	upgrade_magnet_level = 0
	meta_coins += refund

	_save_meta()
	_apply_upgrades_to_runtime()
	_refresh_upgrades_ui()
	_show_toast("已重製能力，返還 %d 金幣" % refund, Color(0.2, 1, 1))


func _setup_maps_dialog() -> void:
	if _maps_dialog:
		return
	_maps_dialog = AcceptDialog.new()
	_maps_dialog.title = "Maps"
	_maps_dialog.dialog_text = ""
	_maps_dialog.unresizable = true
	_maps_dialog.min_size = Vector2i(720, 420)
	_maps_dialog.size = Vector2i(720, 420)
	_maps_dialog.ok_button_text = "關閉"
	add_child(_maps_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_maps_dialog.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var preview_aspect := AspectRatioContainer.new()
	preview_aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_aspect.ratio = 16.0 / 9.0
	root.add_child(preview_aspect)

	var preview_layer := Control.new()
	preview_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_aspect.add_child(preview_layer)

	var preview := TextureRect.new()
	preview.anchor_left = 0.0
	preview.anchor_top = 0.0
	preview.anchor_right = 1.0
	preview.anchor_bottom = 1.0
	preview.offset_left = 0
	preview.offset_top = 0
	preview.offset_right = 0
	preview.offset_bottom = 0
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_maps_preview = preview
	preview_layer.add_child(preview)
	if not preview.gui_input.is_connected(_on_maps_preview_gui_input):
		preview.gui_input.connect(_on_maps_preview_gui_input)

	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(44, 44)
	prev_btn.focus_mode = Control.FOCUS_NONE
	prev_btn.anchor_left = 0.0
	prev_btn.anchor_right = 0.0
	prev_btn.anchor_top = 0.5
	prev_btn.anchor_bottom = 0.5
	prev_btn.offset_left = 6
	prev_btn.offset_top = -22
	prev_btn.offset_right = 50
	prev_btn.offset_bottom = 22
	preview_layer.add_child(prev_btn)
	prev_btn.pressed.connect(_on_maps_prev_pressed)

	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(44, 44)
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.anchor_left = 1.0
	next_btn.anchor_right = 1.0
	next_btn.anchor_top = 0.5
	next_btn.anchor_bottom = 0.5
	next_btn.offset_left = -50
	next_btn.offset_top = -22
	next_btn.offset_right = -6
	next_btn.offset_bottom = 22
	preview_layer.add_child(next_btn)
	next_btn.pressed.connect(_on_maps_next_pressed)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_maps_name_label = name_lbl
	root.add_child(name_lbl)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_maps_option = opt
	root.add_child(opt)
	opt.item_selected.connect(_on_map_selected)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	root.add_child(btn_row)

	var use_game_btn := Button.new()
	use_game_btn.text = "遊戲使用"
	btn_row.add_child(use_game_btn)
	_maps_use_game_button = use_game_btn
	use_game_btn.pressed.connect(_on_map_use_game_pressed)

	var use_menu_btn := Button.new()
	use_menu_btn.text = "主選單使用"
	btn_row.add_child(use_menu_btn)
	_maps_use_menu_button = use_menu_btn
	use_menu_btn.pressed.connect(_on_map_use_menu_pressed)

	var buy_btn := Button.new()
	buy_btn.text = "用金幣解鎖"
	btn_row.add_child(buy_btn)
	_maps_buy_button = buy_btn
	buy_btn.pressed.connect(_on_map_buy_pressed)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(0.9, 0.9, 0.9)
	hint.text = "解鎖地圖與地圖限定專屬音樂"
	root.add_child(hint)

	_reload_map_defs_from_folder()
	_refresh_maps_ui()


func _on_maps_pressed() -> void:
	if _maps_dialog:
		_reload_map_defs_from_folder()
		_refresh_maps_ui()
		_maps_dialog.popup_centered(Vector2i(720, 420))


func _refresh_maps_ui() -> void:
	if not _maps_option:
		return
	_maps_option.clear()
	var idx := 0
	var selected_idx := 0
	for map_id in _map_defs.keys():
		var def: Dictionary = _map_defs[map_id]
		var nm: String = String(def.get("name", map_id))
		var unlocked: bool = meta_unlocked_maps.has(map_id) and bool(meta_unlocked_maps[map_id])
		var label := ""
		if unlocked:
			label = "%s（已解鎖）" % nm
		else:
			var price := int(def.get("price", 999999))
			label = "%s（未解鎖 - %d 金幣）" % [nm, price]
		_maps_option.add_item(label)
		_maps_option.set_item_metadata(idx, map_id)
		if map_id == meta_selected_map:
			selected_idx = idx
		idx += 1
	_maps_option.select(selected_idx)
	_update_map_preview_and_buttons()


func _on_map_selected(_index: int) -> void:
	_update_map_preview_and_buttons()


func _update_map_preview_and_buttons() -> void:
	if not _maps_option:
		return
	var map_id: String = String(_maps_option.get_item_metadata(_maps_option.selected))
	var def: Dictionary = _map_defs.get(map_id, {}) as Dictionary
	var tex: Texture2D = def.get("texture") as Texture2D
	if _maps_preview:
		_maps_preview.texture = tex
	var unlocked: bool = meta_unlocked_maps.has(map_id) and bool(meta_unlocked_maps[map_id])
	if _maps_name_label:
		var nm: String = String(def.get("name", map_id))
		_maps_name_label.text = "%s%s" % [nm, "" if unlocked else "（未解鎖）"]
	if _maps_use_game_button:
		_maps_use_game_button.disabled = not unlocked
	if _maps_use_menu_button:
		_maps_use_menu_button.disabled = not unlocked
	if _maps_buy_button:
		var price := int(def.get("price", 999999))
		_maps_buy_button.text = "用金幣解鎖（%d）" % price
		_maps_buy_button.disabled = unlocked or meta_coins < price


func _on_map_use_game_pressed() -> void:
	if not _maps_option:
		return
	var map_id: String = String(_maps_option.get_item_metadata(_maps_option.selected))
	if meta_unlocked_maps.has(map_id) and bool(meta_unlocked_maps[map_id]):
		meta_selected_map = map_id
		_apply_selected_map()
		_save_meta()
		_refresh_maps_ui()


func _on_map_use_menu_pressed() -> void:
	if not _maps_option:
		return
	var map_id: String = String(_maps_option.get_item_metadata(_maps_option.selected))
	if meta_unlocked_maps.has(map_id) and bool(meta_unlocked_maps[map_id]):
		meta_selected_menu_map = map_id
		_apply_selected_menu_map()
		_save_meta()
		_refresh_maps_ui()


func _on_map_buy_pressed() -> void:
	if not _maps_option:
		return
	var map_id: String = String(_maps_option.get_item_metadata(_maps_option.selected))
	var def: Dictionary = _map_defs.get(map_id, {}) as Dictionary
	if def.is_empty():
		return
	var price := int(def.get("price", 999999))
	if meta_coins < price:
		return
	if meta_unlocked_maps.has(map_id) and bool(meta_unlocked_maps[map_id]):
		return
	meta_coins -= price
	meta_unlocked_maps[map_id] = true
	# 買了就順便套到遊戲背景（主選單要不要套由玩家按按鈕決定）
	meta_selected_map = map_id
	_apply_selected_map()
	_save_meta()
	_update_meta_ui()
	_refresh_maps_ui()
	_refresh_bgm_options()
	_refresh_music_by_state()


func _select_map_relative(step: int) -> void:
	if not _maps_option:
		return
	var count := _maps_option.item_count
	if count <= 0:
		return
	var idx := _maps_option.selected + step
	if idx < 0:
		idx = count - 1
	elif idx >= count:
		idx = 0
	_maps_option.select(idx)
	_update_map_preview_and_buttons()


func _on_maps_prev_pressed() -> void:
	_select_map_relative(-1)


func _on_maps_next_pressed() -> void:
	_select_map_relative(1)


func _on_maps_preview_gui_input(event: InputEvent) -> void:
	# 支援滑動切換（觸控/滑鼠拖曳）
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_maps_swipe_active = true
			_maps_swipe_start_x = e.position.x
			_maps_swipe_last_x = e.position.x
		else:
			if _maps_swipe_active:
				var dx := _maps_swipe_last_x - _maps_swipe_start_x
				_maps_swipe_active = false
				if absf(dx) >= 50.0:
					_select_map_relative(-1 if dx > 0.0 else 1)
		return
	if event is InputEventScreenDrag:
		if _maps_swipe_active:
			_maps_swipe_last_x = (event as InputEventScreenDrag).position.x
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_maps_swipe_active = true
				_maps_swipe_start_x = mb.position.x
				_maps_swipe_last_x = mb.position.x
			else:
				if _maps_swipe_active:
					var dxm := _maps_swipe_last_x - _maps_swipe_start_x
					_maps_swipe_active = false
					if absf(dxm) >= 50.0:
						_select_map_relative(-1 if dxm > 0.0 else 1)
		return
	if event is InputEventMouseMotion:
		if _maps_swipe_active:
			_maps_swipe_last_x = (event as InputEventMouseMotion).position.x
		return


func _add_upgrade_row(root: VBoxContainer, kind: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)

	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 20)
	row.add_child(lbl)
	_upgrade_labels[kind] = lbl

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(180, 42)
	row.add_child(btn)
	_upgrade_buttons[kind] = btn
	btn.pressed.connect(func():
		_on_upgrade_pressed(kind)
	)
	btn.set_meta("title", title)


func _refresh_skins_ui() -> void:
	if not _skins_option:
		return
	_skins_option.clear()
	var idx := 0
	var selected_idx := 0
	for skin_id in _skin_defs.keys():
		var def: Dictionary = _skin_defs[skin_id]
		var unlocked: bool = meta_unlocked_skins.has(skin_id) and bool(meta_unlocked_skins[skin_id])
		# Hide gacha-only skins until obtained.
		if bool(def.get("gacha_only", false)) and not unlocked:
			continue
		var nm: String = String(def.get("name", skin_id))
		var label := ""
		if unlocked:
			label = "%s（已解鎖）" % nm
		else:
			var price := _get_skin_price(String(skin_id))
			label = "%s（未解鎖 - %d 金幣 / 廣告）" % [nm, price]
		_skins_option.add_item(label)
		_skins_option.set_item_metadata(idx, skin_id)
		if skin_id == meta_selected_skin:
			selected_idx = idx
		idx += 1
	_skins_option.select(selected_idx)
	_update_skin_preview_and_unlock()


func _update_skin_preview_and_unlock() -> void:
	if not _skins_option:
		return
	var skin_id: String = String(_skins_option.get_item_metadata(_skins_option.selected))
	var def: Dictionary = _skin_defs.get(skin_id, {}) as Dictionary
	if not def.is_empty() and _skins_preview:
		_skins_preview.texture = def.get("texture") as Texture2D
	var unlocked: bool = meta_unlocked_skins.has(skin_id) and bool(meta_unlocked_skins[skin_id])
	if _skins_unlock_button:
		_skins_unlock_button.disabled = unlocked
	if _skins_coin_unlock_button:
		var price := _get_skin_price(skin_id)
		_skins_coin_unlock_button.text = "用金幣解鎖（%d）" % price
		_skins_coin_unlock_button.disabled = unlocked or meta_coins < price


func _refresh_upgrades_ui() -> void:
	# coins label
	var coins_lbl: Label = _upgrade_labels.get("coins", null) as Label
	if coins_lbl:
		coins_lbl.text = "金幣：%d" % meta_coins

	_update_upgrade_row("gravity", upgrade_gravity_level)
	_update_upgrade_row("speed", upgrade_speed_level)
	_update_upgrade_row("magnet", upgrade_magnet_level)


func _update_upgrade_row(kind: String, level: int) -> void:
	var title := ""
	var btn: Button = _upgrade_buttons.get(kind, null) as Button
	if btn and btn.has_meta("title"):
		title = String(btn.get_meta("title"))
	else:
		title = kind

	var cost := _upgrade_cost(kind, level)
	var lbl: Label = _upgrade_labels.get(kind, null) as Label
	if lbl:
		lbl.text = "%s  Lv.%d   下一級：%d 金幣" % [title, level, cost]
	if btn:
		btn.text = "升級 (%d)" % cost
		btn.disabled = meta_coins < cost


func _on_skins_pressed() -> void:
	if _skins_dialog:
		_reload_skin_defs_from_folder()
		_refresh_skins_ui()
		_skins_dialog.popup_centered(Vector2i(620, 360))


func _on_upgrades_pressed() -> void:
	if _upgrades_dialog:
		_refresh_upgrades_ui()
		_upgrades_dialog.popup_centered(Vector2i(720, 380))


func _on_skin_selected(_index: int) -> void:
	_update_skin_preview_and_unlock()


func _on_skin_apply_pressed() -> void:
	if not _skins_option:
		return
	var skin_id: String = String(_skins_option.get_item_metadata(_skins_option.selected))
	var unlocked: bool = meta_unlocked_skins.has(skin_id) and bool(meta_unlocked_skins[skin_id])
	if not unlocked:
		_show_toast("尚未解鎖此 Skin", Color.ORANGE)
		return
	meta_selected_skin = skin_id
	_save_meta()
	_apply_selected_skin()
	_show_toast("已套用 Skin：%s" % String(_skin_defs[skin_id]["name"]), Color(0.2, 1, 1))


func _on_skin_unlock_pressed() -> void:
	if not _skins_option:
		return
	var skin_id: String = String(_skins_option.get_item_metadata(_skins_option.selected))
	if meta_unlocked_skins.has(skin_id) and bool(meta_unlocked_skins[skin_id]):
		return
	# 商業化：這裡先用「模擬看廣告」直接解鎖
	meta_unlocked_skins[skin_id] = true
	_save_meta()
	_refresh_skins_ui()
	_update_meta_ui()
	_show_toast("已解鎖 Skin：%s" % String(_skin_defs[skin_id]["name"]), Color.GREEN)


func _on_skin_coin_unlock_pressed() -> void:
	if not _skins_option:
		return
	var skin_id: String = String(_skins_option.get_item_metadata(_skins_option.selected))
	if meta_unlocked_skins.has(skin_id) and bool(meta_unlocked_skins[skin_id]):
		return
	var price := _get_skin_price(skin_id)
	if meta_coins < price:
		_show_toast("金幣不足", Color.ORANGE)
		return
	meta_coins -= price
	meta_unlocked_skins[skin_id] = true
	_save_meta()
	_refresh_skins_ui()
	_update_meta_ui()
	_show_toast("已用金幣解鎖：%s" % String(_skin_defs[skin_id]["name"]), Color(0.2, 1, 1))


func _on_upgrade_pressed(kind: String) -> void:
	var level := 0
	match kind:
		"gravity":
			level = upgrade_gravity_level
		"speed":
			level = upgrade_speed_level
		"magnet":
			level = upgrade_magnet_level
		_:
			return
	var cost := _upgrade_cost(kind, level)
	if meta_coins < cost:
		_show_toast("金幣不足", Color.ORANGE)
		return
	meta_coins -= cost
	match kind:
		"gravity":
			upgrade_gravity_level += 1
		"speed":
			upgrade_speed_level += 1
		"magnet":
			upgrade_magnet_level += 1
	_save_meta()
	_apply_upgrades_to_runtime()
	_refresh_upgrades_ui()
	_update_meta_ui()
	_show_toast("升級完成！", Color(0.2, 1, 1))


func _on_settings_pressed() -> void:
	# Lazily create the dialog so a partial _ready() failure can't break settings.
	if not _settings_dialog or not is_instance_valid(_settings_dialog):
		_setup_settings_menu()
	if not _settings_dialog:
		return
	_refresh_music_by_state()
	_refresh_bgm_options()
	_rebuild_settings_missions()
	_apply_settings_modal(true)
	# Use a safe popup path; modal is handled via `exclusive = true`.
	_settings_dialog.popup_centered(Vector2i(620, 520))
	_settings_dialog.grab_focus()
	# Pause gameplay while settings is open (in-game only).
	if game_started and not is_game_over:
		if not get_tree().paused:
			get_tree().paused = true
			_paused_by_settings = true


func _on_settings_visibility_changed() -> void:
	# 視窗關閉/開啟時都刷新一次音樂狀態
	_refresh_music_by_state()
	if _abandon_button:
		_abandon_button.disabled = not game_started
	_apply_settings_modal(_settings_dialog != null and _settings_dialog.visible)
	# Resume gameplay when settings closes (only if we paused it).
	if _settings_dialog and not _settings_dialog.visible:
		if _paused_by_settings:
			get_tree().paused = false
			_paused_by_settings = false


func _apply_settings_modal(open: bool) -> void:
	# Godot GUI input can be blocked by full-screen Controls (MainMenu/HUD) if they have MOUSE_FILTER_STOP.
	# When settings is open, force those layers to IGNORE so the dialog always receives drag/click.
	if open:
		if _settings_modal_active:
			return
		_settings_modal_active = true
		if main_menu and main_menu is Control:
			_prev_main_menu_mouse_filter = (main_menu as Control).mouse_filter
			(main_menu as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		if hud and hud is Control:
			_prev_hud_mouse_filter = (hud as Control).mouse_filter
			(hud as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		return

	if not _settings_modal_active:
		return
	_settings_modal_active = false
	if main_menu and main_menu is Control:
		(main_menu as Control).mouse_filter = _prev_main_menu_mouse_filter
	if hud and hud is Control:
		(hud as Control).mouse_filter = _prev_hud_mouse_filter


func _on_abandon_pressed() -> void:
	if not game_started:
		return
	_setup_abandon_confirm_dialog()
	if _abandon_confirm_dialog:
		_abandon_confirm_dialog.popup_centered(Vector2i(620, 220))


func _setup_abandon_confirm_dialog() -> void:
	if _abandon_confirm_dialog:
		return
	_abandon_confirm_dialog = ConfirmationDialog.new()
	_abandon_confirm_dialog.title = "放棄本局？"
	_abandon_confirm_dialog.dialog_text = "確定要回主選單並放棄本局進度嗎？"
	_abandon_confirm_dialog.ok_button_text = "確定"
	_abandon_confirm_dialog.cancel_button_text = "取消"
	_abandon_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_abandon_confirm_dialog.exclusive = true
	# Make sure it's always above HUD/overlays.
	if _settings_layer and is_instance_valid(_settings_layer):
		_settings_layer.add_child(_abandon_confirm_dialog)
	else:
		var cl := get_node_or_null("CanvasLayer")
		if cl:
			cl.add_child(_abandon_confirm_dialog)
		else:
			add_child(_abandon_confirm_dialog)
	_abandon_confirm_dialog.confirmed.connect(_on_abandon_confirmed)


func _on_abandon_confirmed() -> void:
	# 確認後才真正放棄
	if _settings_dialog:
		_settings_dialog.hide()
	_abandon_to_main_menu()


func _abandon_to_main_menu() -> void:
	# 回主選單代表放棄本局：清場 + 重置到 menu 狀態
	_clear_world_entities()
	_enter_main_menu()


func _clear_world_entities() -> void:
	# 清除所有本局生成/殘留物件，避免主選單看到「死圖」或新局殘留
	var groups: Array[StringName] = [
		&"Enemies",
		&"EnemyProjectiles",
		&"Prey",
		&"Swallowables",
		&"PowerUps",
	]
	for g in groups:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n):
				n.queue_free()


func _on_music_volume_changed(value: float) -> void:
	battle_music_volume_db = value
	if _music_player and is_instance_valid(_music_player):
		_music_player.volume_db = value
	_update_music_value_label(value)
	_save_meta()


func _on_bgm_selected(_index: int) -> void:
	if not _bgm_option:
		return
	meta_selected_bgm_id = String(_bgm_option.get_item_metadata(_bgm_option.selected))
	_save_meta()
	_refresh_music_by_state()


func _on_sfx_volume_changed(value: float) -> void:
	sfx_volume_db = value
	_apply_sfx_volume_db(value)
	_update_sfx_value_label(value)
	_save_meta()


func _on_ripple_toggle_changed(pressed: bool) -> void:
	# CheckBox 文字是「關閉」，所以 pressed=true 代表要關閉
	gravity_ripple_enabled = not pressed
	var black_hole = %BlackHole
	if black_hole and black_hole.has_method("set_fullscreen_distort_enabled"):
		black_hole.set_fullscreen_distort_enabled(gravity_ripple_enabled)
	elif black_hole and not gravity_ripple_enabled and black_hole.has_method("disable_fullscreen_distort"):
		black_hole.disable_fullscreen_distort()


func _update_music_value_label(value_db: float) -> void:
	if not _music_value_label:
		return
	# 將 -30dB..0dB 映射到 0%..100% 顯示，直覺一點
	var percent := int(round(inverse_lerp(-30.0, 0.0, value_db) * 100.0))
	percent = clamp(percent, 0, 100)
	_music_value_label.text = "%d%%" % percent


func _update_sfx_value_label(value_db: float) -> void:
	if not _sfx_value_label:
		return
	var percent := int(round(inverse_lerp(-30.0, 0.0, value_db) * 100.0))
	percent = clamp(percent, 0, 100)
	_sfx_value_label.text = "%d%%" % percent


func _apply_sfx_volume_db(value_db: float) -> void:
	# Minimal: apply to known SFX players in MainScene.
	if sfx_level_up and is_instance_valid(sfx_level_up):
		sfx_level_up.volume_db = value_db
	if sfx_wanted_up and is_instance_valid(sfx_wanted_up):
		sfx_wanted_up.volume_db = value_db



func _input(event):
	# If settings dialog is open, don't run click fallbacks.
	if _settings_dialog and _settings_dialog.visible:
		return
	# 保險：若 UI 沒吃到點擊（常見於父節點裁切/覆蓋），用 rect hit-test 強制觸發
	var pos: Vector2
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pos = get_viewport().get_mouse_position()
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	else:
		return

	# 主選單：點擊「開始遊戲 / 關卡制」保險命中
	if not game_started and main_menu and main_menu.visible:
		if campaign_start_button and campaign_start_button is Control and campaign_start_button.visible:
			var camp_rect: Rect2 = (campaign_start_button as Control).get_global_rect()
			if camp_rect.has_point(pos):
				_on_start_campaign_pressed()
				get_viewport().set_input_as_handled()
				return
		if start_button and start_button is Control and start_button.visible:
			var start_rect: Rect2 = (start_button as Control).get_global_rect()
			if start_rect.has_point(pos):
				_on_start_game_pressed()
				get_viewport().set_input_as_handled()
				return
		if endless_button and endless_button is Control and endless_button.visible:
			var endless_rect: Rect2 = (endless_button as Control).get_global_rect()
			if endless_rect.has_point(pos):
				_on_start_endless_pressed()
				get_viewport().set_input_as_handled()
				return

		# 主選單：離線收益
		var idle_btn: Button = idle_rewards_button
		if not idle_btn:
			idle_btn = find_child("IdleRewardsButton", true, false) as Button
		if idle_btn and idle_btn is Control:
			var idle_rect: Rect2 = (idle_btn as Control).get_global_rect()
			if idle_rect.has_point(pos):
				_on_idle_rewards_pressed()
				get_viewport().set_input_as_handled()
				return

		# 主選單：Skins / Upgrades 保險命中
		var skins_btn = skins_button
		if not skins_btn:
			skins_btn = find_child("SkinsButton", true, false) as Button
		if skins_btn and skins_btn is Control:
			var skins_rect: Rect2 = (skins_btn as Control).get_global_rect()
			if skins_rect.has_point(pos):
				_on_skins_pressed()
				get_viewport().set_input_as_handled()
				return
		var up_btn = upgrades_button
		if not up_btn:
			up_btn = find_child("UpgradesButton", true, false) as Button
		if up_btn and up_btn is Control:
			var up_rect: Rect2 = (up_btn as Control).get_global_rect()
			if up_rect.has_point(pos):
				_on_upgrades_pressed()
				get_viewport().set_input_as_handled()
				return

		# 主選單：設定
		var menu_set_btn: Button = menu_settings_button
		if not menu_set_btn:
			menu_set_btn = find_child("MenuSettingsButton", true, false) as Button
		if menu_set_btn and menu_set_btn is Control:
			var menu_set_rect: Rect2 = (menu_set_btn as Control).get_global_rect()
			if menu_set_rect.has_point(pos):
				_on_settings_pressed()
				get_viewport().set_input_as_handled()
				return

	# 設定按鈕優先（右上角）
	if settings_button and settings_button is Control and settings_button.visible:
		var settings_rect: Rect2 = (settings_button as Control).get_global_rect()
		if settings_rect.has_point(pos):
			_on_settings_pressed()
			get_viewport().set_input_as_handled()
			return

	# EMP 按鈕
	if emp_button and emp_button is Control and emp_button.visible:
		var emp_rect: Rect2 = (emp_button as Control).get_global_rect()
		if emp_rect.has_point(pos):
			_on_EMP_Button_pressed()
			get_viewport().set_input_as_handled()
			return

	# Shockwave 按鈕（遊戲中 HUD）
	if shockwave_button and shockwave_button is Control and shockwave_button.visible:
		var sw_rect: Rect2 = (shockwave_button as Control).get_global_rect()
		if sw_rect.has_point(pos):
			_on_shockwave_button_pressed()
			get_viewport().set_input_as_handled()
			return

func _init_ui():
	if score_label: score_label.text = "已吞噬：0"
	if level_label: level_label.text = "核心等級：Lv.1"
	if wanted_label: wanted_label.text = "SECURITY: SAFE"
	if stability_bar: 
		stability_bar.value = 100
		stability_bar.max_value = 100
		stability_bar.modulate = Color(0, 1, 1)

func _connect_signals():
	var black_hole = %BlackHole
	if black_hole:
		black_hole.object_swallowed.connect(_on_swallowed)
		black_hole.level_up.connect(_on_level_up)
		black_hole.reached_max_level.connect(_on_max_level)
		if black_hole.has_signal("objective_swallowed"):
			black_hole.objective_swallowed.connect(_on_campaign_objective_swallowed)
		if black_hole.has_signal("powerup_collected"):
			black_hole.powerup_collected.connect(_on_powerup_collected)
		if black_hole.has_signal("enemy_killed"):
			black_hole.enemy_killed.connect(_on_enemy_killed)
		
		if black_hole.has_signal("stability_changed"):
			black_hole.stability_changed.connect(_on_stability_changed)
		if black_hole.has_signal("stability_depleted"):
			black_hole.stability_depleted.connect(_on_entropy_death)
		if black_hole.has_signal("damaged"):
			black_hole.damaged.connect(_on_black_hole_damaged)
		if black_hole.has_signal("swallowed_feedback"):
			black_hole.swallowed_feedback.connect(_on_black_hole_swallowed_feedback)
		if black_hole.has_signal("shockwave_triggered"):
			black_hole.shockwave_triggered.connect(_on_black_hole_shockwave_triggered)
		if black_hole.has_signal("fever_started"):
			black_hole.fever_started.connect(_on_black_hole_fever_started)
		if black_hole.has_signal("fever_changed"):
			black_hole.fever_changed.connect(_on_black_hole_fever_changed)
		if black_hole.has_signal("fever_ended"):
			black_hole.fever_ended.connect(_on_black_hole_fever_ended)
		if black_hole.has_signal("fever_enemy_combo"):
			black_hole.fever_enemy_combo.connect(_on_black_hole_fever_enemy_combo)
	
	# 【新增】連接 EMP 按鈕的點擊訊號
	if emp_button:
		emp_button.pressed.connect(_on_EMP_Button_pressed)
	# Shockwave 按鈕（穩定觸發，避免雙擊偵測失敗）
	if shockwave_button and not shockwave_button.pressed.is_connected(_on_shockwave_button_pressed):
		shockwave_button.pressed.connect(_on_shockwave_button_pressed)

	if start_button and start_button is Button:
		if not (start_button as Button).pressed.is_connected(_on_start_game_pressed):
			(start_button as Button).pressed.connect(_on_start_game_pressed)
	if campaign_start_button and campaign_start_button is Button:
		if not (campaign_start_button as Button).pressed.is_connected(_on_start_campaign_pressed):
			(campaign_start_button as Button).pressed.connect(_on_start_campaign_pressed)
	if endless_button and endless_button is Button:
		if not (endless_button as Button).pressed.is_connected(_on_start_endless_pressed):
			(endless_button as Button).pressed.connect(_on_start_endless_pressed)

	# Roguelike: auto_shockwave event from powerup_collected signal
	if not Events.powerup_collected.is_connected(_on_roguelike_auto_shockwave):
		Events.powerup_collected.connect(_on_roguelike_auto_shockwave)

	# 音樂變速開關
	if music_pitch_toggle and music_pitch_toggle is CheckBox:
		# 初始化為 exported 設定值
		music_pitch_toggle.set_pressed(enable_dynamic_bgm_pitch)
		if not music_pitch_toggle.toggled.is_connected(_on_music_pitch_toggled):
			music_pitch_toggle.toggled.connect(_on_music_pitch_toggled)


func _enter_main_menu() -> void:
	# Safety: if settings modal/pause was active, clear it when returning to menu.
	if _settings_dialog and _settings_dialog.visible:
		_settings_dialog.hide()
	_apply_settings_modal(false)
	if get_tree().paused:
		get_tree().paused = false
	_paused_by_settings = false

	game_started = false
	is_game_over = false
	_revive_prompt_open = false

	# 進主選單先清場，避免看到上一局殘留或一開始就出現不互動獵物
	_clear_world_entities()
	_clear_campaign_runtime()
	_reset_feedback_overlays_for_menu()

	# 先把 HUD 藏起來，避免一進場就滿版文字
	if hud:
		hud.hide()
	if main_menu:
		main_menu.show()
		# 強制保險：確保主選單在最上層且可見（行動裝置上可能被 CanvasLayer / full-screen overlays 遮蔽）
		if main_menu is CanvasItem:
			# 提升 z_index (clamped to RenderingServer limits)
			main_menu.z_index = min(max(main_menu.z_index, 100000), int(RenderingServer.CANVAS_ITEM_Z_MAX))
			# 嘗試把父層（若為 CanvasLayer）提升到更高層級
			var pm = main_menu.get_parent()
			if pm and pm is CanvasLayer:
				pm.layer = max(pm.layer, 1000)
		# 嘗試把節點帶到最上層
		if main_menu.has_method("raise"):
			main_menu.call("raise")
		print("_enter_main_menu: main_menu shown; z_index=", (main_menu.z_index if main_menu is CanvasItem else "N/A"))

	# 停止地圖事件
	_stop_map_event()

	# 停止生成與玩家控制/黑洞處理
	if _spawn_mgr:
		_spawn_mgr.stop_timers()

	var player_controller = get_node_or_null("PlayerController")
	if player_controller:
		player_controller.set_physics_process(false)

	var black_hole = %BlackHole
	if black_hole:
		black_hole.set_process(false)
		black_hole.set_physics_process(false)
		if black_hole.has_method("disable_fullscreen_distort"):
			black_hole.disable_fullscreen_distort()

	# 重置 UI 顯示（但不開局）
	time_left = game_duration
	current_score = 0
	wanted_level = 0
	_combo_count = 0
	_combo_timer = 0.0
	_fever_combo_count = 0
	_fever_combo_last_sec = -9999.0
	_fever_time_left = 0.0
	if _spawn_mgr:
		_spawn_mgr.reset_powerup_state()
		_spawn_mgr.set_fever_active(false)
	if %BlackHole and %BlackHole.has_method("set_shield_active"):
		%BlackHole.set_shield_active(false)
	_hide_boss_hp_bar()
	_init_ui()
	_update_time_ui()
	_update_wanted_ui()
	if emp_button:
		emp_button.hide()
	if shockwave_button:
		shockwave_button.hide()
	_apply_meta_to_session()
	_refresh_music_by_state()
	# 離線收益提示（不自動領取，改由主選單選項領取）
	if _pending_idle_reward_coins > 0:
		_show_toast("離線收益可領取：%d 金幣" % _pending_idle_reward_coins, Color(0.2, 1, 1))
	# 試用結束提示
	if _trial_skin_id != "" and (not meta_unlocked_skins.has(_trial_skin_id) or not bool(meta_unlocked_skins[_trial_skin_id])):
		_show_toast("試用結束：%s（到 Skins 可購買）" % _trial_skin_id, Color(1, 1, 0.6))
	_trial_skin_id = ""


func _on_start_game_pressed() -> void:
	_pending_game_mode = GameMode.INFINITE
	_show_character_select()

func _on_start_endless_pressed() -> void:
	_pending_game_mode = GameMode.ENDLESS
	_show_character_select()

func _show_character_select() -> void:
	if _character_select_ui and is_instance_valid(_character_select_ui):
		_character_select_ui.queue_free()
	var CharSelectScript: GDScript = load("res://Scripts/CharacterSelectUI.gd") as GDScript
	if not CharSelectScript:
		# Fallback: skip character select, use default
		game_mode = _pending_game_mode
		_start_game()
		return
	# Hide main menu so it doesn't bleed through
	if main_menu:
		main_menu.hide()
	_character_select_ui = CharSelectScript.new() as CanvasLayer
	add_child(_character_select_ui)
	_character_select_ui.character_chosen.connect(_on_character_chosen)
	_character_select_ui.cancelled.connect(_on_character_select_cancelled)

func _on_character_chosen(character_id: String) -> void:
	game_mode = _pending_game_mode
	_start_game()

func _on_character_select_cancelled() -> void:
	# Restore main menu visibility
	if main_menu:
		main_menu.show()


func _on_start_campaign_pressed() -> void:
	game_mode = GameMode.CAMPAIGN
	_open_campaign_levels_dialog()


func _start_game() -> void:
	# Safety: ensure we are not paused or stuck in settings modal when starting.
	if _settings_dialog and _settings_dialog.visible:
		_settings_dialog.hide()
	_apply_settings_modal(false)
	if get_tree().paused:
		get_tree().paused = false
	_paused_by_settings = false

	# Reset roguelike manager for new run
	if has_node("/root/RoguelikeUpgradeManager"):
		get_node("/root/RoguelikeUpgradeManager").reset_run()

	game_started = true
	is_game_over = false
	_revive_prompt_open = false

	# 開新局前清掉可能殘留的物件（含主選單時期預放）
	_clear_world_entities()

	if main_menu:
		main_menu.hide()
	if hud:
		hud.show()
	if shockwave_button:
		shockwave_button.show()

	# Endless mode: no time limit (use a very large number)
	if game_mode == GameMode.ENDLESS:
		game_duration = 999999.0
	else:
		game_duration = ENDLESS_TIME_LIMIT

	# 初始化本局數值
	time_left = game_duration
	current_score = 0
	wanted_level = 0
	_combo_count = 0
	_combo_timer = 0.0
	if _combo_label and is_instance_valid(_combo_label):
		_combo_label.visible = false
	if _spawn_mgr:
		_spawn_mgr.reset_powerup_state()
	if %BlackHole and %BlackHole.has_method("set_shield_active"):
		%BlackHole.set_shield_active(false)
	_hide_boss_hp_bar()
	_run_enemies_killed = 0
	_run_shockwave_count = 0
	# 每局開始生成新的局內任務
	if has_node("/root/MissionManager"):
		var msm: Node = get_node("/root/MissionManager")
		msm.generate_run_missions()
		msm.reset_run_progress()
	_revive_used = false
	_run_score_claimed = false
	_apply_meta_to_session()
	_maybe_apply_trial_skin_for_run()
	_start_campaign_if_needed()

	_init_ui()
	_update_time_ui()
	_update_wanted_ui()
	# 啟用玩家控制/黑洞處理
	var player_controller = get_node_or_null("PlayerController")
	if player_controller:
		player_controller.set_physics_process(true)
	var black_hole = %BlackHole
	if black_hole:
		# 套用升級/皮膚後，重置黑洞確保初始引力大小正確
		if black_hole.has_method("reset_for_new_run"):
			black_hole.reset_for_new_run()
		black_hole.set_process(true)
		black_hole.set_physics_process(true)
		if black_hole.has_method("set_fullscreen_distort_enabled"):
			black_hole.set_fullscreen_distort_enabled(gravity_ripple_enabled)

	# 啟動生成
	if _spawn_mgr:
		_spawn_mgr.start_timers()
	_refresh_music_by_state()

	# ---- 地圖事件系統 ----
	_start_map_event_for_current()



func _start_campaign_if_needed() -> void:
	_clear_campaign_runtime()
	if game_mode != GameMode.CAMPAIGN:
		return
	# Use the starting camera position as the campaign "map center".
	_campaign_center = camera.global_position if camera else (%BlackHole.global_position if %BlackHole else Vector2.ZERO)
	_campaign_reached_lv7 = false
	_campaign_vortex_enabled = false
	_bind_campaign_map_and_music()
	time_left = CAMPAIGN_TIME_LIMIT
	_update_time_ui()
	_show_toast("關卡目標：\n達到 Lv.7 觸發目標\nLv.10 吞噬黃金核心", Color(1.0, 0.92, 0.35))


func _bind_campaign_map_and_music() -> void:
	var def := _get_campaign_level_def(campaign_level_id)
	var map_path: String = String(def.get("map_path", CAMPAIGN_MAP_PATH))
	var music_path: String = String(def.get("music_path", CAMPAIGN_MUSIC_PATH))

	# Force map texture
	_campaign_forced_map_texture = null
	if map_path != "" and ResourceLoader.exists(map_path):
		_campaign_forced_map_texture = load(map_path) as Texture2D
	if _campaign_forced_map_texture and background_node and (background_node is Sprite2D):
		(background_node as Sprite2D).texture = _campaign_forced_map_texture
		_init_background()

	# Force music
	_campaign_forced_music_stream = null
	if music_path != "" and ResourceLoader.exists(music_path):
		_campaign_forced_music_stream = load(music_path) as AudioStream
	# Ensure music updates to the forced campaign track.
	_refresh_music_by_state()


# ============================================================
# 地圖事件系統
# ============================================================
func _start_map_event_for_current() -> void:
	if not _map_event_manager:
		_map_event_manager = MapEventManager.new()
		_map_event_manager.name = "MapEventManager"
		add_child(_map_event_manager)

	# 決定實際地圖 ID
	var map_id: String = ""
	if game_mode == GameMode.CAMPAIGN:
		# 從關卡定義推導地圖 ID
		var def := _get_campaign_level_def(campaign_level_id)
		var map_path: String = String(def.get("map_path", ""))
		if map_path != "":
			map_id = map_path.get_file().to_lower().get_basename()
	else:
		map_id = meta_selected_map

	var player_ctrl: Node = get_node_or_null("PlayerController")
	_map_event_manager.start_map_event(map_id, self, %BlackHole, player_ctrl, _spawn_mgr, camera)

	# HUD 指示器
	_update_map_event_hud()


func _stop_map_event() -> void:
	if _map_event_manager:
		_map_event_manager.stop_map_event()
	if _map_event_label and is_instance_valid(_map_event_label):
		_map_event_label.text = ""
		_map_event_label.visible = false


func _update_map_event_hud() -> void:
	if not _map_event_manager or not _map_event_manager.has_active_event():
		if _map_event_label and is_instance_valid(_map_event_label):
			_map_event_label.visible = false
		return

	var ev: MapEventBase = _map_event_manager.get_current_event()
	if not ev:
		return

	# 第一次建立 label
	if not _map_event_label or not is_instance_valid(_map_event_label):
		_map_event_label = Label.new()
		_map_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_map_event_label.add_theme_font_size_override("font_size", 16)
		_map_event_label.add_theme_color_override("font_color", Color(1, 1, 0.8, 0.85))
		_map_event_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		_map_event_label.add_theme_constant_override("shadow_offset_x", 1)
		_map_event_label.add_theme_constant_override("shadow_offset_y", 1)
		_map_event_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if hud:
			hud.add_child(_map_event_label)
			_map_event_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
			_map_event_label.position.y = 50

	_map_event_label.text = "%s：%s" % [ev.get_event_name(), ev.get_event_description()]
	_map_event_label.visible = true

	# 3 秒後淡出提示
	if _map_event_label:
		var tw := create_tween()
		tw.tween_interval(3.0)
		tw.tween_property(_map_event_label, "modulate:a", 0.0, 1.5)


func _reset_feedback_overlays_for_menu() -> void:
	# Ensure any transient screen effects don't remain visible on the main menu.
	if damage_flash and is_instance_valid(damage_flash):
		damage_flash.modulate.a = 0.0
	if wanted_overlay and is_instance_valid(wanted_overlay):
		wanted_overlay.modulate.a = 1.0
		wanted_overlay.color.a = 0.0
	if campaign_gold_overlay and is_instance_valid(campaign_gold_overlay):
		campaign_gold_overlay.modulate.a = 1.0
		campaign_gold_overlay.color.a = 0.0
	if objective_arrow and is_instance_valid(objective_arrow):
		objective_arrow.visible = false
	_update_campaign_atmosphere(0.0, 0.0, true)


func _get_campaign_levels() -> Array:
	# Built-in 4 levels (preview map + forced BGM).
	return [
		{
			"id": 1,
			"name": "黃金沙漠",
			"map_path": "res://Maps/Golden Singularity.png",
			"music_path": "res://Maps/Golden Singularity.mp3"
		},
		{
			"id": 2,
			"name": "冰封禁域",
			"map_path": "res://Maps/聖誕雪地科幻無限場景.png",
			"music_path": "res://Maps/Crystalline Fault Lines.mp3"
		},
		{
			"id": 3,
			"name": "極熱熔岩",
			"map_path": "res://Maps/火山熔岩科幻場景.png",
			"music_path": "res://Maps/Ion Trails.mp3"
		},
		{
			"id": 4,
			"name": "森林之母",
			"map_path": "res://Maps/森林叢林科幻場景.png",
			"music_path": "res://Maps/Echoes in the Night.mp3"
		}
	]


func _get_campaign_level_def(level_id: int) -> Dictionary:
	for def in _get_campaign_levels():
		if int(def.get("id", 0)) == level_id:
			return def
	return _get_campaign_levels()[0] as Dictionary


func _get_campaign_fog_color(level_id: int) -> Color:
	# Used by near-core atmosphere: overlay + dust + flow lines.
	match level_id:
		1:
			return Color(1.0, 0.85, 0.2, 1.0) # desert / golden
		2:
			return Color(0.55, 0.86, 1.0, 1.0) # ice / cyan
		3:
			return Color(1.0, 0.45, 0.2, 1.0) # lava / orange-red
		4:
			return Color(0.35, 1.0, 0.55, 1.0) # forest / green
	return Color(1.0, 0.85, 0.2, 1.0)


func _setup_campaign_levels_dialog() -> void:
	if _campaign_levels_dialog:
		return
	_campaign_levels_dialog = AcceptDialog.new()
	_campaign_levels_dialog.title = "關卡選擇"
	_campaign_levels_dialog.dialog_text = ""
	_campaign_levels_dialog.unresizable = true
	_campaign_levels_dialog.min_size = Vector2i(720, 420)
	_campaign_levels_dialog.size = Vector2i(720, 420)
	_campaign_levels_dialog.ok_button_text = "關閉"
	_campaign_level_start_button = _campaign_levels_dialog.add_button("開始", false, "START") as Button
	add_child(_campaign_levels_dialog)
	if not _campaign_levels_dialog.custom_action.is_connected(_on_campaign_levels_dialog_action):
		_campaign_levels_dialog.custom_action.connect(_on_campaign_levels_dialog_action)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_campaign_levels_dialog.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var preview_aspect := AspectRatioContainer.new()
	preview_aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_aspect.ratio = 16.0 / 9.0
	root.add_child(preview_aspect)

	var preview_layer := Control.new()
	preview_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_aspect.add_child(preview_layer)

	var preview := TextureRect.new()
	preview.anchor_left = 0.0
	preview.anchor_top = 0.0
	preview.anchor_right = 1.0
	preview.anchor_bottom = 1.0
	preview.offset_left = 0
	preview.offset_top = 0
	preview.offset_right = 0
	preview.offset_bottom = 0
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_campaign_level_preview = preview
	preview_layer.add_child(preview)
	if not preview.gui_input.is_connected(_on_campaign_levels_preview_gui_input):
		preview.gui_input.connect(_on_campaign_levels_preview_gui_input)

	var locked_icon := TextureRect.new()
	locked_icon.anchor_left = 0.0
	locked_icon.anchor_top = 0.0
	locked_icon.anchor_right = 1.0
	locked_icon.anchor_bottom = 1.0
	locked_icon.offset_left = 0
	locked_icon.offset_top = 0
	locked_icon.offset_right = 0
	locked_icon.offset_bottom = 0
	locked_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	locked_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	locked_icon.visible = false
	if ResourceLoader.exists("res://Maps/unlock.png"):
		locked_icon.texture = load("res://Maps/unlock.png") as Texture2D
	_campaign_level_locked_label = locked_icon
	preview_layer.add_child(locked_icon)

	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(44, 44)
	prev_btn.focus_mode = Control.FOCUS_NONE
	prev_btn.anchor_left = 0.0
	prev_btn.anchor_right = 0.0
	prev_btn.anchor_top = 0.5
	prev_btn.anchor_bottom = 0.5
	prev_btn.offset_left = 6
	prev_btn.offset_top = -22
	prev_btn.offset_right = 50
	prev_btn.offset_bottom = 22
	preview_layer.add_child(prev_btn)
	prev_btn.pressed.connect(func():
		_select_campaign_level_relative(-1)
	)
	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(44, 44)
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.anchor_left = 1.0
	next_btn.anchor_right = 1.0
	next_btn.anchor_top = 0.5
	next_btn.anchor_bottom = 0.5
	next_btn.offset_left = -50
	next_btn.offset_top = -22
	next_btn.offset_right = -6
	next_btn.offset_bottom = 22
	preview_layer.add_child(next_btn)
	next_btn.pressed.connect(func():
		_select_campaign_level_relative(1)
	)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_level_name_label = name_lbl
	root.add_child(name_lbl)

	_update_campaign_levels_ui()


func _open_campaign_levels_dialog() -> void:
	if not _campaign_levels_dialog:
		_setup_campaign_levels_dialog()
	_campaign_level_selected_index = clampi(_campaign_level_selected_index, 0, CAMPAIGN_LEVEL_COUNT - 1)
	_update_campaign_levels_ui()
	_campaign_levels_dialog.popup_centered(Vector2i(720, 420))


func _is_campaign_level_unlocked(level_id: int) -> bool:
	return level_id <= meta_campaign_max_unlocked


func _update_campaign_levels_ui() -> void:
	if not _campaign_level_preview:
		return
	var levels := _get_campaign_levels()
	if levels.is_empty():
		return
	_campaign_level_selected_index = clampi(_campaign_level_selected_index, 0, levels.size() - 1)
	var def: Dictionary = levels[_campaign_level_selected_index] as Dictionary
	var level_id := int(def.get("id", 1))
	var nm: String = String(def.get("name", ""))
	var unlocked := _is_campaign_level_unlocked(level_id)
	var map_path: String = String(def.get("map_path", ""))
	var tex: Texture2D = null
	if map_path != "" and ResourceLoader.exists(map_path):
		tex = load(map_path) as Texture2D
	_campaign_level_preview.texture = tex if unlocked else null
	if _campaign_level_locked_label and is_instance_valid(_campaign_level_locked_label):
		_campaign_level_locked_label.visible = not unlocked
	if _campaign_level_name_label:
		_campaign_level_name_label.text = "第 %d 關：%s%s" % [level_id, nm, "" if unlocked else "（未解鎖）"]
	if _campaign_level_start_button and is_instance_valid(_campaign_level_start_button):
		_campaign_level_start_button.disabled = not unlocked


func _select_campaign_level_relative(step: int) -> void:
	var levels := _get_campaign_levels()
	if levels.is_empty():
		return
	var idx := _campaign_level_selected_index + step
	if idx < 0:
		idx = levels.size() - 1
	elif idx >= levels.size():
		idx = 0
	_campaign_level_selected_index = idx
	_update_campaign_levels_ui()


func _on_campaign_levels_preview_gui_input(event: InputEvent) -> void:
	# 支援滑動切換（觸控/滑鼠拖曳）
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_campaign_levels_swipe_active = true
			_campaign_levels_swipe_start_x = e.position.x
			_campaign_levels_swipe_last_x = e.position.x
		else:
			if _campaign_levels_swipe_active:
				var dx := _campaign_levels_swipe_last_x - _campaign_levels_swipe_start_x
				_campaign_levels_swipe_active = false
				if absf(dx) >= 50.0:
					_select_campaign_level_relative(-1 if dx > 0.0 else 1)
		return
	if event is InputEventScreenDrag:
		if _campaign_levels_swipe_active:
			_campaign_levels_swipe_last_x = (event as InputEventScreenDrag).position.x
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_campaign_levels_swipe_active = true
				_campaign_levels_swipe_start_x = mb.position.x
				_campaign_levels_swipe_last_x = mb.position.x
			else:
				if _campaign_levels_swipe_active:
					var dxm := _campaign_levels_swipe_last_x - _campaign_levels_swipe_start_x
					_campaign_levels_swipe_active = false
					if absf(dxm) >= 50.0:
						_select_campaign_level_relative(-1 if dxm > 0.0 else 1)
		return
	if event is InputEventMouseMotion:
		if _campaign_levels_swipe_active:
			_campaign_levels_swipe_last_x = (event as InputEventMouseMotion).position.x
		return


func _on_campaign_levels_dialog_action(action: StringName) -> void:
	if String(action) != "START":
		return
	var levels := _get_campaign_levels()
	if levels.is_empty():
		return
	var def: Dictionary = levels[_campaign_level_selected_index] as Dictionary
	var level_id := int(def.get("id", 1))
	if not _is_campaign_level_unlocked(level_id):
		_show_toast("此關卡尚未解鎖", Color(1, 1, 1))
		_update_campaign_levels_ui()
		return
	if _campaign_levels_dialog:
		_campaign_levels_dialog.hide()
	# Start selected campaign level.
	campaign_level_id = level_id
	_start_game()


func _ensure_campaign_atmosphere_nodes() -> void:
	if _campaign_atmosphere_root and is_instance_valid(_campaign_atmosphere_root):
		return
	var layer := get_node_or_null("FeedbackLayer") as CanvasLayer
	if not layer:
		return
	_campaign_atmosphere_root = Node2D.new()
	_campaign_atmosphere_root.name = "CampaignAtmosphere"
	layer.add_child(_campaign_atmosphere_root)

	_campaign_sand_particles = GPUParticles2D.new()
	_campaign_sand_particles.name = "CampaignSandDust"
	_campaign_sand_particles.emitting = false
	_campaign_sand_particles.one_shot = false
	_campaign_sand_particles.amount = 160
	_campaign_sand_particles.lifetime = 1.6
	_campaign_sand_particles.explosiveness = 0.0
	_campaign_sand_particles.randomness = 0.6
	_campaign_sand_particles.speed_scale = 1.0
	var star_tex: Texture2D = null
	if ResourceLoader.exists("res://Maps/star.png"):
		star_tex = load("res://Maps/star.png") as Texture2D
	if star_tex:
		_campaign_sand_particles.texture = star_tex
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 240.0
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 180.0
	pm.gravity = Vector3(0.0, 0.0, 0.0)
	pm.initial_velocity_min = 30.0
	pm.initial_velocity_max = 130.0
	pm.damping_min = 6.0
	pm.damping_max = 14.0
	pm.angular_velocity_min = -50.0
	pm.angular_velocity_max = 50.0
	pm.scale_min = 0.25
	pm.scale_max = 0.85
	pm.color = Color(1.0, 0.85, 0.2, 0.28)
	_campaign_sand_particles.process_material = pm
	_campaign_atmosphere_root.add_child(_campaign_sand_particles)

	_campaign_flow_lines = Line2D.new()
	_campaign_flow_lines.name = "CampaignFlowLines"
	_campaign_flow_lines.width = 3.0
	_campaign_flow_lines.default_color = Color(1.0, 0.85, 0.2, 0.0)
	_campaign_flow_lines.antialiased = true
	_campaign_flow_lines.round_precision = 8
	_campaign_atmosphere_root.add_child(_campaign_flow_lines)


func _update_campaign_atmosphere(delta: float, proximity: float, force_hide: bool = false) -> void:
	_ensure_campaign_atmosphere_nodes()
	if not (_campaign_atmosphere_root and is_instance_valid(_campaign_atmosphere_root)):
		return
	var fog := _get_campaign_fog_color(campaign_level_id)
	if force_hide:
		if _campaign_sand_particles and is_instance_valid(_campaign_sand_particles):
			_campaign_sand_particles.emitting = false
		if _campaign_flow_lines and is_instance_valid(_campaign_flow_lines):
			_campaign_flow_lines.default_color = Color(fog.r, fog.g, fog.b, 0.0)
			_campaign_flow_lines.clear_points()
		_campaign_prev_proximity = -1.0
		return

	# Skip rebuild if proximity hasn't changed meaningfully
	var p: float = clampf(proximity, 0.0, 1.0)
	var proximity_changed: bool = absf(p - _campaign_prev_proximity) >= 0.01
	_campaign_prev_proximity = p

	_campaign_flow_time += delta
	var vp: Vector2 = get_viewport_rect().size
	var center: Vector2 = vp * 0.5

	if _campaign_sand_particles and is_instance_valid(_campaign_sand_particles):
		_campaign_sand_particles.position = center
		_campaign_sand_particles.emitting = (p > 0.02)
		if proximity_changed:
			_campaign_sand_particles.amount = int(lerpf(60.0, 260.0, p))
			_campaign_sand_particles.modulate = Color(fog.r, fog.g, fog.b, lerpf(0.0, 0.55, p))
			var pm := _campaign_sand_particles.process_material as ParticleProcessMaterial
			if pm:
				pm.emission_sphere_radius = lerpf(340.0, 220.0, p)
				pm.initial_velocity_min = lerpf(18.0, 55.0, p)
				pm.initial_velocity_max = lerpf(65.0, 165.0, p)

	if _campaign_flow_lines and is_instance_valid(_campaign_flow_lines):
		var a: float = lerpf(0.0, 0.26, p)
		_campaign_flow_lines.default_color = Color(fog.r, fog.g, fog.b, a)
		_campaign_flow_lines.clear_points()
		# Simple spiral: screen-space flow lines that feel like "currents".
		var turns: float = lerpf(1.8, 3.4, p)
		var pts: int = 36  # Reduced from 72 — visually identical on mobile
		var r0: float = lerpf(220.0, 160.0, p)
		var r1: float = lerpf(560.0, 820.0, p)
		var t0: float = _campaign_flow_time * lerpf(0.45, 1.15, p)
		for i in range(pts):
			var u := float(i) / float(max(1, pts - 1))
			var ang := (u * TAU * turns) + t0
			var rr := lerpf(r0, r1, u)
			var wobble := 18.0 * sin((u * 8.0) + t0 * 1.6)
			var pos := center + Vector2(cos(ang), sin(ang)) * (rr + wobble)
			_campaign_flow_lines.add_point(pos)


func _spawn_golden_core_objective() -> void:
	if _campaign_objective and is_instance_valid(_campaign_objective):
		_campaign_objective.queue_free()
		_campaign_objective = null
	if not GOLDEN_CORE_SCENE:
		return
	var node := GOLDEN_CORE_SCENE.instantiate()
	if not (node is Node2D):
		return
	_campaign_objective = node as Node2D
	add_child(_campaign_objective)
	_campaign_objective.global_position = _campaign_center


func _clear_campaign_runtime() -> void:
	_campaign_vortex_enabled = false
	_campaign_reached_lv7 = false
	_campaign_forced_map_texture = null
	_campaign_forced_music_stream = null
	_update_campaign_atmosphere(0.0, 0.0, true)
	if _campaign_objective and is_instance_valid(_campaign_objective):
		_campaign_objective.queue_free()
	_campaign_objective = null


func _setup_campaign_clear_dialog() -> void:
	if _campaign_clear_dialog:
		return
	_campaign_clear_dialog = ConfirmationDialog.new()
	_campaign_clear_dialog.title = "關卡完成"
	_campaign_clear_dialog.dialog_text = ""
	_campaign_clear_dialog.ok_button_text = "回主頁"
	_campaign_clear_dialog.cancel_button_text = "再來一次"
	_campaign_clear_dialog.unresizable = true
	add_child(_campaign_clear_dialog)
	_campaign_clear_dialog.confirmed.connect(_on_campaign_clear_back_to_menu)
	_campaign_clear_dialog.canceled.connect(_on_campaign_clear_restart)


func _show_campaign_clear() -> void:
	if not _campaign_clear_dialog:
		return
	var meta_changed := false
	# Unlock Golden Singularity for purchase (it will appear in Upgrades -> Maps).
	if not meta_campaign_cleared:
		meta_campaign_cleared = true
		meta_changed = true
	# Unlock next campaign level (progression is linear).
	if game_mode == GameMode.CAMPAIGN:
		if campaign_level_id >= 1 and campaign_level_id <= CAMPAIGN_LEVEL_COUNT:
			if campaign_level_id == meta_campaign_max_unlocked and meta_campaign_max_unlocked < CAMPAIGN_LEVEL_COUNT:
				meta_campaign_max_unlocked += 1
				meta_changed = true
	if meta_changed:
		_save_meta()
		_refresh_maps_ui()
	# Pause the run while the clear dialog is visible.
	_revive_prompt_open = false
	is_game_over = true
	# Stop spawning and player control while the dialog is open.
	if _spawn_mgr:
		_spawn_mgr.stop_timers()
	_stop_map_event()
	var player_controller = get_node_or_null("PlayerController")
	if player_controller:
		player_controller.set_physics_process(false)
	var black_hole = %BlackHole
	if black_hole:
		black_hole.set_process(false)
		black_hole.set_physics_process(false)
		if black_hole.has_method("disable_fullscreen_distort"):
			black_hole.disable_fullscreen_distort()
	_campaign_clear_dialog.title = "關卡完成"
	_campaign_clear_dialog.dialog_text = "恭喜過關！"
	_campaign_clear_dialog.ok_button_text = "回主頁"
	_campaign_clear_dialog.cancel_button_text = "再來一次"
	_campaign_clear_dialog.popup_centered(Vector2i(520, 240))


func _on_campaign_clear_restart() -> void:
	if _campaign_clear_dialog:
		_campaign_clear_dialog.hide()
	# Restart the same campaign level.
	is_game_over = false
	_start_game()


func _on_campaign_clear_back_to_menu() -> void:
	if _campaign_clear_dialog:
		_campaign_clear_dialog.hide()
	_clear_campaign_runtime()
	_enter_main_menu()


func _on_campaign_objective_swallowed(objective_id: StringName) -> void:
	if game_mode != GameMode.CAMPAIGN:
		return
	if String(objective_id) == "golden_core" and _campaign_reached_lv7:
		_show_campaign_clear()


func _maybe_apply_trial_skin_for_run() -> void:
	# Try before you buy：每局小機率試用未解鎖 skin（不解鎖，只是當局外觀）
	_trial_skin_id = ""
	if randf() > clampf(trial_skin_chance, 0.0, 1.0):
		return
	_reload_skin_defs_from_folder()
	var locked: Array[String] = []
	for k in _skin_defs.keys():
		var id: String = String(k)
		if id == "classic":
			continue
		var unlocked := meta_unlocked_skins.has(id) and bool(meta_unlocked_skins[id])
		if not unlocked:
			locked.append(id)
	if locked.is_empty():
		return
	_trial_skin_id = locked[randi() % locked.size()]
	var def: Dictionary = _skin_defs.get(_trial_skin_id, {}) as Dictionary
	if def.is_empty():
		_trial_skin_id = ""
		return
	var tex: Texture2D = def.get("texture") as Texture2D
	var black_hole = %BlackHole
	if black_hole and black_hole.has_method("apply_skin_texture") and tex:
		black_hole.apply_skin_texture(tex)
		_show_toast("本局試用：%s" % _trial_skin_id, Color(0.6, 1, 0.9))


func _setup_emp_reward_dialog() -> void:
	if _emp_reward_dialog:
		return
	_emp_reward_dialog = AcceptDialog.new()
	_emp_reward_dialog.title = "觀看廣告"
	_emp_reward_dialog.dialog_text = "選擇獎勵："
	# 兩個獎勵按鈕（custom_action）
	_emp_reward_dialog.add_button("清場", false, "REWARD_CLEAR")
	_emp_reward_dialog.add_button("延長時間", false, "REWARD_TIME")
	add_child(_emp_reward_dialog)
	_emp_reward_dialog.custom_action.connect(_on_emp_reward_selected)


func _on_powerup_collected(powerup_type: StringName) -> void:
	if _spawn_mgr:
		_spawn_mgr.on_powerup_collected(powerup_type)
	# 任務追蹤
	if has_node("/root/MissionManager"):
		get_node("/root/MissionManager").report_powerup_collected()
	match powerup_type:
		&"MAGNET":
			_show_toast("磁力啟動！", Color(1, 0.4, 0.8))
		&"HOURGLASS":
			_show_toast("時間凍結！", Color(0.3, 0.9, 1))
		&"SHIELD":
			_show_toast("護盾啟動！ 8秒免傷", Color(0.3, 0.6, 1))
		&"SCORE_BOOST":
			_show_toast("雙倍得分！ 10秒", Color(1, 0.85, 0.2))

# ----------------------------------------------------
# 遊戲主循環
# ----------------------------------------------------
func _process(delta):
	if not game_started:
		return
	if is_game_over:
		return
	
	# 1. 相機追蹤與縮放
	if camera and %BlackHole:
		# 使用 delta-based smoothing，避免掉幀/卡頓時相機一跳一跳造成「瞬移感」
		var t_follow := 1.0 - exp(-8.0 * delta)
		camera.global_position = camera.global_position.lerp(%BlackHole.global_position, t_follow)
		_update_camera_zoom(delta) 
		_update_camera_shake(delta)
		_update_background()
		# Dynamic BGM pitch disabled (temporarily commented out)
		# _update_dynamic_audio(delta)
		_update_wanted_overlay(delta)
		_update_fever_combo_ui()

	# Swallow combo timer
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_count = 0
			_update_combo_ui()

	# Timer + wanted progression must update every frame.
	_update_timer_and_wanted(delta)

	# 地圖事件 process
	if _map_event_manager:
		_map_event_manager.process_event(delta)

	# Campaign win checks that are not tied to a single signal.
	if game_mode == GameMode.CAMPAIGN:
		_check_campaign_progress()
		_update_campaign_guidance_and_pacing(delta)
	else:
		_update_campaign_guidance_and_pacing(delta)


func _update_campaign_guidance_and_pacing(delta: float) -> void:
	# Hide by default.
	if objective_arrow and is_instance_valid(objective_arrow):
		objective_arrow.visible = false
	if campaign_gold_overlay and is_instance_valid(campaign_gold_overlay):
		var fog0 := _get_campaign_fog_color(campaign_level_id)
		var a0 := lerpf(campaign_gold_overlay.color.a, 0.0, 1.0 - exp(-6.0 * delta))
		campaign_gold_overlay.color = Color(fog0.r, fog0.g, fog0.b, a0)
	_update_campaign_atmosphere(delta, 0.0, true)

	if not game_started or is_game_over:
		return
	if game_mode != GameMode.CAMPAIGN:
		return
	if not _campaign_reached_lv7:
		return
	if not camera or not %BlackHole:
		return
	if not _campaign_objective or not is_instance_valid(_campaign_objective):
		return

	var bh := %BlackHole
	var target_world: Vector2 = _campaign_objective.global_position
	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 2.0 or vp.y <= 2.0:
		return

	# Proximity-driven golden atmosphere.
	var dist: float = (bh.global_position - _campaign_center).length()
	var max_r: float = maxf(600.0, _campaign_vortex_max_radius)
	var proximity: float = clampf(1.0 - (dist / max_r), 0.0, 1.0)
	_update_campaign_atmosphere(delta, proximity, false)
	if campaign_gold_overlay and is_instance_valid(campaign_gold_overlay):
		var a_target: float = clampf(campaign_gold_overlay_max_alpha * proximity, 0.0, campaign_gold_overlay_max_alpha)
		var fog := _get_campaign_fog_color(campaign_level_id)
		var a1 := lerpf(campaign_gold_overlay.color.a, a_target, 1.0 - exp(-6.0 * delta))
		campaign_gold_overlay.color = Color(fog.r, fog.g, fog.b, a1)

	# Edge arrow pointing to the Golden Core when it's off-screen.
	var target_screen: Vector2 = _world_to_screen(target_world)
	var safe_margin: float = clampf(campaign_guidance_edge_margin_px, 24.0, 160.0)
	var safe_rect := Rect2(Vector2.ZERO, vp).grow(-safe_margin)
	var on_screen: bool = safe_rect.has_point(target_screen)
	if objective_arrow and is_instance_valid(objective_arrow) and not on_screen:
		var screen_center: Vector2 = vp * 0.5
		var dir: Vector2 = (target_screen - screen_center)
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
		else:
			dir = dir.normalized()
		var half_w: float = vp.x * 0.5 - safe_margin
		var half_h: float = vp.y * 0.5 - safe_margin
		var tx: float = INF
		var ty: float = INF
		if absf(dir.x) > 0.0001:
			tx = half_w / absf(dir.x)
		if absf(dir.y) > 0.0001:
			ty = half_h / absf(dir.y)
		var t: float = minf(tx, ty)
		if not is_finite(t):
			t = minf(half_w, half_h)
		var arrow_center: Vector2 = screen_center + dir * t
		objective_arrow.visible = true
		objective_arrow.rotation = dir.angle()
		# Use helper if present (ObjectiveArrow.gd), else fallback.
		if objective_arrow.has_method("set_center_position"):
			objective_arrow.call("set_center_position", arrow_center)
		else:
			objective_arrow.position = arrow_center

	# More obstacles near the core: spawn extra enemies as you get closer.
	if not campaign_extra_enemy_spawn_enabled:
		return
	if proximity < campaign_extra_enemy_min_proximity:
		_campaign_extra_enemy_accum = 0.0
		return
	_campaign_extra_enemy_accum += delta
	var interval: float = lerpf(campaign_extra_enemy_max_interval, campaign_extra_enemy_min_interval, proximity)
	interval = clampf(interval, campaign_extra_enemy_min_interval, campaign_extra_enemy_max_interval)
	if _campaign_extra_enemy_accum < interval:
		return
	_campaign_extra_enemy_accum = 0.0
	_spawn_campaign_center_enemy(proximity)


func _world_to_screen(world_pos: Vector2) -> Vector2:
	# Godot 4: Camera2D does not provide `unproject_position`.
	# Use the viewport's canvas transform (includes Camera2D offset/zoom) to map world -> screen.
	return get_viewport().get_canvas_transform() * world_pos


func _spawn_campaign_center_enemy(proximity: float) -> void:
	if _spawn_mgr:
		_spawn_mgr.spawn_campaign_center_enemy(_campaign_center, proximity)


func _update_background() -> void:
	# 背景視差：使用初始位置與相機偏移計算，避免受父節點影響
	if not camera or not background_node:
		return
	var cam_offset = camera.global_position - _camera_origin
	var offset = cam_offset * parallax_strength
	# 最穩定的無限背景：重複貼圖的大型 region sprite
	if _bg_repeat_sprite:
		# 背景永遠置中在鏡頭，避免任何情況露底；視差改用滾動 region_rect 來呈現。
		_bg_repeat_sprite.global_position = camera.global_position
		# 依照 viewport 與 zoom 動態擴大 region，確保永遠覆蓋
		var vp_size = get_viewport_rect().size
		# Godot Camera2D.zoom：值越小顯示範圍越大，所以可視世界尺寸應該是 vp / zoom
		var z = camera.zoom
		var world_vp = Vector2(vp_size.x / max(0.001, z.x), vp_size.y / max(0.001, z.y))
		var buffer: float = 3.0
		var sx: float = max(0.001, absf(_bg_repeat_sprite.scale.x))
		var sy: float = max(0.001, absf(_bg_repeat_sprite.scale.y))
		var w: float = (world_vp.x * buffer) / sx
		var h: float = (world_vp.y * buffer) / sy
		var max_region: float = 50000.0
		w = minf(w, max_region)
		h = minf(h, max_region)
		# 視差：滾動取樣的 region（region_rect 的座標是貼圖像素空間，所以要除以 scale）
		var scroll = Vector2(offset.x / sx, offset.y / sy)
		_bg_repeat_sprite.region_rect = Rect2(Vector2(-w * 0.5, -h * 0.5) + scroll, Vector2(w, h))
		return
	# 如果使用 ParallaxBackground，直接更新它的 base offset
	if _parallax_bg:
		# 使用相對於背景原點的攝影機偏移作為 scroll offset（乘上 parallax_strength）
		var rel_cam = camera.global_position - _bg_origin
		_parallax_bg.scroll_base_offset = rel_cam * parallax_strength
		return
	# 使用 3x3 磁磚池時，動態重排磁磚以維持覆蓋
	if _bg_tiles_parent and _bg_tile_size.x > 0 and _bg_tile_size.y > 0 and _bg_tiles.size() > 0:
		_update_tile_pool(camera.global_position)
		return
	# 後備：直接移動原背景
	background_node.global_position = _bg_origin - offset


func _is_fever_active() -> bool:
	var bh = %BlackHole
	if bh and bh.has_method("is_fever_active"):
		return bool(bh.call("is_fever_active"))
	return false


func _update_fever_combo_ui() -> void:
	if not fever_bar or not is_instance_valid(fever_bar):
		return
	fever_bar.max_value = float(max(1, fever_combo_required))
	# Adjust for roguelike fever threshold reduction
	var rum_node_fever = get_node_or_null("/root/RoguelikeUpgradeManager")
	if rum_node_fever and rum_node_fever.has_method("get_modifier"):
		var reduced: int = max(3, fever_combo_required - int(rum_node_fever.get_modifier("fever_threshold_reduction")))
		fever_bar.max_value = float(max(1, reduced))
	if _is_fever_active():
		fever_bar.visible = true
		fever_bar.max_value = maxf(0.001, _fever_duration)
		fever_bar.value = clampf(_fever_time_left, 0.0, _fever_duration)
		return
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var active: bool = _fever_combo_count > 0 and (now_sec - _fever_combo_last_sec) <= fever_combo_chain_window_sec
	fever_bar.visible = active
	fever_bar.value = float(_fever_combo_count)
	if not active:
		fever_bar.value = 0.0
		# 不要一直重置 last_sec，避免短時間內重複閃爍


func _register_swallow_for_fever() -> void:
	if _is_fever_active():
		return
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	if (now_sec - _fever_combo_last_sec) <= fever_combo_chain_window_sec:
		_fever_combo_count += 1
	else:
		_fever_combo_count = 1
	_fever_combo_last_sec = now_sec
	_update_fever_combo_ui()
	# Apply roguelike fever threshold reduction (e.g. berserker character)
	var _effective_fever_required: int = fever_combo_required
	var rum_node = get_node_or_null("/root/RoguelikeUpgradeManager")
	if rum_node and rum_node.has_method("get_modifier"):
		_effective_fever_required = max(3, fever_combo_required - int(rum_node.get_modifier("fever_threshold_reduction")))
	if _fever_combo_count >= _effective_fever_required:
		_fever_combo_count = 0
		_fever_combo_last_sec = -9999.0
		var bh = %BlackHole
		if bh and bh.has_method("start_fever"):
			bh.call("start_fever")


func _on_black_hole_fever_started(duration: float) -> void:
	_fever_duration = maxf(0.001, duration)
	_fever_time_left = _fever_duration
	if _spawn_mgr:
		_spawn_mgr.set_fever_active(true)
	# 移速提升：透過 PlayerController 的 speed multiplier
	var pc = get_node_or_null("PlayerController")
	if pc and pc.has_method("apply_speed_multiplier"):
		var fever_mult: float = 1.5
		var bh = %BlackHole
		if bh and bh.has_method("get_fever_speed_multiplier"):
			fever_mult = float(bh.call("get_fever_speed_multiplier"))
		# Layer fever speed on top of roguelike + meta speed
		var base_speed: float = 1.0 + float(upgrade_speed_level) * 0.08
		var rum_speed = get_node_or_null("/root/RoguelikeUpgradeManager")
		if rum_speed and rum_speed.has_method("get_multiplier"):
			base_speed *= rum_speed.get_multiplier("move_speed_mult")
		pc.call("apply_speed_multiplier", base_speed * fever_mult)
	_show_toast("FEVER MODE!", Color(1.0, 0.92, 0.35))
	_flash_screen(Color(1.0, 0.92, 0.35), 0.18, 0.22)
	_start_shake(0.16, 8.0)
	Input.vibrate_handheld(28)
	_update_fever_combo_ui()


func _on_black_hole_fever_changed(time_remaining: float, duration: float) -> void:
	_fever_time_left = maxf(0.0, time_remaining)
	_fever_duration = maxf(0.001, duration)
	_update_fever_combo_ui()


func _on_black_hole_fever_ended() -> void:
	_fever_time_left = 0.0
	if _spawn_mgr:
		_spawn_mgr.set_fever_active(false)
	# Restore proper speed (meta + roguelike modifiers) instead of resetting to 1.0
	_apply_roguelike_speed()
	_update_fever_combo_ui()
	_hide_enemy_combo_label()


var _enemy_combo_label: Label = null
var _enemy_combo_tween: Tween = null


func _ensure_enemy_combo_ui() -> void:
	if _enemy_combo_label and is_instance_valid(_enemy_combo_label):
		return
	var hud_node := get_node_or_null("%HUD") as Control
	if not hud_node:
		return
	_enemy_combo_label = Label.new()
	_enemy_combo_label.name = "EnemyComboLabel"
	_enemy_combo_label.visible = false
	_enemy_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_enemy_combo_label.add_theme_font_size_override("font_size", 86)
	_enemy_combo_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_enemy_combo_label.add_theme_constant_override("outline_size", 10)
	_enemy_combo_label.modulate = Color(1.0, 0.92, 0.35, 0.0)
	_enemy_combo_label.scale = Vector2.ONE
	hud_node.add_child(_enemy_combo_label)


func _hide_enemy_combo_label() -> void:
	if _enemy_combo_tween and _enemy_combo_tween.is_valid():
		_enemy_combo_tween.kill()
		_enemy_combo_tween = null
	if _enemy_combo_label and is_instance_valid(_enemy_combo_label):
		_enemy_combo_label.visible = false
		_enemy_combo_label.modulate.a = 0.0


func _on_black_hole_fever_enemy_combo(combo: int, world_pos: Vector2) -> void:
	# Big rhythmic “X1/X2…” pop + small shake.
	if not camera:
		return
	_ensure_enemy_combo_ui()
	if not _enemy_combo_label or not is_instance_valid(_enemy_combo_label):
		return

	combo = int(max(1, combo))
	_enemy_combo_label.text = "X%d" % combo
	_enemy_combo_label.visible = true
	# Taiko-ish ramp: yellow -> orange -> hot pink, brighter as combo grows.
	var t: float = clampf(float(combo - 1) / 10.0, 0.0, 1.0)
	var c0 := Color(1.0, 0.92, 0.35, 0.0)
	var c1 := Color(1.0, 0.45, 0.18, 0.0)
	var c2 := Color(1.0, 0.2, 0.75, 0.0)
	var cc := c0.lerp(c1, clampf(t * 1.2, 0.0, 1.0)).lerp(c2, clampf((t - 0.45) * 2.0, 0.0, 1.0))
	_enemy_combo_label.modulate = cc
	_enemy_combo_label.scale = Vector2.ONE * 0.12

	# Place near the black hole in screen space.
	var screen_pos: Vector2 = _world_to_screen(world_pos)
	# Add a tiny random offset for punch.
	screen_pos += Vector2(randf_range(-22.0, 22.0), randf_range(-22.0, 22.0))
	var sz: Vector2 = _enemy_combo_label.get_minimum_size()
	_enemy_combo_label.size = sz
	_enemy_combo_label.position = screen_pos - sz * 0.5

	# Rhythm: quick shake, stronger with combo.
	var s: float = clampf(5.5 + float(combo) * 0.8, 5.5, 12.0)
	_start_shake(0.08, s)
	Input.vibrate_handheld(int(clampf(12.0 + float(combo) * 2.2, 12.0, 30.0)))

	if _enemy_combo_tween and _enemy_combo_tween.is_valid():
		_enemy_combo_tween.kill()
		_enemy_combo_tween = null
	_enemy_combo_tween = create_tween()
	_enemy_combo_tween.tween_property(_enemy_combo_label, "modulate:a", 1.0, 0.04).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Pop hard then settle.
	var peak: float = clampf(1.35 + float(combo) * 0.03, 1.35, 1.65)
	_enemy_combo_tween.parallel().tween_property(_enemy_combo_label, "scale", Vector2.ONE * peak, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Punch upward slightly (rhythm).
	var p0: Vector2 = _enemy_combo_label.position
	var up: float = clampf(18.0 + float(combo) * 1.2, 18.0, 34.0)
	_enemy_combo_tween.parallel().tween_property(_enemy_combo_label, "position", p0 + Vector2(0, -up), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_enemy_combo_tween.tween_property(_enemy_combo_label, "scale", Vector2.ONE * 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_enemy_combo_tween.parallel().tween_property(_enemy_combo_label, "position", p0 + Vector2(0, -up * 0.6), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_enemy_combo_tween.tween_interval(0.14)
	_enemy_combo_tween.tween_property(_enemy_combo_label, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_enemy_combo_tween.finished.connect(func() -> void:
		if _enemy_combo_label and is_instance_valid(_enemy_combo_label):
			_enemy_combo_label.visible = false
	)


# ---- Swallow Combo UI ----
func _ensure_combo_ui() -> void:
	if _combo_label and is_instance_valid(_combo_label):
		return
	var hud_node := get_node_or_null("%HUD") as Control
	if not hud_node:
		return
	_combo_label = Label.new()
	_combo_label.name = "SwallowComboLabel"
	_combo_label.visible = false
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 42)
	_combo_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_combo_label.add_theme_constant_override("outline_size", 6)
	_combo_label.modulate = Color(0.4, 1.0, 0.9, 1.0)
	# Position in top-right area, below score
	_combo_label.anchor_left = 1.0
	_combo_label.anchor_right = 1.0
	_combo_label.anchor_top = 0.0
	_combo_label.anchor_bottom = 0.0
	_combo_label.offset_left = -260.0
	_combo_label.offset_right = -16.0
	_combo_label.offset_top = 80.0
	_combo_label.offset_bottom = 120.0
	hud_node.add_child(_combo_label)


func _update_combo_ui() -> void:
	_ensure_combo_ui()
	if not _combo_label or not is_instance_valid(_combo_label):
		return
	if _combo_count <= 1:
		_combo_label.visible = false
		return
	var mult: float = COMBO_MULTIPLIERS[mini(_combo_count, COMBO_MULTIPLIERS.size() - 1)]
	_combo_label.text = "COMBO x%d (%.1f倍)" % [_combo_count, mult]
	_combo_label.visible = true
	# Color ramp: cyan → yellow → hot red
	var t: float = clampf(float(_combo_count - 1) / 4.0, 0.0, 1.0)
	var col := Color(0.4, 1.0, 0.9).lerp(Color(1.0, 1.0, 0.3), clampf(t * 2.0, 0.0, 1.0))
	col = col.lerp(Color(1.0, 0.3, 0.2), clampf((t - 0.5) * 2.0, 0.0, 1.0))
	# Pulse animation
	if _combo_tween and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_tween = create_tween()
	_combo_label.modulate = Color(col.r, col.g, col.b, 1.0)
	_combo_label.scale = Vector2(1.3, 1.3)
	_combo_tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_shockwave_button_pressed() -> void:
	var bh = %BlackHole
	if not bh or not bh.has_method("trigger_shockwave"):
		_show_toast("衝擊波不可用", Color(1, 0.6, 0.6))
		return
	var ok: bool = bool(bh.call("trigger_shockwave"))
	if not ok:
		_show_toast("穩定度不足：無法釋放衝擊波", Color(1, 0.6, 0.6))
	else:
		_run_shockwave_count += 1
		if has_node("/root/MissionManager"):
			get_node("/root/MissionManager").report_shockwave_used()

func _update_wanted_overlay(delta: float) -> void:
	if not wanted_overlay or not is_instance_valid(wanted_overlay):
		return
	# 取消 Wanted 的「持續閃紅」效果：只保留一次性的提示（例如 wanted 升級時的 flash）。
	# 這裡永遠朝 0 淡出。
	wanted_overlay.color.a = lerpf(wanted_overlay.color.a, 0.0, 1.0 - exp(-8.0 * delta))


func _update_timer_and_wanted(delta: float) -> void:
	# 遊戲計時（沙漏：暫停倒數）
	if _spawn_mgr and _spawn_mgr.hourglass_time_left > 0.0:
		_spawn_mgr.hourglass_time_left -= delta
		if _spawn_mgr.hourglass_time_left <= 0.0:
			_spawn_mgr.hourglass_time_left = 0.0
			_spawn_mgr.hourglass_active = false
			_spawn_mgr.set_combat_frozen(false)
	else:
		time_left -= delta
	_update_time_ui()
	if game_mode != GameMode.ENDLESS and time_left <= 0:
		_game_over("TIME_LIMIT_EXCEEDED")
		return
	# 任務：存活秒數追蹤
	if has_node("/root/MissionManager"):
		var survived: int = int(game_duration - time_left)
		get_node("/root/MissionManager").report_survive_time(survived)
	# 通緝等級檢查
	_check_wanted_level()


func _physics_process(delta):
	if not game_started or is_game_over:
		return
	# 地圖事件 physics process
	if _map_event_manager:
		_map_event_manager.physics_process_event(delta)
	# Campaign: vortex current (enabled after Lv.7 milestone)
	if game_mode == GameMode.CAMPAIGN and _campaign_vortex_enabled:
		_apply_campaign_vortex(delta)
	# 磁鐵：10 秒內把「看得到的獵物」都吸進來
	if _spawn_mgr and _spawn_mgr.magnet_time_left > 0.0:
		_spawn_mgr.magnet_time_left -= delta
		var bh = %BlackHole
		if bh and camera:
			var vp = get_viewport_rect().size
			var z = camera.zoom
			var world_size = Vector2(vp.x / max(0.001, z.x), vp.y / max(0.001, z.y))
			var view_rect = Rect2(camera.global_position - world_size * 0.5, world_size)
			for prey in _get_cached_group("Prey"):
				if not is_instance_valid(prey):
					continue
				if not (prey is RigidBody2D):
					continue
				if not view_rect.has_point(prey.global_position):
					continue
				var dir = (bh.global_position - prey.global_position)
				var dist = max(50.0, dir.length())
				var force = dir.normalized() * magnet_strength * (1.0 / (dist / 200.0))
				(prey as RigidBody2D).apply_central_force(force * delta * 60.0)

	# Shield timer
	if _spawn_mgr and _spawn_mgr.shield_time_left > 0.0:
		_spawn_mgr.shield_time_left -= delta
		if _spawn_mgr.shield_time_left <= 0.0:
			_spawn_mgr.shield_time_left = 0.0
			var bh2 = %BlackHole
			if bh2 and bh2.has_method("set_shield_active"):
				bh2.set_shield_active(false)

	# Score boost timer (multiplier applied in _on_swallowed)
	if _spawn_mgr and _spawn_mgr.score_boost_time_left > 0.0:
		_spawn_mgr.score_boost_time_left -= delta
		if _spawn_mgr.score_boost_time_left <= 0.0:
			_spawn_mgr.score_boost_time_left = 0.0

	# Roguelike: passive magnet effect
	_apply_roguelike_passive_magnet(delta)


func _apply_campaign_vortex(delta: float) -> void:
	var center := _campaign_center
	var max_r := maxf(200.0, _campaign_vortex_max_radius)
	var tang := _campaign_vortex_tangential_strength
	var rad := _campaign_vortex_radial_strength
	# Affect common dynamic bodies only.
	var groups := ["Prey", "Enemies", "EnemyProjectiles", "Swallowables"]
	for g in groups:
		for n in _get_cached_group(g):
			if not is_instance_valid(n):
				continue
			if not (n is RigidBody2D):
				continue
			var b := n as RigidBody2D
			var to_center := center - b.global_position
			var d := to_center.length()
			if d > max_r:
				continue
			var dir := (to_center / d) if d > 0.001 else Vector2.RIGHT
			var tdir := dir.orthogonal()
			var falloff := clampf(1.0 - (d / max_r), 0.0, 1.0)
			# Stronger near the center.
			var f := (dir * rad + tdir * tang) * (0.35 + 0.65 * falloff)
			b.apply_central_force(f * delta * 60.0)


func _check_campaign_progress() -> void:
	var bh = %BlackHole
	if not bh:
		return
	# Combined campaign level:
	# - Reach Lv.7 once to spawn objective + enable vortex.
	# - Reach Lv.10 and swallow objective to clear (handled by objective signal).
	if not _campaign_reached_lv7 and int(bh.current_level) >= 7:
		_campaign_reached_lv7 = true
		_campaign_vortex_enabled = true
		_spawn_golden_core_objective()
		_show_toast("目標出現：達到 Lv.10 後吞噬黃金核心", Color(1.0, 0.92, 0.35))

func _update_time_ui():
	if time_label:
		if game_mode == GameMode.ENDLESS:
			# Endless: show elapsed time instead of countdown
			var elapsed: float = game_duration - time_left
			var total_seconds = int(elapsed)
			var mins = int(total_seconds / 60.0)
			var secs = total_seconds % 60
			time_label.text = "存活: %02d:%02d" % [mins, secs]
			time_label.modulate = Color(0.3, 1.0, 0.6)
		else:
			var total_seconds = int(time_left)
			var mins = int(total_seconds / 60.0)
			var secs = total_seconds % 60
			time_label.text = "限時: %02d:%02d" % [mins, secs]
			if time_left < 10:
				time_label.modulate = Color.RED
			else:
				time_label.modulate = Color.WHITE

# ----------------------------------------------------
# 攝影機動態縮放
# ----------------------------------------------------
func _update_camera_zoom(delta):
	var black_hole = %BlackHole
	if not black_hole: return
	
	# 根據黑洞等級計算縮放值
	var target_zoom_val = 1.0 / (1.0 + (black_hole.current_level * 0.08))
	target_zoom_val = clamp(target_zoom_val, 0.3, 1.0)
	
	var target_zoom = Vector2(target_zoom_val, target_zoom_val)
	# 平滑縮放：使用 exp smoothing，避免升級瞬間覺得背景/畫面跳動
	var t_zoom := 1.0 - exp(-3.0 * delta)
	camera.zoom = camera.zoom.lerp(target_zoom, t_zoom)

# ----------------------------------------------------
# 生成邏輯
# ----------------------------------------------------

func _apply_enemy_stage_to_all(stage: int) -> void:
	if _spawn_mgr:
		_spawn_mgr.apply_enemy_stage_to_all(stage)

# ----------------------------------------------------
# 訊號處理
# ----------------------------------------------------
func _on_swallowed(score_gain):
	if score_gain > 0:
		# Combo multiplier: rapid swallows increase score
		# Roguelike: combo_window_bonus extends the combo window
		var combo_window: float = COMBO_WINDOW
		if has_node("/root/RoguelikeUpgradeManager"):
			combo_window += get_node("/root/RoguelikeUpgradeManager").get_modifier("combo_window_bonus")
		if _combo_timer > 0.0:
			_combo_count = mini(_combo_count + 1, COMBO_MULTIPLIERS.size() - 1)
		else:
			_combo_count = 1
		_combo_timer = combo_window
		var mult: float = COMBO_MULTIPLIERS[mini(_combo_count, COMBO_MULTIPLIERS.size() - 1)]
		# Score boost powerup doubles score
		if _spawn_mgr and _spawn_mgr.score_boost_time_left > 0.0:
			mult *= 2.0
		# Roguelike: score_mult modifier
		if has_node("/root/RoguelikeUpgradeManager"):
			var rum = get_node("/root/RoguelikeUpgradeManager")
			mult *= rum.get_multiplier("score_mult")
			# Roguelike: double_score_chance
			var dsc: float = rum.get_modifier("double_score_chance")
			if dsc > 0.0 and randf() < dsc:
				mult *= 2.0
		var boosted: int = int(ceil(float(score_gain) * mult))
		current_score += boosted
		# Roguelike: swallow_time_bonus adds time per swallow
		if has_node("/root/RoguelikeUpgradeManager"):
			var time_bonus: float = get_node("/root/RoguelikeUpgradeManager").get_modifier("swallow_time_bonus")
			if time_bonus > 0.0:
				time_left += time_bonus
		_update_combo_ui()
		Events.combo_updated.emit(_combo_count, mult)
		# 任務追蹤
		if has_node("/root/MissionManager"):
			var msm: Node = get_node("/root/MissionManager")
			msm.report_swallow(1)
			msm.report_combo(_combo_count)
	
	_update_score_ui()
	
func _on_level_up(lv):
	if level_label: level_label.text = "核心等級：Lv.%d" % lv
	_show_toast("核心等級提升：Lv.%d" % lv, Color(0.2, 1, 1))
	if sfx_level_up:
		sfx_level_up.play()
	# 任務追蹤
	if has_node("/root/MissionManager"):
		get_node("/root/MissionManager").report_level_reached(int(lv))
	
	# 後期不要加速過頭，避免畫面物件數爆炸
	if _spawn_mgr:
		_spawn_mgr.spawn_rate = max(0.35, _spawn_mgr.spawn_rate * 0.97)
		if _spawn_mgr.spawn_timer:
			_spawn_mgr.spawn_timer.wait_time = _spawn_mgr.spawn_rate

	# Roguelike: show upgrade selection (pause game)
	_show_roguelike_upgrade_selection(int(lv))

func _on_max_level():
	if level_label:
		level_label.text = "★ 最終型態 ★"
		level_label.modulate = Color(2, 0, 0)
		level_label.scale = Vector2(3, 3)

func _on_stability_changed(curr, max_val):
	if stability_bar:
		# 這裡的 value 應該是 (curr / max_val) * max_value，ProgressBar 會自動處理百分比
		stability_bar.value = curr
		stability_bar.max_value = max_val # 確保 max_value 是正確的
		
		var percent = curr / max_val
		if percent < 0.3:
			stability_bar.modulate = Color(1, 0, 0)
		else:
			stability_bar.modulate = Color(0, 1, 1)

func _on_entropy_death():
	# 死亡時提供一次性看廣告復活
	if not _revive_used:
		_prompt_revive_once()
		return
	_game_over("ENTROPY_COLLAPSE")

# ----------------------------------------------------
# Boss 系統
# ----------------------------------------------------
func _on_boss_defeated() -> void:
	"""SpawnManager 回呼：Boss 被擊敗"""
	# 獎勵：大量分數 + 穩定度回復
	var score_bonus: int = int(GameConfig.BOSS_SCORE_VALUE)
	current_score += score_bonus
	_update_score_ui()
	var black_hole := %BlackHole
	if black_hole:
		black_hole.current_stability = minf(
			black_hole.current_stability + GameConfig.BOSS_STABILITY_REWARD,
			black_hole.max_stability)
		black_hole.stability_changed.emit(black_hole.current_stability, black_hole.max_stability)
	_show_toast("BOSS 擊敗！+%d 分" % score_bonus, Color(1.0, 0.85, 0.2))
	_flash_screen(Color(1.0, 0.9, 0.3), 0.6, 0.3)
	_start_shake(0.3, 10.0)
	Input.vibrate_handheld(60)
	_hide_boss_hp_bar()
	# 任務追蹤
	_run_enemies_killed += 1
	if has_node("/root/MissionManager"):
		var msm: Node = get_node("/root/MissionManager")
		msm.report_boss_defeated()
		msm.report_enemy_killed(1)

func _on_boss_hp_changed(current_hp: float, max_hp: float) -> void:
	"""SpawnManager 回呼：Boss HP 變化"""
	if _boss_hp_bar:
		_boss_hp_bar.value = current_hp
		_boss_hp_bar.max_value = max_hp
	if _boss_hp_label:
		_boss_hp_label.text = "BOSS  %d / %d" % [int(current_hp), int(max_hp)]

func _on_enemy_killed() -> void:
	"""BlackHole 回呼：Fever 吞噬敵人"""
	_run_enemies_killed += 1
	if has_node("/root/MissionManager"):
		get_node("/root/MissionManager").report_enemy_killed(1)

# ----------------------------------------------------
# 任務 UI（嵌入設定視窗）
# ----------------------------------------------------
func _rebuild_settings_missions() -> void:
	"""重建設定視窗內的任務列表"""
	_mission_items.clear()
	if not _settings_mission_container or not is_instance_valid(_settings_mission_container):
		return
	# 清除舊子節點
	for c in _settings_mission_container.get_children():
		c.queue_free()

	if not has_node("/root/MissionManager"):
		return
	var msm: Node = get_node("/root/MissionManager")
	var missions: Array = msm.get_all_active_missions()
	if missions.is_empty():
		var empty_label := Label.new()
		empty_label.text = "（今日無任務）"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 18)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_settings_mission_container.add_child(empty_label)
		return

	for m in missions:
		var item_hbox := HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 6)

		var tag_label := Label.new()
		var mid: String = String(m.get("id", ""))
		if mid.begins_with("daily"):
			tag_label.text = "[日]"
			tag_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		else:
			tag_label.text = "[局]"
			tag_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5))
		tag_label.add_theme_font_size_override("font_size", 18)
		item_hbox.add_child(tag_label)

		var desc_label := Label.new()
		desc_label.text = String(m.get("label", ""))
		desc_label.add_theme_font_size_override("font_size", 18)
		desc_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_hbox.add_child(desc_label)

		var progress_label := Label.new()
		var cur: int = int(m.get("current", 0))
		var tgt: int = int(m.get("target", 1))
		var completed: bool = bool(m.get("completed", false))
		if completed:
			progress_label.text = "✓"
			progress_label.add_theme_color_override("font_color", Color(0.2, 1, 0.4))
		else:
			progress_label.text = "%d/%d" % [cur, tgt]
			progress_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		progress_label.add_theme_font_size_override("font_size", 18)
		item_hbox.add_child(progress_label)

		_settings_mission_container.add_child(item_hbox)

		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = tgt
		bar.value = cur
		bar.show_percentage = false
		var fill_s := StyleBoxFlat.new()
		if completed:
			fill_s.bg_color = Color(0.2, 1, 0.4)
		elif mid.begins_with("daily"):
			fill_s.bg_color = Color(0.3, 0.8, 1.0)
		else:
			fill_s.bg_color = Color(0.4, 1.0, 0.5)
		fill_s.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill_s)
		var bg_s := StyleBoxFlat.new()
		bg_s.bg_color = Color(0.15, 0.15, 0.15, 0.9)
		bg_s.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", bg_s)
		_settings_mission_container.add_child(bar)

		if completed:
			desc_label.add_theme_color_override("font_color", Color(0.2, 1, 0.4))

		_mission_items.append({
			"id": mid,
			"label": desc_label,
			"progress": progress_label,
			"bar": bar,
			"hbox": item_hbox,
		})


func _update_mission_ui() -> void:
	"""更新任務面板中各項的進度"""
	if not has_node("/root/MissionManager"):
		return
	if _mission_items.is_empty():
		return
	var msm: Node = get_node("/root/MissionManager")
	var missions: Array = msm.get_all_active_missions()
	# 建立 id -> mission 字典方便查詢
	var mission_map: Dictionary = {}
	for m in missions:
		mission_map[String(m.get("id", ""))] = m

	for item in _mission_items:
		var mid: String = String(item.get("id", ""))
		if not mission_map.has(mid):
			# 已領取/移除
			if item.get("hbox") and is_instance_valid(item["hbox"]):
				item["hbox"].modulate = Color(0.5, 0.5, 0.5, 0.5)
			continue
		var m: Dictionary = mission_map[mid]
		var cur: int = int(m.get("current", 0))
		var tgt: int = int(m.get("target", 1))
		var completed: bool = bool(m.get("completed", false))
		# 更新進度文字
		if item.get("progress") and is_instance_valid(item["progress"]):
			if completed:
				(item["progress"] as Label).text = "✓"
				(item["progress"] as Label).add_theme_color_override("font_color", Color(0.2, 1, 0.4))
			else:
				(item["progress"] as Label).text = "%d/%d" % [cur, tgt]
				(item["progress"] as Label).add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		# 更新進度條
		if item.get("bar") and is_instance_valid(item["bar"]):
			(item["bar"] as ProgressBar).max_value = tgt
			(item["bar"] as ProgressBar).value = cur
			if completed:
				var fill_done := StyleBoxFlat.new()
				fill_done.bg_color = Color(0.2, 1, 0.4)
				fill_done.corner_radius_top_left = 3
				fill_done.corner_radius_top_right = 3
				fill_done.corner_radius_bottom_left = 3
				fill_done.corner_radius_bottom_right = 3
				(item["bar"] as ProgressBar).add_theme_stylebox_override("fill", fill_done)
		# 完成時高亮描述
		if completed and item.get("label") and is_instance_valid(item["label"]):
			(item["label"] as Label).add_theme_color_override("font_color", Color(0.2, 1, 0.4))


func _show_boss_hp_bar() -> void:
	if not _boss_hp_container:
		_create_boss_hp_bar()
	if _boss_hp_container:
		_boss_hp_container.visible = true
	if _boss_hp_bar:
		_boss_hp_bar.value = GameConfig.BOSS_MAX_HP
		_boss_hp_bar.max_value = GameConfig.BOSS_MAX_HP
	if _boss_hp_label:
		_boss_hp_label.text = "BOSS  %d / %d" % [int(GameConfig.BOSS_MAX_HP), int(GameConfig.BOSS_MAX_HP)]

func _hide_boss_hp_bar() -> void:
	if _boss_hp_container:
		_boss_hp_container.visible = false

func _create_boss_hp_bar() -> void:
	"""動態建立 Boss 血條 UI（掛在 HUD 下方）"""
	if not hud:
		return
	_boss_hp_container = PanelContainer.new()
	_boss_hp_container.name = "BossHPContainer"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.05, 0.05, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_boss_hp_container.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_boss_hp_container.add_child(vbox)

	_boss_hp_label = Label.new()
	_boss_hp_label.text = "BOSS"
	_boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hp_label.add_theme_font_size_override("font_size", 18)
	_boss_hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	vbox.add_child(_boss_hp_label)

	_boss_hp_bar = ProgressBar.new()
	_boss_hp_bar.custom_minimum_size = Vector2(280, 16)
	_boss_hp_bar.max_value = GameConfig.BOSS_MAX_HP
	_boss_hp_bar.value = GameConfig.BOSS_MAX_HP
	_boss_hp_bar.show_percentage = false
	# 紅色填充
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.85, 0.12, 0.1)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	_boss_hp_bar.add_theme_stylebox_override("fill", fill_style)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_left = 3
	bg_style.corner_radius_bottom_right = 3
	_boss_hp_bar.add_theme_stylebox_override("background", bg_style)
	vbox.add_child(_boss_hp_bar)

	hud.add_child(_boss_hp_container)
	# 嘗試定位在上方中央
	_boss_hp_container.anchors_preset = Control.PRESET_CENTER_TOP
	_boss_hp_container.position.y = 60.0
	_boss_hp_container.visible = false


func _setup_revive_dialog() -> void:
	if _revive_dialog:
		return
	_revive_dialog = ConfirmationDialog.new()
	_revive_dialog.title = "復活"
	_revive_dialog.dialog_text = "是否觀看廣告復活一次？"
	_revive_dialog.ok_button_text = "復活"
	_revive_dialog.cancel_button_text = "結束"
	add_child(_revive_dialog)
	_revive_dialog.confirmed.connect(_on_revive_confirmed)
	_revive_dialog.canceled.connect(_on_revive_declined)


func _setup_game_over_dialog() -> void:
	if _game_over_dialog:
		return
	_game_over_dialog = ConfirmationDialog.new()
	_game_over_dialog.title = ""
	_game_over_dialog.dialog_text = ""
	_game_over_dialog.ok_button_text = "再來一次"
	_game_over_dialog.cancel_button_text = "回主頁"
	_game_over_dialog.unresizable = true
	add_child(_game_over_dialog)
	_game_over_dialog.confirmed.connect(_on_game_over_restart)
	_game_over_dialog.canceled.connect(_on_game_over_back_to_menu)
	_game_over_dialog.visibility_changed.connect(_on_game_over_dialog_visibility_changed)


func _on_game_over_dialog_visibility_changed() -> void:
	# 避免用 X 關閉後卡死：關閉視窗也視為回主頁
	if _game_over_dialog and not _game_over_dialog.visible and is_game_over and not _revive_prompt_open:
		_on_game_over_back_to_menu()


func _on_game_over_restart() -> void:
	_restart_run()


func _on_game_over_back_to_menu() -> void:
	_return_to_menu()


func _clear_world() -> void:
	_clear_all_enemies()
	_clear_enemy_projectiles()
	for p in get_tree().get_nodes_in_group("Prey"):
		if is_instance_valid(p):
			p.queue_free()
	for pu in get_tree().get_nodes_in_group("PowerUps"):
		if is_instance_valid(pu):
			pu.queue_free()


func _reset_black_hole() -> void:
	var black_hole = %BlackHole
	if black_hole and black_hole.has_method("reset_for_new_run"):
		black_hole.reset_for_new_run()


func _restart_run() -> void:
	if _game_over_dialog:
		_game_over_dialog.hide()
	_clear_world()
	_reset_black_hole()
	# 重新開始：直接開局（不回主選單）
	_start_game()


func _return_to_menu() -> void:
	if _game_over_dialog:
		_game_over_dialog.hide()
	_clear_world()
	_reset_black_hole()
	_enter_main_menu()


func _prompt_revive_once() -> void:
	# 先凍結遊戲（不顯示結算文字），等玩家選擇
	if is_game_over:
		return
	_revive_prompt_open = true
	is_game_over = true
	if _spawn_mgr:
		_spawn_mgr.stop_timers()
	var player_controller = get_node_or_null("PlayerController")
	if player_controller:
		player_controller.set_physics_process(false)
	var black_hole = %BlackHole
	if black_hole:
		black_hole.set_process(false)
		black_hole.set_physics_process(false)
		if black_hole.has_method("disable_fullscreen_distort"):
			black_hole.disable_fullscreen_distort()
	if _revive_dialog:
		_revive_dialog.popup_centered()
	else:
		_on_revive_declined()


func _on_revive_confirmed() -> void:
	_revive_used = true
	_revive_prompt_open = false
	# 清掉場上威脅，避免復活瞬間再死
	_clear_all_enemies()
	_clear_enemy_projectiles()
	# 回復穩定度
	var black_hole = %BlackHole
	if black_hole and black_hole.has_method("revive_to_ratio"):
		black_hole.revive_to_ratio(revive_stability_ratio)
	# 恢復遊戲
	is_game_over = false
	if _spawn_mgr:
		_spawn_mgr.start_timers()
	var player_controller = get_node_or_null("PlayerController")
	if player_controller:
		player_controller.set_physics_process(true)
	var black_hole2 = %BlackHole
	if black_hole2:
		black_hole2.set_process(true)
		black_hole2.set_physics_process(true)
		if black_hole2.has_method("set_fullscreen_distort_enabled"):
			black_hole2.set_fullscreen_distort_enabled(gravity_ripple_enabled)


func _on_revive_declined() -> void:
	# 注意：不要先把 _revive_prompt_open 關掉，否則 _game_over 的 guard 會直接 return
	_game_over("ENTROPY_COLLAPSE")


func _clear_enemy_projectiles() -> void:
	if _spawn_mgr:
		_spawn_mgr.clear_enemy_projectiles()

# ----------------------------------------------------
# 通緝系統邏輯
# ----------------------------------------------------
func _check_wanted_level():
	if not game_started:
		return
	var black_hole = %BlackHole
	if not black_hole: return
	
	var new_wanted = 0
	# 通緝系統：5 波變化，均分在 Lv.10 內（Lv.1/3/5/7/9 對應 Wanted 1~5）
	var lv: int = int(black_hole.current_level)
	if lv >= 1: new_wanted = 1
	if lv >= 3: new_wanted = 2
	if lv >= 5: new_wanted = 3
	if lv >= 7: new_wanted = 4
	if lv >= 9: new_wanted = 5
	new_wanted = clampi(new_wanted, 0, 5)
	
	if new_wanted != wanted_level:
		var prev_wanted: int = wanted_level
		wanted_level = new_wanted
		if _spawn_mgr:
			_spawn_mgr.rebuild_enemy_stage_cycle(wanted_level)
			_spawn_mgr.update_enemy_spawning(wanted_level)
		_update_wanted_ui()
		if new_wanted > prev_wanted and new_wanted >= 1 and sfx_wanted_up:
			sfx_wanted_up.play()
			# Wanted 升級回饋：紅閃 + 輕震 + 震動（讓玩家知道進入生存波次）
			var a: float = clampf(float(new_wanted) / 5.0, 0.25, 0.75)
			_flash_screen(Color(1, 0.1, 0.1), a, 0.18)
			_start_shake(0.14, 4.0 + float(new_wanted) * 2.0)
			Input.vibrate_handheld(int(12 + new_wanted * 4))

	# Boss 觸發：通緝等級 5 時召喚 Boss
	if wanted_level >= GameConfig.BOSS_SPAWN_WANTED_LEVEL and _spawn_mgr and not _spawn_mgr.boss_spawned_this_run:
		var spawned: bool = _spawn_mgr.try_spawn_boss()
		if spawned:
			_show_toast("⚠ BOSS 出現！⚠", Color(1.0, 0.2, 0.1))
			_flash_screen(Color(1.0, 0.0, 0.0), 0.8, 0.4)
			_start_shake(0.5, 15.0)
			Input.vibrate_handheld(80)
			_show_boss_hp_bar()


func _hit_stop(duration: float, time_scale: float = 0.12) -> void:
	# 小停幀：強化吞噬「咬下去」的重量感
	_hit_stop_seq += 1
	var seq: int = _hit_stop_seq
	Engine.time_scale = clampf(time_scale, 0.05, 1.0)
	call_deferred("_restore_time_scale_after", seq, duration)


func _restore_time_scale_after(seq: int, duration: float) -> void:
	await get_tree().create_timer(max(0.01, duration), true, false, true).timeout
	if seq != _hit_stop_seq:
		return
	Engine.time_scale = 1.0


func _update_dynamic_audio(delta: float) -> void:
	# Dynamic BGM pitch feature disabled per request.
	# Previously updated `_music_player.pitch_scale` based on level/fever.
	return


func _update_wanted_ui():
	if not wanted_label: return
	
	var txt = "SECURITY: SAFE"
	var col = Color.GREEN
	
	match wanted_level:
		1: 
			txt = "WARNING: DETECTED"
			col = Color.YELLOW
		2: 
			txt = "ALERT: TRACING..."
			col = Color.ORANGE
		3: 
			txt = "DANGER: PURGE ACTIVE"
			col = Color.RED
		4: 
			txt = "CRITICAL: KILL ON SIGHT"
			col = Color.MAGENTA
		5:
			txt = "APOCALYPSE: EXTERMINATE"
			col = Color.WHITE * 2.0 # 閃爍白色
			
	wanted_label.text = txt
	wanted_label.modulate = col
	# 通緝變動彈出提示（Wanted >= 1 才提示，避免 SAFE 也吵）
	if wanted_level >= 1:
		_show_toast("警告：%s" % txt, col)
	
	# EMP 按鈕：wanted >= 2 才顯示
	if emp_button:
		if wanted_level >= 2:
			emp_button.show()
			
			# 只有在沒有動畫在執行時才創建新的 Tween
			if not emp_button_tween or not emp_button_tween.is_valid():
				# 建立並儲存 Tween
				emp_button_tween = create_tween()
				emp_button_tween.set_loops()
				# 閃爍效果 (從白色到紅色，然後重複)
				emp_button_tween.tween_property(emp_button, "modulate", Color.RED, 0.3).from(Color.WHITE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			emp_button.hide()
			# 【關鍵修正】: 檢查追蹤的 Tween 是否存在且有效，然後銷毀它
			if emp_button_tween and emp_button_tween.is_valid():
				emp_button_tween.kill()
				emp_button_tween = null # 清空變數


func _on_music_pitch_toggled(pressed: bool) -> void:
	# Dynamic BGM pitch toggle handler disabled — feature turned off.
	# Keep meta saved so user preference isn't lost if re-enabled later.
	_save_meta()
	_show_toast("動態BGM變速 已停用 (暫時註解)", Color(0.8, 0.8, 1.0))

# ----------------------------------------------------
# UI 更新
# ----------------------------------------------------

# 更新分數 UI 顯示
func _update_score_ui():
	if score_label:
		score_label.text = "已吞噬數據：" + str(current_score)
		
# 實際點擊按鈕時執行
func _on_EMP_Button_pressed():
	# 避免重複觸發（例如 _input + pressed 同時觸發）
	if _emp_reward_dialog and _emp_reward_dialog.visible:
		return
	# 先讓玩家選擇獎勵（之後你再把這裡換成真正的 rewarded ad 回呼）
	if _emp_reward_dialog:
		_emp_reward_dialog.popup_centered()
	else:
		_on_emp_reward_selected("REWARD_CLEAR")


func _on_emp_reward_selected(action: StringName) -> void:
	match String(action):
		"REWARD_CLEAR":
			_clear_all_enemies()
		"REWARD_TIME":
			time_left += rewarded_time_bonus
			_update_time_ui()
		_:
			pass
		
# 模擬觀看廣告後觸發的秒殺效果
func _trigger_emp_reward():
	# 已改為二選一獎勵，保留此函式避免舊呼叫點崩潰（若未來接廣告回呼可改用）
	pass
	
	# 3. (視覺/音效)：全畫面閃爍或震動效果
	# 可以考慮在 Main.gd 中加入一個 CameraShaker 節點來處理震動
	
# 輔助函式：銷毀所有敵人
func _clear_all_enemies():
	if _spawn_mgr:
		_spawn_mgr.clear_all_enemies()
			
# ----------------------------------------------------
# Roguelike 升級選擇系統
# ----------------------------------------------------
func _show_roguelike_upgrade_selection(lv: int) -> void:
	if not has_node("/root/RoguelikeUpgradeManager"):
		return
	var rum = get_node("/root/RoguelikeUpgradeManager")
	var choices: Array[Dictionary] = rum.generate_choices(lv)
	if choices.is_empty():
		return

	# Pause gameplay
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_upgrade = true

	# Create the upgrade selection UI
	var UpgradeUIScript: GDScript = load("res://Scripts/UpgradeSelectionUI.gd") as GDScript
	if not UpgradeUIScript:
		if _paused_by_upgrade:
			get_tree().paused = false
			_paused_by_upgrade = false
		return

	_upgrade_selection_ui = UpgradeUIScript.new() as CanvasLayer
	add_child(_upgrade_selection_ui)
	_upgrade_selection_ui.setup(choices)
	_upgrade_selection_ui.upgrade_chosen.connect(_on_roguelike_upgrade_chosen)


func _on_roguelike_upgrade_chosen(upgrade_id: String) -> void:
	# Resume gameplay
	if _paused_by_upgrade:
		get_tree().paused = false
		_paused_by_upgrade = false

	# Apply movement speed modifier from roguelike
	_apply_roguelike_speed()
	# Apply passive magnet strength (UI toast)
	if has_node("/root/RoguelikeUpgradeManager"):
		var rum = get_node("/root/RoguelikeUpgradeManager")
		var def: Dictionary = rum.find_upgrade_def(upgrade_id)
		if not def.is_empty():
			var rarity := String(def.get("rarity", "common"))
			var color := Color(0.5, 0.7, 1.0)
			match rarity:
				"rare": color = Color(0.6, 0.3, 1.0)
				"epic": color = Color(1.0, 0.7, 0.2)
			_show_toast("%s %s" % [String(def.get("icon", "")), String(def.get("name", ""))], color)

	Input.vibrate_handheld(30)


func _apply_roguelike_speed() -> void:
	if not has_node("/root/RoguelikeUpgradeManager"):
		return
	var rum = get_node("/root/RoguelikeUpgradeManager")
	var speed_mult: float = rum.get_multiplier("move_speed_mult")
	# Combine with meta upgrade speed
	speed_mult *= 1.0 + float(upgrade_speed_level) * 0.08
	var pc = get_node_or_null("PlayerController")
	if pc and pc.has_method("apply_speed_multiplier"):
		pc.apply_speed_multiplier(speed_mult)


func _apply_roguelike_passive_magnet(delta: float) -> void:
	"""Called from _physics_process: passive magnet from roguelike upgrades"""
	if not has_node("/root/RoguelikeUpgradeManager"):
		return
	var rum = get_node("/root/RoguelikeUpgradeManager")
	var mag_str: float = rum.get_modifier("passive_magnet")
	if mag_str <= 0.0:
		return
	var bh = %BlackHole
	if not bh or not camera:
		return
	var vp = get_viewport_rect().size
	var z = camera.zoom
	var world_size = Vector2(vp.x / max(0.001, z.x), vp.y / max(0.001, z.y))
	var view_rect = Rect2(camera.global_position - world_size * 0.5, world_size)
	var passive_force: float = magnet_strength * mag_str
	for prey in _get_cached_group("Prey"):
		if not is_instance_valid(prey):
			continue
		if not (prey is RigidBody2D):
			continue
		if not view_rect.has_point(prey.global_position):
			continue
		var dir = (bh.global_position - prey.global_position)
		var dist = max(50.0, dir.length())
		var force = dir.normalized() * passive_force * (1.0 / (dist / 200.0))
		(prey as RigidBody2D).apply_central_force(force * delta * 60.0)


func _handle_auto_shockwave() -> void:
	"""Handle auto_shockwave event from RoguelikeUpgradeManager"""
	var bh = %BlackHole
	if not bh or not bh.has_method("trigger_shockwave"):
		return
	# Auto shockwave: free (cost already handled by modifier system)
	bh.call("trigger_shockwave")
	_show_toast("⚡ 超新星自動衝擊波！", Color(1.0, 0.8, 0.3))
	Input.vibrate_handheld(25)


func _on_roguelike_auto_shockwave(type: String) -> void:
	if type == "auto_shockwave":
		_handle_auto_shockwave()

# ----------------------------------------------------
# 遊戲結束
# ----------------------------------------------------
func _game_over(reason: String):
	if is_game_over and not _revive_prompt_open:
		return
	_revive_prompt_open = false
	is_game_over = true
	# 結算：本局分數直接當作金幣累積（HCG Meta 動力）
	if not _run_score_claimed:
		meta_coins += int(current_score)
		_run_score_claimed = true
		_save_meta()
		_update_meta_ui()
	_game_over_seq += 1
	var seq: int = _game_over_seq
	
	if _spawn_mgr:
		_spawn_mgr.stop_timers()

	# 停止地圖事件
	_stop_map_event()

	# 清理 EMP 按鈕的 Tween 效果
	if emp_button_tween and emp_button_tween.is_valid():
		emp_button_tween.kill()
		emp_button_tween = null
	
	# 停止黑洞移動
	var player_controller = get_node_or_null("PlayerController")
	if player_controller:
		player_controller.set_physics_process(false)
	var black_hole = %BlackHole
	if black_hole:
		black_hole.set_process(false)
		black_hole.set_physics_process(false)
		if black_hole.has_method("disable_fullscreen_distort"):
			black_hole.disable_fullscreen_distort()
	
	if level_label:
		if reason == "ENTROPY_COLLAPSE":
			level_label.text = "核心崩潰！\n最終得分: %d" % current_score
		else: 
			level_label.text = "時間到！\n最終得分: %d" % current_score
			
		level_label.scale = Vector2(2.5, 2.5)
		level_label.modulate = Color(1, 1, 0)

	# 結束時停止震動/閃爍
	if camera:
		camera.offset = Vector2.ZERO
	_shake_time_left = 0.0
	_shake_strength = 0.0
	if damage_flash:
		damage_flash.color.a = 0.0
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
		_flash_tween = null
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
		_toast_tween = null

	# 局結束：自動領取已完成的局內任務獎勵
	if has_node("/root/MissionManager"):
		var msm: Node = get_node("/root/MissionManager")
		var mission_coins: int = msm.auto_claim_run_missions()
		# 每日任務也嘗試領取（本局達成的）
		for m in msm.daily_missions:
			if bool(m.get("completed", false)) and not bool(m.get("claimed", false)):
				mission_coins += msm.claim_mission(String(m.get("id", "")))
		if mission_coins > 0:
			meta_coins += mission_coins
			_save_meta()
			_update_meta_ui()
			_show_toast("任務獎勵：+%d 金幣" % mission_coins, Color(0.2, 1, 0.6))
	_update_mission_ui()

	# 3 秒後彈出選單（避免死亡瞬間打斷回饋）
	_show_game_over_dialog_after_delay(seq)


func _show_game_over_dialog_after_delay(seq: int) -> void:
	await get_tree().create_timer(3.0).timeout
	if seq != _game_over_seq:
		return
	if not is_game_over:
		return
	if _revive_prompt_open:
		return
	if not _game_over_dialog:
		return
	_game_over_dialog.dialog_text = "最終得分: %d" % current_score
	_game_over_dialog.popup_centered(Vector2i(520, 240))


func _show_toast(text: String, color: Color) -> void:
	if not toast_label:
		return
	# Ensure long text doesn't overflow off-screen.
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vpw := get_viewport_rect().size.x
	if vpw > 10.0:
		toast_label.custom_minimum_size = Vector2(min(820.0, vpw * 0.86), 0.0)
	toast_label.text = text
	toast_label.modulate = Color(color.r, color.g, color.b, 0.0)
	toast_label.scale = Vector2.ONE * 0.96
	
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
		_toast_tween = null
	
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_toast_tween.parallel().tween_property(toast_label, "scale", Vector2.ONE * 1.02, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 閃兩下
	_toast_tween.tween_property(toast_label, "modulate:a", 0.35, 0.10)
	_toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.10)
	# 停留後淡出
	_toast_tween.tween_interval(0.55)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _start_shake(duration: float, strength: float) -> void:
	_shake_time_left = max(_shake_time_left, duration)
	_shake_strength = max(_shake_strength, strength)


func _update_camera_shake(delta: float) -> void:
	if not camera:
		return
	if _shake_time_left <= 0.0:
		camera.offset = Vector2.ZERO
		_shake_strength = 0.0
		return
	_shake_time_left -= delta
	# 每幀隨機抖動（小幅度即可）
	var s = _shake_strength
	camera.offset = Vector2(randf_range(-s, s), randf_range(-s, s))
	# 漸弱
	_shake_strength = lerp(_shake_strength, 0.0, delta * 5.0)


func _flash_screen(color: Color, peak_alpha: float, duration: float) -> void:
	if not damage_flash:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
		_flash_tween = null
	
	damage_flash.color = Color(color.r, color.g, color.b, 0.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(damage_flash, "color:a", peak_alpha, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, max(0.08, duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _on_black_hole_damaged(amount: float) -> void:
	# 受傷：紅閃 + 強震 + 震動
	var a: float = clampf(amount / 25.0, 0.25, 0.9)
	_flash_screen(Color(1, 0.1, 0.1), a, 0.18)
	_start_shake(0.22, 10.0 + amount * 0.25)
	Input.vibrate_handheld(int(25 + amount * 2.0))


func _on_black_hole_swallowed_feedback(energy_gain: float) -> void:
	# 吞噬：小震 + 輕震動（大獵物更明顯）
	var strength: float = clampf(2.0 + energy_gain * 0.08, 2.0, 9.0)
	_start_shake(0.10, strength)
	_register_swallow_for_fever()
	if energy_gain >= 12.0:
		Input.vibrate_handheld(int(clamp(10 + energy_gain * 0.6, 10.0, 35.0)))
	# 吞噬大型目標：短暫停幀（hit stop）增加重量感
	if energy_gain >= 18.0:
		_hit_stop(0.06, 0.12)


func _on_black_hole_shockwave_triggered(intensity: float) -> void:
	# 強回饋：清彈感 + 震感 + 視覺圓環
	intensity = clampf(intensity, 0.2, 1.5)
	_start_shake(0.18, 10.0 * intensity)
	_flash_screen(Color(0.2, 1, 1), 0.25 * intensity, 0.18)
	Input.vibrate_handheld(int(18 + 25 * intensity))
	_show_toast("重力衝擊波！", Color(0.2, 1, 1))
	_draw_shockwave_ring(intensity)


func _draw_shockwave_ring(intensity: float) -> void:
	if not shockwave_ring or not is_instance_valid(shockwave_ring):
		return
	var bh = %BlackHole
	if not bh or not camera:
		return
	# 把黑洞世界座標換成螢幕座標（FeedbackLayer 是 CanvasLayer）
	var vp_transform: Transform2D = camera.get_viewport_transform()
	var center_px: Vector2 = vp_transform * (bh as Node2D).global_position
	shockwave_ring.position = center_px

	var vp_size: Vector2 = get_viewport_rect().size
	var max_r: float = minf(vp_size.x, vp_size.y) * 0.62
	var r0: float = max_r * 0.22
	var r1: float = max_r * clampf(intensity, 0.35, 1.0)
	var segments: int = 56

	shockwave_ring.clear_points()
	for i in range(segments):
		var a: float = (TAU * float(i)) / float(segments)
		shockwave_ring.add_point(Vector2(cos(a), sin(a)) * r0)
	shockwave_ring.default_color = Color(0.35, 1, 1, 0.0)
	shockwave_ring.width = 10.0
	shockwave_ring.visible = true

	var tw = create_tween()
	# alpha up
	tw.tween_property(shockwave_ring, "default_color:a", 0.85, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# expand
	tw.parallel().tween_method(func(rr: float) -> void:
		shockwave_ring.clear_points()
		for i in range(segments):
			var a2: float = (TAU * float(i)) / float(segments)
			shockwave_ring.add_point(Vector2(cos(a2), sin(a2)) * rr)
	, r0, r1, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# fade out + thin
	tw.tween_property(shockwave_ring, "default_color:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(shockwave_ring, "width", 2.0, 0.22)
	tw.finished.connect(func() -> void:
		if shockwave_ring and is_instance_valid(shockwave_ring):
			shockwave_ring.visible = false
	)
