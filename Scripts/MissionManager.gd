extends Node
## MissionManager — 每日任務 + 局內任務管理 (Autoload)
## 提供短期目標，提升留存與遊戲節奏。
##
## 任務類型：
##   SWALLOW_COUNT  — 本局吞噬 N 個物件
##   REACH_LEVEL    — 本局達到 Lv.N
##   KILL_ENEMIES   — 本局消滅 N 個敵人
##   SURVIVE_TIME   — 本局存活 N 秒
##   REACH_COMBO    — 本局達到 N 連擊
##   DEFEAT_BOSS    — 本局擊敗 Boss
##   USE_SHOCKWAVE  — 本局使用 N 次衝擊波
##   COLLECT_POWERUP— 本局收集 N 個道具

# ============================================================
# 常數
# ============================================================
const DAILY_MISSION_COUNT: int = 3
const RUN_MISSION_COUNT: int = 2
const DAILY_RESET_HOUR: int = 4  ## UTC+8 凌晨 4 點重置

# 任務種類 ID
enum MissionType {
	SWALLOW_COUNT,
	REACH_LEVEL,
	KILL_ENEMIES,
	SURVIVE_TIME,
	REACH_COMBO,
	DEFEAT_BOSS,
	USE_SHOCKWAVE,
	COLLECT_POWERUP,
}

# ============================================================
# 訊號
# ============================================================
signal mission_progress_updated(mission_id: String, current: int, target: int)
signal mission_completed(mission_id: String, reward_coins: int)
signal daily_missions_refreshed()

# ============================================================
# 任務結構
# ============================================================
# {
#   "id": "daily_0",
#   "type": MissionType,
#   "target": int,
#   "current": int,
#   "reward": int,
#   "completed": bool,
#   "claimed": bool,
#   "label": String,
# }

var daily_missions: Array[Dictionary] = []
var run_missions: Array[Dictionary] = []
var _daily_seed_date: String = ""  ## 用於判斷是否需要刷新

# 任務模板池：[type, min_target, max_target, reward_base, label_template]
const MISSION_TEMPLATES: Array = [
	[MissionType.SWALLOW_COUNT,  30, 80,  60,  "吞噬 {target} 個物件"],
	[MissionType.SWALLOW_COUNT,  100, 200, 120, "吞噬 {target} 個物件"],
	[MissionType.REACH_LEVEL,    5, 8,    80,  "達到 Lv.{target}"],
	[MissionType.REACH_LEVEL,    10, 15,  150, "達到 Lv.{target}"],
	[MissionType.KILL_ENEMIES,   5, 15,   70,  "消滅 {target} 個敵人"],
	[MissionType.KILL_ENEMIES,   20, 40,  130, "消滅 {target} 個敵人"],
	[MissionType.SURVIVE_TIME,   60, 120, 50,  "存活 {target} 秒"],
	[MissionType.SURVIVE_TIME,   150, 180, 100, "存活 {target} 秒"],
	[MissionType.REACH_COMBO,    3, 5,    90,  "達到 {target} 連擊"],
	[MissionType.DEFEAT_BOSS,    1, 1,    200, "擊敗 Boss"],
	[MissionType.USE_SHOCKWAVE,  2, 5,    60,  "使用 {target} 次衝擊波"],
	[MissionType.COLLECT_POWERUP, 3, 8,   50,  "收集 {target} 個道具"],
]

# 局內任務用較簡單的模板
const RUN_TEMPLATES: Array = [
	[MissionType.SWALLOW_COUNT,  15, 40,  30,  "吞噬 {target} 個物件"],
	[MissionType.KILL_ENEMIES,   3, 10,   40,  "消滅 {target} 個敵人"],
	[MissionType.REACH_LEVEL,    3, 6,    50,  "達到 Lv.{target}"],
	[MissionType.REACH_COMBO,    2, 4,    40,  "達到 {target} 連擊"],
	[MissionType.COLLECT_POWERUP, 2, 5,   30,  "收集 {target} 個道具"],
	[MissionType.USE_SHOCKWAVE,  1, 3,    35,  "使用 {target} 次衝擊波"],
]

