extends RefCounted
class_name MapEventBase
## 地圖事件基底類別
## 所有地圖專屬機制繼承此類別，覆寫對應方法

var main_ref: Node = null          # Main.gd reference
var black_hole_ref: Node = null    # BlackHole node
var player_ctrl_ref: Node = null   # PlayerController node
var spawn_mgr_ref: Node = null     # SpawnManager node
var camera_ref: Camera2D = null
var _active: bool = false

## 地圖事件顯示名稱（HUD 用）
func get_event_name() -> String:
	return ""

## 地圖事件簡短描述（HUD 提示）
func get_event_description() -> String:
	return ""

## 啟動事件：遊戲開始時呼叫
func activate(main: Node, black_hole: Node, player_ctrl: Node, spawn_mgr: Node, camera: Camera2D) -> void:
	main_ref = main
	black_hole_ref = black_hole
	player_ctrl_ref = player_ctrl
	spawn_mgr_ref = spawn_mgr
	camera_ref = camera
	_active = true
	_on_activate()

## 子類覆寫：啟動時的額外邏輯
func _on_activate() -> void:
	pass

## 每幀更新（由 Main._process / _physics_process 呼叫）
func process(delta: float) -> void:
	pass

## 物理幀更新
func physics_process(delta: float) -> void:
	pass

## 停止事件：遊戲結束 / 回到主選單
func deactivate() -> void:
	_active = false
	_on_deactivate()

## 子類覆寫：停止時的清理邏輯
func _on_deactivate() -> void:
	pass

## 是否正在運行
func is_active() -> bool:
	return _active
