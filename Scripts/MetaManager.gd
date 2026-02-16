extends Node
## MetaManager — 局外成長 / 持久化存檔管理 (Autoload)
## 所有 meta_* 變數與存檔邏輯的單一來源。
## Main.gd 及其他腳本透過 MetaManager.xxx 讀寫。

signal coins_changed(new_amount: int)

# ============================================================
# 存檔路徑
# ============================================================
const META_SAVE_PATH_EDITOR: String = "user://meta.cfg"
const META_SAVE_PATH_RUNTIME: String = "user://meta_runtime.cfg"

func _get_save_path() -> String:
	return META_SAVE_PATH_EDITOR if OS.has_feature("editor") else META_SAVE_PATH_RUNTIME

# ============================================================
# 持久資料
# ============================================================
var coins: int = 0
var selected_skin: String = "classic"
var unlocked_skins: Dictionary = {"classic": true}
var selected_map: String = "default"
var unlocked_maps: Dictionary = {"default": true}
var selected_menu_map: String = "default"
var selected_bgm_id: String = "default"
var campaign_cleared: bool = false
var campaign_max_unlocked: int = 1

var upgrade_gravity_level: int = 0
var upgrade_speed_level: int = 0
var upgrade_magnet_level: int = 0

# 音效 / 設定（也持久化）
var dynamic_bgm_pitch: bool = false
var music_volume_db: float = -6.0
var sfx_volume_db: float = -6.0

# 閒置收益
var pending_idle_reward_coins: int = 0

# ============================================================
# Public API
# ============================================================
func get_coins() -> int:
	return coins

func add_coins(amount: int) -> void:
	coins += amount
	coins_changed.emit(coins)

func spend_coins(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true

func is_skin_unlocked(skin_id: String) -> bool:
	return unlocked_skins.has(skin_id) and bool(unlocked_skins[skin_id])

func unlock_skin(skin_id: String) -> void:
	unlocked_skins[skin_id] = true

func is_map_unlocked(map_id: String) -> bool:
	return unlocked_maps.has(map_id) and bool(unlocked_maps[map_id])

func unlock_map(map_id: String) -> void:
	unlocked_maps[map_id] = true

func get_upgrade_level(kind: String) -> int:
	match kind:
		"gravity": return upgrade_gravity_level
		"speed":   return upgrade_speed_level
		"magnet":  return upgrade_magnet_level
	return 0

func set_upgrade_level(kind: String, level: int) -> void:
	match kind:
		"gravity": upgrade_gravity_level = level
		"speed":   upgrade_speed_level = level
		"magnet":  upgrade_magnet_level = level

func upgrade_cost(kind: String, level: int) -> int:
	match kind:
		"gravity":
			return 120 + level * 90
		"speed":
			return 150 + level * 110
		"magnet":
			return 140 + level * 100
	return 999999

func upgrade_total_spent(kind: String, level: int) -> int:
	var total := 0
	for i in range(level):
		total += upgrade_cost(kind, i)
	return total

# ============================================================
# 存檔 / 讀檔
# ============================================================
func load_meta() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(_get_save_path())
	if err == OK:
		coins = int(cfg.get_value("meta", "coins", 0))
		pending_idle_reward_coins = int(cfg.get_value("meta", "pending_idle_reward_coins", 0))
		selected_skin = String(cfg.get_value("skins", "selected", "classic"))
		var unlocked: Variant = cfg.get_value("skins", "unlocked", {"classic": true})
		if typeof(unlocked) == TYPE_DICTIONARY:
			unlocked_skins = unlocked as Dictionary
		else:
			unlocked_skins = {"classic": true}
		selected_map = String(cfg.get_value("maps", "selected", "default"))
		selected_menu_map = String(cfg.get_value("maps", "menu_selected", "default"))
		var unlocked_maps_v: Variant = cfg.get_value("maps", "unlocked", {"default": true})
		if typeof(unlocked_maps_v) == TYPE_DICTIONARY:
			unlocked_maps = unlocked_maps_v as Dictionary
		else:
			unlocked_maps = {"default": true}
		upgrade_gravity_level = int(cfg.get_value("upgrades", "gravity", 0))
		upgrade_speed_level = int(cfg.get_value("upgrades", "speed", 0))
		upgrade_magnet_level = int(cfg.get_value("upgrades", "magnet", 0))
		dynamic_bgm_pitch = bool(cfg.get_value("settings", "dynamic_bgm_pitch", dynamic_bgm_pitch))
		selected_bgm_id = String(cfg.get_value("settings", "bgm_id", selected_bgm_id))
		music_volume_db = float(cfg.get_value("settings", "music_volume_db", music_volume_db))
		sfx_volume_db = float(cfg.get_value("settings", "sfx_volume_db", sfx_volume_db))
		campaign_cleared = bool(cfg.get_value("campaign", "cleared", false))
		campaign_max_unlocked = int(cfg.get_value("campaign", "max_unlocked", 1))
		if has_node("/root/GachaManager"):
			var gm = get_node("/root/GachaManager")
			gm.load_from_config(cfg)
		if has_node("/root/MissionManager"):
			var msm = get_node("/root/MissionManager")
			msm.load_from_config(cfg)

	_validate()
	coins_changed.emit(coins)

func save_meta() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "coins", coins)
	cfg.set_value("meta", "pending_idle_reward_coins", pending_idle_reward_coins)
	cfg.set_value("meta", "last_seen", int(Time.get_unix_time_from_system()))
	cfg.set_value("skins", "selected", selected_skin)
	cfg.set_value("skins", "unlocked", unlocked_skins)
	cfg.set_value("maps", "selected", selected_map)
	cfg.set_value("maps", "menu_selected", selected_menu_map)
	cfg.set_value("maps", "unlocked", unlocked_maps)
	cfg.set_value("upgrades", "gravity", upgrade_gravity_level)
	cfg.set_value("upgrades", "speed", upgrade_speed_level)
	cfg.set_value("upgrades", "magnet", upgrade_magnet_level)
	cfg.set_value("settings", "dynamic_bgm_pitch", dynamic_bgm_pitch)
	cfg.set_value("settings", "bgm_id", selected_bgm_id)
	cfg.set_value("settings", "music_volume_db", music_volume_db)
	cfg.set_value("settings", "sfx_volume_db", sfx_volume_db)
	cfg.set_value("campaign", "cleared", campaign_cleared)
	cfg.set_value("campaign", "max_unlocked", campaign_max_unlocked)
	if has_node("/root/GachaManager"):
		var gm3 = get_node("/root/GachaManager")
		gm3.save_to_config(cfg)
	if has_node("/root/MissionManager"):
		var msm2 = get_node("/root/MissionManager")
		msm2.save_to_config(cfg)
	cfg.save(_get_save_path())