# ============================================================
# 生命週期
# ============================================================
func _ready() -> void:
	_check_daily_refresh()


# ============================================================
# 每日任務
# ============================================================
func _check_daily_refresh() -> void:
	var today: String = _get_daily_key()
	if today != _daily_seed_date or daily_missions.is_empty():
		_generate_daily_missions(today)
		_daily_seed_date = today
		daily_missions_refreshed.emit()


func _get_daily_key() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var hour: int = int(dt.get("hour", 0))
	# 如果還沒到重置時間，算前一天
	var day_str: String = "%04d-%02d-%02d" % [int(dt.get("year", 2025)), int(dt.get("month", 1)), int(dt.get("day", 1))]
	if hour < DAILY_RESET_HOUR:
		# 用前一天的日期作為 key
		var unix: int = int(Time.get_unix_time_from_system()) - 86400
		var prev: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
		day_str = "%04d-%02d-%02d" % [int(prev.get("year", 2025)), int(prev.get("month", 1)), int(prev.get("day", 1))]
	return day_str


func _generate_daily_missions(seed_key: String) -> void:
	daily_missions.clear()
	# 用日期當隨機種子，讓同一天的重新開遊戲看到相同任務
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var used_types: Array[int] = []
	for i in range(DAILY_MISSION_COUNT):
		var mission: Dictionary = _pick_mission(MISSION_TEMPLATES, rng, used_types, "daily_%d" % i)
		daily_missions.append(mission)


func _pick_mission(templates: Array, rng: RandomNumberGenerator, used_types: Array[int], id: String) -> Dictionary:
	var attempts: int = 0
	var idx: int = rng.randi_range(0, templates.size() - 1)
	while used_types.has(idx) and attempts < 20:
		idx = rng.randi_range(0, templates.size() - 1)
		attempts += 1
	used_types.append(idx)
	var t: Array = templates[idx]
	var mission_type: int = int(t[0])
	var target: int = rng.randi_range(int(t[1]), int(t[2]))
	var reward: int = int(t[3])
	var label_tpl: String = String(t[4])
	var label: String = label_tpl.replace("{target}", str(target))
	return {
		"id": id,
		"type": mission_type,
		"target": target,
		"current": 0,
		"reward": reward,
		"completed": false,
		"claimed": false,
		"label": label,
	}


# ============================================================
# 局內任務（每局開始時生成）
# ============================================================
func generate_run_missions() -> void:
	run_missions.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var used_types: Array[int] = []
	for i in range(RUN_MISSION_COUNT):
		var mission: Dictionary = _pick_mission(RUN_TEMPLATES, rng, used_types, "run_%d" % i)
		run_missions.append(mission)


func reset_run_progress() -> void:
	"""每局開始時重置局內任務進度"""
	for m in run_missions:
		m["current"] = 0
		m["completed"] = false
		m["claimed"] = false
	# 同時重置每日任務的局內進度（但保留已完成/已領取狀態）
	for m in daily_missions:
		if not bool(m.get("completed", false)):
			m["current"] = 0


# ============================================================
# 進度更新 API（由 Main.gd 呼叫）
# ============================================================
func report_swallow(count: int = 1) -> void:
	_advance_missions(MissionType.SWALLOW_COUNT, count)

func report_enemy_killed(count: int = 1) -> void:
	_advance_missions(MissionType.KILL_ENEMIES, count)

func report_level_reached(level: int) -> void:
	_set_missions_max(MissionType.REACH_LEVEL, level)

func report_survive_time(seconds: int) -> void:
	_set_missions_max(MissionType.SURVIVE_TIME, seconds)

func report_combo(combo_count: int) -> void:
	_set_missions_max(MissionType.REACH_COMBO, combo_count)

func report_boss_defeated() -> void:
	_advance_missions(MissionType.DEFEAT_BOSS, 1)

