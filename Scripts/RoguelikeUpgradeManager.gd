extends Node
## RoguelikeUpgradeManager — Autoload
## 管理局內 Roguelike 升級選擇（每次升級時彈出 3 個隨機被動能力）、
## 能力進化合成、以及多角色定義。
##
## 用法：
##   RoguelikeUpgradeManager.generate_choices(current_level)  → Array[Dictionary]
##   RoguelikeUpgradeManager.apply_upgrade(upgrade_id)
##   RoguelikeUpgradeManager.check_evolutions()               → Array[Dictionary] (newly unlocked)
##   RoguelikeUpgradeManager.get_character_defs()              → Dictionary
##   RoguelikeUpgradeManager.reset_run()                       → 清除本局所有被動

signal upgrade_applied(upgrade: Dictionary)
signal evolution_unlocked(evolution: Dictionary)
signal choices_ready(choices: Array)  # 3 choices for UI to display

# ============================================================
# 升級池定義
# ============================================================
## 每個被動能力的定義
## {
##   id: StringName,
##   name: String,        # 中文顯示名
##   desc: String,        # 中文描述
##   icon: String,        # emoji 或圖示路徑
##   max_stack: int,      # 最大堆疊次數
##   rarity: String,      # "common" / "rare" / "epic"
##   weight: float,       # 出現權重 (越大越常出現)
##   effect_key: String,  # 效果類型鍵
##   effect_value: float, # 每層效果數值
##   tags: Array[String], # 標籤 (用於進化合成配對)
## }

