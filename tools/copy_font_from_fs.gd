@tool
extends Node

# Editor helper: copy a local OTF/TTF from an absolute filesystem path into res://Fonts/
# Usage:
# 1. Open this script in the Editor, set `source_path` to your local font file (e.g. C:\\Users\\User\\Downloads\\NotoSansTC-Regular.otf)
# 2. Press the "Run" button in the Script editor or instance the node and call `copy_font()` from the Editor
# 3. Restart/reload the project so Godot detects the new resource.

@export var source_path: String = "C:\\Users\\User\\Downloads\\NotoSansTC-Regular.otf"
@export var target_name: String = "NotoSansTC-Regular.otf"

func _ready():
	if not Engine.is_editor_hint():
		return
	print("copy_font: loaded. Set `source_path` and call copy_font() (or press Run) to copy into res://Fonts/)")

func copy_font() -> void:
	if not FileAccess.file_exists(source_path):
		push_error("copy_font: source not found: %s" % source_path)
		return
	var fonts_dir := "res://Fonts"
	var dir := DirAccess.open(fonts_dir)
	if not dir:
		var root := DirAccess.open("res://")
		if not root:
			push_error("copy_font: cannot access res://")
			return
		root.make_dir("Fonts")
	# read source
	var src := FileAccess.open(source_path, FileAccess.ModeFlags.READ)
	if src == null:
		push_error("copy_font: cannot open source file for reading: %s" % source_path)
		return
	var size := src.get_length()
	var data := src.get_buffer(size)
	src.close()
	# write destination
	var out_path := fonts_dir + "/" + target_name
	var f := FileAccess.open(out_path, FileAccess.ModeFlags.WRITE)
	if f == null:
		push_error("copy_font: cannot open %s for writing" % out_path)
		return
	f.store_buffer(data)
	f.close()
	print("copy_font: copied %s -> %s" % [source_path, out_path])
	print("copy_font: restart editor or reload project to pick up the font")