# ============================================================
# 閒置收益
# ============================================================
func grant_idle_rewards_if_any() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(_get_save_path())
	if err != OK:
		return
	var last_seen: int = int(cfg.get_value("meta", "last_seen", 0))
	var now: int = int(Time.get_unix_time_from_system())
	if last_seen <= 0 or now <= last_seen:
		return
	@warning_ignore("integer_division")
	var minutes: int = (now - last_seen) / 60
	minutes = clampi(minutes, 0, GameConfig.IDLE_COIN_CAP_MINUTES)
	if minutes <= 0:
		return
	var mult: float = 1.0 + float(upgrade_gravity_level) * 0.05
	var reward: int = int(round(float(minutes) * GameConfig.IDLE_COIN_RATE_PER_MIN * mult))
	if reward <= 0:
		return
	var cap: int = maxi(0, GameConfig.IDLE_COIN_DAILY_CAP)
	if cap > 0:
		var remaining: int = maxi(0, cap - maxi(0, pending_idle_reward_coins))
		reward = mini(reward, remaining)
	if reward <= 0:
		return
	pending_idle_reward_coins += reward
	save_meta()

# ============================================================
# Internal
# ============================================================
func _reset_defaults() -> void:
	coins = 0
	pending_idle_reward_coins = 0
	selected_skin = "classic"
	unlocked_skins = {"classic": true}
	selected_map = "default"
	selected_menu_map = "default"
	unlocked_maps = {"default": true}
	upgrade_gravity_level = 0
	upgrade_speed_level = 0
	upgrade_magnet_level = 0
	selected_bgm_id = "default"
	campaign_cleared = false
	campaign_max_unlocked = 1

func _validate() -> void:
	campaign_max_unlocked = clampi(campaign_max_unlocked, 1, GameConfig.CAMPAIGN_LEVEL_COUNT)
	if not unlocked_skins.has(selected_skin) or not bool(unlocked_skins[selected_skin]):
		selected_skin = "classic"
	if not unlocked_maps.has(selected_map) or not bool(unlocked_maps[selected_map]):
		selected_map = "default"
	if not unlocked_maps.has(selected_menu_map) or not bool(unlocked_maps[selected_menu_map]):
		selected_menu_map = "default"
	if selected_bgm_id != "default" and selected_bgm_id.begins_with("map:"):
		var map_id := selected_bgm_id.substr(4)
		if not (unlocked_maps.has(map_id) and bool(unlocked_maps[map_id])):
			selected_bgm_id = "default"