const UPGRADE_POOL: Array[Dictionary] = [
	# --- Common (高權重，基礎強化) ---
	{
		"id": "pull_strength_up",
		"name": "引力增幅",
		"desc": "拉力 +20%",
		"icon": "🌀",
		"max_stack": 5,
		"rarity": "common",
		"weight": 10.0,
		"effect_key": "pull_strength_mult",
		"effect_value": 0.20,
		"tags": ["gravity", "offense"],
	},
	{
		"id": "stability_decay_down",
		"name": "熵值抑制",
		"desc": "穩定度衰減 -15%",
		"icon": "🛡️",
		"max_stack": 5,
		"rarity": "common",
		"weight": 10.0,
		"effect_key": "decay_rate_mult",
		"effect_value": -0.15,
		"tags": ["defense", "stability"],
	},
	{
		"id": "pull_radius_up",
		"name": "事件視界擴張",
		"desc": "吸引範圍 +10%",
		"icon": "⭕",
		"max_stack": 5,
		"rarity": "common",
		"weight": 9.0,
		"effect_key": "pull_radius_mult",
		"effect_value": 0.10,
		"tags": ["gravity", "range"],
	},
	{
		"id": "move_speed_up",
		"name": "星際推進",
		"desc": "移動速度 +12%",
		"icon": "💨",
		"max_stack": 5,
		"rarity": "common",
		"weight": 9.0,
		"effect_key": "move_speed_mult",
		"effect_value": 0.12,
		"tags": ["speed", "mobility"],
	},
	{
		"id": "score_mult_up",
		"name": "質量轉換",
		"desc": "分數加成 +15%",
		"icon": "💎",
		"max_stack": 5,
		"rarity": "common",
		"weight": 8.0,
		"effect_key": "score_mult",
		"effect_value": 0.15,
		"tags": ["score", "offense"],
	},
	{
		"id": "stability_regen",
		"name": "質量回饋",
		"desc": "每次吞噬回復 +2 穩定度",
		"icon": "💚",
		"max_stack": 5,
		"rarity": "common",
		"weight": 8.0,
		"effect_key": "swallow_heal",
		"effect_value": 2.0,
		"tags": ["defense", "stability", "swallow"],
	},
	# --- Rare (中等權重，特化能力) ---
	{
		"id": "magnet_aura",
		"name": "磁場光環",
		"desc": "永久微型磁鐵效果 (30% 強度)",
		"icon": "🧲",
		"max_stack": 3,
		"rarity": "rare",
		"weight": 5.0,
		"effect_key": "passive_magnet",
		"effect_value": 0.30,
		"tags": ["magnet", "gravity", "range"],
	},
	{
		"id": "combo_window_up",
		"name": "時間扭曲",
		"desc": "Combo 判定窗口 +0.4 秒",
		"icon": "⏳",
		"max_stack": 3,
		"rarity": "rare",
		"weight": 5.0,
		"effect_key": "combo_window_bonus",
		"effect_value": 0.4,
		"tags": ["combo", "time"],
	},
	{
		"id": "shockwave_cost_down",
		"name": "衝擊波效率",
		"desc": "衝擊波穩定度消耗 -20%",
		"icon": "💥",
		"max_stack": 3,
		"rarity": "rare",
		"weight": 5.0,
		"effect_key": "shockwave_cost_mult",
		"effect_value": -0.20,
		"tags": ["shockwave", "defense"],
	},
	{
		"id": "fever_duration_up",
		"name": "狂暴延長",
		"desc": "Fever 模式持續時間 +1.5 秒",
		"icon": "🔥",
		"max_stack": 3,
		"rarity": "rare",
		"weight": 5.0,
		"effect_key": "fever_duration_bonus",
		"effect_value": 1.5,
		"tags": ["fever", "offense"],
	},
	{
		"id": "damage_reduction",
		"name": "奇異物質",
		"desc": "受到傷害 -20%",
		"icon": "🔰",
		"max_stack": 3,
		"rarity": "rare",
		"weight": 5.0,
		"effect_key": "damage_reduction",
		"effect_value": 0.20,
		"tags": ["defense", "stability"],
	},
	{
		"id": "kill_radius_up",
		"name": "吞噬核心",
		"desc": "吞噬半徑 +15%",
		"icon": "⚫",
		"max_stack": 3,
		"rarity": "rare",
		"weight": 5.0,
		"effect_key": "kill_radius_mult",
		"effect_value": 0.15,
		"tags": ["swallow", "offense"],
	},
	# --- Epic (低權重，強力被動) ---
	{
		"id": "vampiric_pull",
		"name": "暗物質吸取",
		"desc": "吞噬敵人時回復 10 穩定度",
		"icon": "🩸",
		"max_stack": 2,
		"rarity": "epic",
		"weight": 2.5,
		"effect_key": "enemy_swallow_heal",
		"effect_value": 10.0,
		"tags": ["offense", "defense", "swallow"],
	},
	{
		"id": "time_on_swallow",
		"name": "時間竊取",
		"desc": "每次吞噬 +0.3 秒",
		"icon": "⏰",
		"max_stack": 2,
		"rarity": "epic",
		"weight": 2.5,
		"effect_key": "swallow_time_bonus",
		"effect_value": 0.3,
		"tags": ["time", "swallow"],
	},
	{
		"id": "double_score_chance",
		"name": "量子疊加",
		"desc": "15% 機率雙倍分數",
		"icon": "✨",
		"max_stack": 2,
		"rarity": "epic",
		"weight": 2.5,
		"effect_key": "double_score_chance",
		"effect_value": 0.15,
		"tags": ["score", "offense"],
	},
	{
		"id": "explosion_on_swallow",
		"name": "超新星",
		"desc": "每 8 次吞噬自動觸發小型衝擊波",
		"icon": "💫",
		"max_stack": 1,
		"rarity": "epic",
		"weight": 2.0,
		"effect_key": "auto_shockwave_interval",
		"effect_value": 8.0,
		"tags": ["shockwave", "offense", "swallow"],
	},
]

# ============================================================
# 進化合成定義
# ============================================================
## 當玩家同時擁有指定的兩個被動能力時，自動合成為超強進化能力
## {
##   id: StringName,
##   name: String,
##   desc: String,
##   icon: String,
##   requires: Array[String],      # 需要的兩個被動 id
##   effect_key: String,
##   effect_value: float,
##   replaces_required: bool,      # true = 消耗原材料
## }

