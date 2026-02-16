extends Node
## GameConfig — 所有遊戲平衡數值的單一來源 (Autoload)
## 任何腳本都能透過 GameConfig.XXX 讀取。

# ============================================================
# 時間
# ============================================================
const ENDLESS_TIME_LIMIT: float = 180.0
const CAMPAIGN_TIME_LIMIT: float = 150.0
const REWARDED_TIME_BONUS: float = 20.0

# ============================================================
# 穩定度 / 熵值
# ============================================================
const MAX_STABILITY: float = 100.0
const BASE_DECAY_RATE: float = 2.2
const DECAY_LEVEL_SCALE: float = 0.08
const REVIVE_STABILITY_RATIO: float = 0.6

# ============================================================
# 戰鬥 — 傷害
# ============================================================
const ENEMY_CONTACT_DAMAGE: float = 30.0
const MELEE_HIT_RADIUS: float = 140.0

# ============================================================
# 戰鬥 — 超載 / 衝擊波
# ============================================================
const OVERLOAD_THRESHOLD: float = 0.8
const OVERLOAD_PULL_MULTIPLIER: float = 1.2
const OVERLOAD_SCORE_MULTIPLIER: float = 2.0
const SHOCKWAVE_STABILITY_COST: float = 28.0
const SHOCKWAVE_RADIUS: float = 420.0
const SHOCKWAVE_PUSH_IMPULSE: float = 520.0
const SHOCKWAVE_STUN_TIME: float = 0.45

# ============================================================
# 成長 / 升級
# ============================================================
const BASE_GROWTH_PER_OBJECT: float = 6.0
const EXPONENTIAL_GROWTH_FACTOR: float = 0.06
const GROWTH_PER_LEVEL: int = 26
const GROWTH_ENERGY_DIVISOR: float = 22.0
const MAX_LEVEL: int = 30
const FINAL_MAX_RADIUS: float = 2800.0
const VISUAL_GROWTH_FACTOR: float = 1.5

# ============================================================
# 物理 — 黑洞核心
# ============================================================
const PULL_STRENGTH: float = 900.0
const BASE_KILL_RADIUS: float = 50.0
const BASE_PULL_RADIUS: float = 500.0
const BASE_VISUAL_SCALE: float = 0.5

# ============================================================
# Fever 模式
# ============================================================
const FEVER_DURATION_SEC: float = 6.5
const FEVER_PULL_RADIUS_MULTIPLIER: float = 2.0
const FEVER_SPEED_MULTIPLIER: float = 1.5
const FEVER_PROJECTILE_ABSORB_RADIUS: float = 360.0
const FEVER_ENEMY_SCORE_MULTIPLIER: float = 2.0
const FEVER_ENEMY_TIME_BONUS_SEC: float = 0.9
const FEVER_TIME_CAP_MULTIPLIER: float = 2.25
const FEVER_ENEMY_STABILITY_GAIN: float = 18.0
const FEVER_COMBO_REQUIRED: int = 10
const FEVER_COMBO_CHAIN_WINDOW_SEC: float = 2.2

# ============================================================
# 生成 — 獵物
# ============================================================
const SPAWN_RATE: float = 1.5
const PREY_BASE_SPAWN_COUNT: int = 2
const PREY_MAX_SPAWN_COUNT: int = 5
const MAX_PREY_ALIVE: int = 90

# ============================================================
# 生成 — 敵人
# ============================================================
const MAX_ENEMIES_ALIVE: int = 22
const MAX_ENEMY_PROJECTILES_ALIVE: int = 90

## 各通緝等級的敵人生成間隔（秒）
const ENEMY_SPAWN_WAIT: Array = [8.0, 4.5, 2.8, 1.7, 1.0, 0.6]
## 各通緝等級的目標在場敵人數
const ENEMY_DESIRED_COUNT: Array = [2, 3, 5, 7, 9, 11]

# ============================================================
# 通緝等級門檻（玩家等級 → 通緝等級）
# ============================================================
const WANTED_LEVEL_THRESHOLDS: Array = [1, 3, 5, 7, 9]

# ============================================================
# 道具
# ============================================================
const POWERUP_SPAWN_INTERVAL: float = 14.0
const MAGNET_DURATION: float = 10.0
const HOURGLASS_DURATION: float = 15.0
const MAGNET_STRENGTH: float = 6500.0
const MAGNET_SPAWN_RATIO: float = 0.6    # 剩餘 0.4 = 沙漏

