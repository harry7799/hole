extends Node
class_name MapEventManager
## 地圖事件管理器
## 根據 meta_selected_map 自動啟動對應地圖的專屬機制

# 地圖 ID → 事件類別的對映表
# 地圖 ID 來自檔名（小寫、無副檔名），例如 "火山熔岩科幻場景"
const MAP_EVENT_REGISTRY: Dictionary = {
	"火山熔岩科幻場景": "volcano",
	"聖誕雪地科幻無限場景": "ice",
	"森林叢林科幻場景": "jungle",
}

var _current_event: MapEventBase = null
var _current_map_id: String = ""
var _event_label: Label = null   # HUD 上的地圖事件提示

## 根據地圖 ID 取得事件實例（若無對應事件則回傳 null）
func _create_event_for_map(map_id: String) -> MapEventBase:
	var event_type: String = MAP_EVENT_REGISTRY.get(map_id, "")
	match event_type:
		"volcano":
			return VolcanoMapEvent.new()
		"ice":
			return IceMapEvent.new()
		"jungle":
			return JungleMapEvent.new()
		_:
			return null


## 啟動地圖事件（由 Main._start_game 呼叫）
func start_map_event(map_id: String, main: Node, black_hole: Node, player_ctrl: Node, spawn_mgr: Node, camera: Camera2D) -> void:
	stop_map_event()
	_current_map_id = map_id
	_current_event = _create_event_for_map(map_id)
	if _current_event:
		_current_event.activate(main, black_hole, player_ctrl, spawn_mgr, camera)
		print("[MapEventManager] 啟動地圖事件：%s (%s)" % [_current_event.get_event_name(), map_id])


## 停止地圖事件（由 Main._enter_main_menu / game over 呼叫）
func stop_map_event() -> void:
	if _current_event and _current_event.is_active():
		_current_event.deactivate()
		print("[MapEventManager] 停止地圖事件：%s" % _current_map_id)
	_current_event = null
	_current_map_id = ""


## 每幀更新
func process_event(delta: float) -> void:
	if _current_event and _current_event.is_active():
		_current_event.process(delta)


## 物理幀更新
func physics_process_event(delta: float) -> void:
	if _current_event and _current_event.is_active():
		_current_event.physics_process(delta)


## 取得當前事件（供 UI 查詢）
func get_current_event() -> MapEventBase:
	return _current_event


## 是否有地圖事件正在運行
func has_active_event() -> bool:
	return _current_event != null and _current_event.is_active()