const EVOLUTION_POOL: Array[Dictionary] = [
	{
		"id": "gravity_overlord",
		"name": "重力魔王",
		"desc": "自動吸引全場獵物（磁鐵+引力合體，100% 強度永久磁鐵）",
		"icon": "👑",
		"requires": ["magnet_aura", "pull_strength_up"],
		"effect_key": "passive_magnet",
		"effect_value": 1.0,
		"replaces_required": true,
	},
	{
		"id": "event_horizon",
		"name": "事件視界",
		"desc": "吸引範圍+吞噬半徑大幅擴張 (+50%)",
		"icon": "🕳️",
		"requires": ["pull_radius_up", "kill_radius_up"],
		"effect_key": "pull_radius_mult",
		"effect_value": 0.50,
		"extra_effects": {"kill_radius_mult": 0.50},
		"replaces_required": true,
	},
	{
		"id": "perpetual_fever",
		"name": "永恆狂暴",
		"desc": "Fever 持續時間 +4 秒 且 Fever 中不消耗穩定度",
		"icon": "🌋",
		"requires": ["fever_duration_up", "stability_decay_down"],
		"effect_key": "fever_duration_bonus",
		"effect_value": 4.0,
		"extra_effects": {"fever_no_decay": 1.0},
		"replaces_required": true,
	},
	{
		"id": "star_eater",
		"name": "噬星者",
		"desc": "吞噬回復大幅增加 + 敵人吞噬回復翻倍",
		"icon": "⭐",
		"requires": ["stability_regen", "vampiric_pull"],
		"effect_key": "swallow_heal",
		"effect_value": 5.0,
		"extra_effects": {"enemy_swallow_heal": 20.0},
		"replaces_required": true,
	},
	{
		"id": "time_lord",
		"name": "時間領主",
		"desc": "Combo 窗口 +1 秒 且每次吞噬 +0.5 秒",
		"icon": "🕐",
		"requires": ["combo_window_up", "time_on_swallow"],
		"effect_key": "combo_window_bonus",
		"effect_value": 1.0,
		"extra_effects": {"swallow_time_bonus": 0.5},
		"replaces_required": true,
	},
	{
		"id": "supernova_engine",
		"name": "超新星引擎",
		"desc": "衝擊波不消耗穩定度 + 每 5 次吞噬自動衝擊波",
		"icon": "🌟",
		"requires": ["shockwave_cost_down", "explosion_on_swallow"],
		"effect_key": "shockwave_cost_mult",
		"effect_value": -1.0,
		"extra_effects": {"auto_shockwave_interval": 5.0},
		"replaces_required": true,
	},
]

# ============================================================
# 角色 / 黑洞類型定義
# ============================================================
## 不同黑洞有不同初始能力

const CHARACTER_DEFS: Dictionary = {
	"standard": {
		"id": "standard",
		"name": "標準型",
		"desc": "均衡的黑洞，適合新手",
		"icon": "⚫",
		"unlock_condition": "default",  # 預設解鎖
		"modifiers": {},  # 無任何修正
	},
	"stable": {
		"id": "stable",
		"name": "穩定型",
		"desc": "穩定度衰減慢 (-30%)，但拉力較弱 (-15%)",
		"icon": "🛡️",
		"unlock_condition": "reach_level_10",
		"modifiers": {
			"decay_rate_mult": -0.30,
			"pull_strength_mult": -0.15,
		},
	},
	"glutton": {
		"id": "glutton",
		"name": "暴食型",
		"desc": "拉力強 (+30%)，但穩定度衰減快 (+20%)",
		"icon": "😈",
		"unlock_condition": "score_5000",
		"modifiers": {
			"pull_strength_mult": 0.30,
			"decay_rate_mult": 0.20,
		},
	},
	"magnetar": {
		"id": "magnetar",
		"name": "磁星型",
		"desc": "自帶磁鐵效果 (40%)，移動速度 -10%",
		"icon": "🧲",
		"unlock_condition": "total_swallow_1000",
		"modifiers": {
			"passive_magnet": 0.40,
			"move_speed_mult": -0.10,
		},
	},
	"speedster": {
		"id": "speedster",
		"name": "疾行型",
		"desc": "移動速度 +25%，吞噬範圍 -10%",
		"icon": "💨",
		"unlock_condition": "reach_level_15",
		"modifiers": {
			"move_speed_mult": 0.25,
			"kill_radius_mult": -0.10,
		},
	},
	"berserker": {
		"id": "berserker",
		"name": "狂暴型",
		"desc": "Fever 持續 +3 秒，Fever 觸發門檻降低，但基礎穩定度 -20",
		"icon": "🔥",
		"unlock_condition": "fever_count_10",
		"modifiers": {
			"fever_duration_bonus": 3.0,
			"fever_threshold_reduction": 3,
			"max_stability_offset": -20.0,
		},
	},
}