# ============================================================
# 敵人基礎數值（被 stage 覆寫）
# ============================================================
const ENEMY_BASE_MOVE_SPEED: float = 150.0
const ENEMY_BASE_DAMAGE: float = 10.0
const ENEMY_SHRINK_AMOUNT: float = 8.0
const ENEMY_EJECT_COUNT: int = 4
const ENEMY_TELEGRAPH_TIME: float = 0.5
const ENEMY_TELEGRAPH_STAGE_MIN: int = 2
const ENEMY_MAX_GLOBAL_PROJECTILES: int = 90

# ============================================================
# 敵人階段參數 [stage 0-5]
# 每個 Array: [move_speed, damage, shoot_interval, projectile_speed,
#              projectile_damage, burst_count, spread_degrees]
# ============================================================
const ENEMY_STAGE_PARAMS: Array = [
	[140.0, 8.0, 2.2, 420.0, 5.0, 1, 0.0],
	[165.0, 10.0, 1.8, 480.0, 6.0, 1, 0.0],
	[200.0, 12.0, 1.4, 560.0, 7.5, 1, 0.0],
	[240.0, 14.0, 1.1, 650.0, 9.0, 2, 10.0],
	[290.0, 16.0, 0.85, 740.0, 11.5, 3, 16.0],
	[340.0, 18.0, 0.65, 860.0, 14.5, 3, 22.0],
]

# ============================================================
# 投射物基礎值
# ============================================================
const PROJECTILE_BASE_SPEED: float = 400.0
const PROJECTILE_BASE_DAMAGE: float = 5.0

# ============================================================
# 玩家移動
# ============================================================
const PLAYER_MAX_SPEED: float = 950.0
const PLAYER_SPEED_FACTOR: float = 2.2
const PLAYER_ACCELERATION: float = 12.0
const PLAYER_DECELERATION: float = 14.0
const PLAYER_DEAD_ZONE_PX: float = 18.0
const PLAYER_KEYBOARD_SPEED: float = 650.0
const PLAYER_BOOST_MULTIPLIER: float = 1.6
const PLAYER_BOOST_STABILITY_COST: float = 8.0

# ============================================================
# 升級費用公式（回傳金幣費用）
# ============================================================
static func upgrade_cost(type: String, level: int) -> int:
	match type:
		"gravity":
			return 120 + level * 90
		"speed":
			return 150 + level * 110
		"magnet":
			return 140 + level * 100
	return 9999

# ============================================================
# 閒置 / 經濟
# ============================================================
const TRIAL_SKIN_CHANCE: float = 0.35
const IDLE_COIN_RATE_PER_MIN: float = 3.0
const IDLE_COIN_CAP_MINUTES: int = 240
const IDLE_COIN_DAILY_CAP: int = 600

# ============================================================
# 任務系統
# ============================================================
const DAILY_MISSION_COUNT: int = 3
const RUN_MISSION_COUNT: int = 2
const MISSION_DAILY_RESET_HOUR: int = 4  ## UTC+8 凌晨 4 點重置

# ============================================================
# Boss 戰鬥
# ============================================================
const BOSS_MAX_HP: float = 300.0
const BOSS_MOVE_SPEED: float = 130.0
const BOSS_CONTACT_DAMAGE: float = 35.0
const BOSS_CHARGE_SPEED: float = 550.0
const BOSS_CHARGE_DAMAGE: float = 50.0
const BOSS_ORBIT_RADIUS: float = 420.0
const BOSS_ORBIT_SPEED: float = 1.2          ## rad/s
const BOSS_PULL_DAMAGE_PER_HIT: float = 25.0 ## 黑洞吞噬每次造成的傷害
const BOSS_PULL_HIT_COOLDOWN: float = 0.5    ## 吞噬傷害冷卻（秒）
const BOSS_SCORE_VALUE: float = 200.0
const BOSS_STABILITY_REWARD: float = 60.0    ## 擊敗後回復穩定度
const BOSS_SPIRAL_BULLET_COUNT: int = 12
const BOSS_SPIRAL_SPEED: float = 320.0
const BOSS_SPIRAL_DAMAGE: float = 8.0
const BOSS_SUMMON_COUNT: int = 3
const BOSS_SPAWN_WANTED_LEVEL: int = 5       ## 通緝等級 5 觸發

# ============================================================
# 戰役
# ============================================================
const CAMPAIGN_LEVEL_COUNT: int = 4
const CAMPAIGN_VORTEX_TANGENTIAL_STRENGTH: float = 900.0
