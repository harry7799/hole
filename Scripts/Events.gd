extends Node
## Events — 輕量事件匯流排 (Autoload)
## 解耦 Manager 之間的信號依賴。
## 用法：Events.score_changed.emit(new_score)
##       Events.score_changed.connect(_on_score_changed)

# 遊戲狀態
@warning_ignore("unused_signal")
signal score_changed(new_score: int)
@warning_ignore("unused_signal")
signal level_up(new_level: int)
@warning_ignore("unused_signal")
signal game_over(reason: String)
@warning_ignore("unused_signal")
signal game_started()

# Fever
@warning_ignore("unused_signal")
signal fever_started(duration: float)
@warning_ignore("unused_signal")
signal fever_ended()

# 戰鬥
@warning_ignore("unused_signal")
signal wanted_level_changed(new_level: int)
@warning_ignore("unused_signal")
signal enemy_killed(enemy: Node, position: Vector2)
@warning_ignore("unused_signal")
signal boss_defeated(boss: Node)

# 經濟
@warning_ignore("unused_signal")
signal coins_changed(new_amount: int)

# 道具
@warning_ignore("unused_signal")
signal powerup_collected(type: String)
@warning_ignore("unused_signal")
signal combo_updated(count: int, multiplier: float)

# 任務
@warning_ignore("unused_signal")
signal mission_progress(mission_id: String, current: int, target: int)
@warning_ignore("unused_signal")
signal mission_completed(mission_id: String, reward: int)
@warning_ignore("unused_signal")
signal run_missions_generated()