# ============================================================
# 局內運行時狀態
# ============================================================
## 目前擁有的被動 { upgrade_id: stack_count }
var active_upgrades: Dictionary = {}
## 已解鎖的進化 { evolution_id: true }
var active_evolutions: Dictionary = {}
## 本局選擇的角色 id
var selected_character: String = "standard"
## 本局已升級次數（用於調整稀有度權重）
var _run_upgrade_count: int = 0
## 自動衝擊波計數器
var _auto_shockwave_counter: int = 0

# ============================================================
# Public API
# ============================================================

func reset_run() -> void:
	"""新局開始時呼叫，清除所有局內被動"""
	active_upgrades.clear()
	active_evolutions.clear()
	_run_upgrade_count = 0
	_auto_shockwave_counter = 0


func generate_choices(current_level: int) -> Array[Dictionary]:
	"""產生 3 個不重複的升級選項（權重隨機）"""
	var pool: Array[Dictionary] = _build_weighted_pool()
	var choices: Array[Dictionary] = []
	var used_ids: Array[String] = []

	# 升級次數越多，稀有/史詩出現率越高
	var rare_bonus: float = _run_upgrade_count * 0.15
	for item in pool:
		if String(item.get("rarity", "common")) == "rare":
			item["_adj_weight"] = float(item.get("weight", 5.0)) + rare_bonus
		elif String(item.get("rarity", "common")) == "epic":
			item["_adj_weight"] = float(item.get("weight", 2.0)) + rare_bonus * 0.6
		else:
			item["_adj_weight"] = float(item.get("weight", 10.0))

	for _i in range(3):
		var pick := _weighted_pick(pool, used_ids)
		if pick.is_empty():
			break
		choices.append(pick)
		used_ids.append(String(pick.get("id", "")))

	choices_ready.emit(choices)
	return choices


func apply_upgrade(upgrade_id: String) -> void:
	"""玩家選擇了一個升級"""
	var def := find_upgrade_def(upgrade_id)
	if def.is_empty():
		return
	var current_stack: int = int(active_upgrades.get(upgrade_id, 0))
	var max_s: int = int(def.get("max_stack", 1))
	if current_stack >= max_s:
		return
	active_upgrades[upgrade_id] = current_stack + 1
	_run_upgrade_count += 1
	upgrade_applied.emit(def)

	# 檢查是否觸發進化
	var evolutions := check_evolutions()
	for evo in evolutions:
		evolution_unlocked.emit(evo)


func check_evolutions() -> Array[Dictionary]:
	"""檢查並觸發所有符合條件的進化"""
	var newly_unlocked: Array[Dictionary] = []
	for evo in EVOLUTION_POOL:
		var evo_id := String(evo.get("id", ""))
		if active_evolutions.has(evo_id):
			continue
		var requires: Array = evo.get("requires", []) as Array
		var all_met := true
		for req in requires:
			if not active_upgrades.has(String(req)):
				all_met = false
				break
		if all_met:
			active_evolutions[evo_id] = true
			# 如果進化消耗原材料
			if bool(evo.get("replaces_required", false)):
				for req2 in requires:
					active_upgrades.erase(String(req2))
			newly_unlocked.append(evo)
	return newly_unlocked


func get_modifier(effect_key: String) -> float:
	"""取得某個效果鍵的總合修正值（被動 + 進化 + 角色）"""
	var total: float = 0.0

	# 角色基礎修正
	var char_def: Dictionary = CHARACTER_DEFS.get(selected_character, {}) as Dictionary
	var char_mods: Dictionary = char_def.get("modifiers", {}) as Dictionary
	total += float(char_mods.get(effect_key, 0.0))

	# 被動升級堆疊
	for uid in active_upgrades:
		var def := find_upgrade_def(String(uid))
		if def.is_empty():
			continue
		if String(def.get("effect_key", "")) == effect_key:
			total += float(def.get("effect_value", 0.0)) * int(active_upgrades[uid])

	# 進化效果
	for evo_id in active_evolutions:
		var evo := _find_evolution_def(String(evo_id))
		if evo.is_empty():
			continue
		if String(evo.get("effect_key", "")) == effect_key:
			total += float(evo.get("effect_value", 0.0))
		var extras: Dictionary = evo.get("extra_effects", {}) as Dictionary
		total += float(extras.get(effect_key, 0.0))

	return total