func report_shockwave_used() -> void:
	_advance_missions(MissionType.USE_SHOCKWAVE, 1)

func report_powerup_collected() -> void:
	_advance_missions(MissionType.COLLECT_POWERUP, 1)


func _advance_missions(mission_type: int, amount: int) -> void:
	for m in daily_missions + run_missions:
		if bool(m.get("completed", false)):
			continue
		if int(m.get("type", -1)) != mission_type:
			continue
		m["current"] = mini(int(m.get("current", 0)) + amount, int(m.get("target", 1)))
		_check_mission_completion(m)

func _set_missions_max(mission_type: int, value: int) -> void:
	for m in daily_missions + run_missions:
		if bool(m.get("completed", false)):
			continue
		if int(m.get("type", -1)) != mission_type:
			continue
		var old: int = int(m.get("current", 0))
		if value > old:
			m["current"] = mini(value, int(m.get("target", 1)))
			_check_mission_completion(m)

func _check_mission_completion(m: Dictionary) -> void:
	var current: int = int(m.get("current", 0))
	var target: int = int(m.get("target", 1))
	mission_progress_updated.emit(String(m.get("id", "")), current, target)
	if current >= target and not bool(m.get("completed", false)):
		m["completed"] = true
		var reward: int = int(m.get("reward", 0))
		mission_completed.emit(String(m.get("id", "")), reward)


# ============================================================
# 領取獎勵
# ============================================================
func claim_mission(mission_id: String) -> int:
	"""領取任務獎勵，回傳金幣數（0 = 不可領取）"""
	for m in daily_missions + run_missions:
		if String(m.get("id", "")) != mission_id:
			continue
		if not bool(m.get("completed", false)):
			return 0
		if bool(m.get("claimed", false)):
			return 0
		m["claimed"] = true
		var reward: int = int(m.get("reward", 0))
		if reward > 0 and has_node("/root/MetaManager"):
			var mm: Node = get_node("/root/MetaManager")
			mm.call("add_coins", reward)
			mm.call("save_meta")
		return reward
	return 0

func auto_claim_run_missions() -> int:
	"""局結束時自動領取所有已完成的局內任務"""
	var total: int = 0
	for m in run_missions:
		if bool(m.get("completed", false)) and not bool(m.get("claimed", false)):
			total += claim_mission(String(m.get("id", "")))
	return total


# ============================================================
# 查詢
# ============================================================
func get_all_active_missions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for m in daily_missions:
		if not bool(m.get("claimed", false)):
			result.append(m)
	for m in run_missions:
		if not bool(m.get("claimed", false)):
			result.append(m)
	return result

func get_unclaimed_count() -> int:
	var count: int = 0
	for m in daily_missions + run_missions:
		if bool(m.get("completed", false)) and not bool(m.get("claimed", false)):
			count += 1
	return count

func has_uncompleted_missions() -> bool:
	for m in daily_missions + run_missions:
		if not bool(m.get("completed", false)):
			return true
	return false


# ============================================================
# 存檔 / 讀檔 (委託 MetaManager 的 ConfigFile)
# ============================================================
func save_to_config(cfg: ConfigFile) -> void:
	cfg.set_value("missions", "daily_seed", _daily_seed_date)
	cfg.set_value("missions", "daily", _serialize_missions(daily_missions))

func load_from_config(cfg: ConfigFile) -> void:
	_daily_seed_date = String(cfg.get_value("missions", "daily_seed", ""))
	var saved: Variant = cfg.get_value("missions", "daily", [])
	if typeof(saved) == TYPE_ARRAY:
		daily_missions = _deserialize_missions(saved as Array)
	# 檢查是否需要刷新
	_check_daily_refresh()

func _serialize_missions(missions: Array[Dictionary]) -> Array:
	var out: Array = []
	for m in missions:
		out.append(m.duplicate())
	return out

func _deserialize_missions(arr: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in arr:
		if typeof(item) == TYPE_DICTIONARY:
			out.append(item as Dictionary)
	return out