func get_multiplier(effect_key: String) -> float:
	"""取得效果作為乘數 (1.0 + modifier)，適合用於乘法修正"""
	return 1.0 + get_modifier(effect_key)


func get_active_upgrade_list() -> Array[Dictionary]:
	"""回傳目前所有被動能力的列表（含堆疊數）"""
	var result: Array[Dictionary] = []
	for uid in active_upgrades:
		var def := find_upgrade_def(String(uid))
		if def.is_empty():
			continue
		var d := def.duplicate()
		d["stack"] = int(active_upgrades[uid])
		result.append(d)
	return result


func get_active_evolution_list() -> Array[Dictionary]:
	"""回傳目前所有已解鎖進化"""
	var result: Array[Dictionary] = []
	for evo_id in active_evolutions:
		var def := _find_evolution_def(String(evo_id))
		if not def.is_empty():
			result.append(def)
	return result


func get_character_defs() -> Dictionary:
	return CHARACTER_DEFS


func get_unlocked_characters() -> Array[String]:
	"""回傳已解鎖的角色 id 列表"""
	# For now: all characters are unlocked. 
	# TODO: Integrate with MetaManager for persistent unlock tracking.
	var unlocked: Array[String] = []
	for cid in CHARACTER_DEFS:
		var cdef: Dictionary = CHARACTER_DEFS[cid] as Dictionary
		var cond := String(cdef.get("unlock_condition", "default"))
		if cond == "default":
			unlocked.append(String(cid))
			continue
		# Check MetaManager for unlock conditions
		if _check_unlock_condition(cond):
			unlocked.append(String(cid))
	return unlocked


func notify_swallow() -> void:
	"""Main.gd 在每次吞噬時呼叫，用於自動衝擊波計數"""
	var interval := get_modifier("auto_shockwave_interval")
	if interval > 0.0:
		_auto_shockwave_counter += 1
		if _auto_shockwave_counter >= int(interval):
			_auto_shockwave_counter = 0
			Events.powerup_collected.emit("auto_shockwave")


# ============================================================
# Internal
# ============================================================

func _build_weighted_pool() -> Array[Dictionary]:
	"""建立可選升級池（排除已滿堆疊的）"""
	var pool: Array[Dictionary] = []
	for def in UPGRADE_POOL:
		var uid := String(def.get("id", ""))
		var current_stack: int = int(active_upgrades.get(uid, 0))
		var max_s: int = int(def.get("max_stack", 1))
		if current_stack < max_s:
			pool.append(def.duplicate())
	return pool


func _weighted_pick(pool: Array[Dictionary], exclude_ids: Array[String]) -> Dictionary:
	"""從池中加權隨機選一個（排除已選 id）"""
	var candidates: Array[Dictionary] = []
	var total_weight: float = 0.0
	for item in pool:
		var item_id := String(item.get("id", ""))
		if item_id in exclude_ids:
			continue
		var w: float = float(item.get("_adj_weight", item.get("weight", 1.0)))
		total_weight += w
		candidates.append(item)

	if candidates.is_empty() or total_weight <= 0.0:
		return {}

	var roll: float = randf() * total_weight
	var accum: float = 0.0
	for c in candidates:
		accum += float(c.get("_adj_weight", c.get("weight", 1.0)))
		if roll <= accum:
			return c
	return candidates[-1]


func find_upgrade_def(upgrade_id: String) -> Dictionary:
	for def in UPGRADE_POOL:
		if String(def.get("id", "")) == upgrade_id:
			return def
	return {}


func _find_evolution_def(evo_id: String) -> Dictionary:
	for evo in EVOLUTION_POOL:
		if String(evo.get("id", "")) == evo_id:
			return evo
	return {}


func _check_unlock_condition(condition: String) -> bool:
	"""檢查角色解鎖條件（基於 MetaManager 持久數據）"""
	if not has_node("/root/MetaManager"):
		return condition == "default"
	# For MVP: unlock all characters. Full condition checks can be added later.
	# This keeps the feature playable immediately.
	return true
