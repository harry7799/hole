@tool
extends Node

# Editor tool: download Noto Sans CJK TC (OTF) and install into res://Fonts/
# Usage: open this script in the Editor (or instance the node), it will auto-run once
# and save the font to res://Fonts/NotoSansTC-Regular.otf if possible.

@export var font_url: String = "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/TraditionalChinese/NotoSansTC-Regular.otf"
@export var target_name: String = "NotoSansTC-Regular.otf"
@export var fallback_zip_url: String = "https://noto-website-2.storage.googleapis.com/pkgs/NotoSansCJKtc-hinted.zip"
var _tried_zip: bool = false

func _ready():
	if not Engine.is_editor_hint():
		return
	var out_path := "res://Fonts/" + target_name
	if FileAccess.file_exists(out_path):
		print("install_noto: font already present at %s" % out_path)
		return
	print("install_noto: starting download of %s" % font_url)
	call_deferred("download_and_install")

func download_and_install() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed)
	var err := http.request(font_url)
	if err != OK:
		push_error("install_noto: failed to start HTTP request: %s" % str(err))

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code < 200 or response_code >= 300:
		if not _tried_zip and fallback_zip_url != "":
			print("install_noto: primary download failed (HTTP %d). Trying fallback zip..." % response_code)
			_tried_zip = true
			var http2 := HTTPRequest.new()
			add_child(http2)
			http2.request_completed.connect(_on_request_completed)
			var err2 := http2.request(fallback_zip_url)
			if err2 != OK:
				push_error("install_noto: failed to start fallback HTTP request: %s" % str(err2))
			return
		push_error("install_noto: download failed, HTTP %d" % response_code)
		return

	# If we reached here and _tried_zip is true, the body is likely a zip file; save to user:// for manual extraction
	if _tried_zip:
		var zip_path := "user://Noto_package.zip"
		var fzip := FileAccess.open(zip_path, FileAccess.ModeFlags.WRITE)
		if fzip == null:
			push_error("install_noto: cannot write zip to %s" % zip_path)
			return
		fzip.store_buffer(body)
		fzip.close()
		print("install_noto: primary OTF not found; saved fallback zip to %s" % zip_path)
		print("install_noto: please extract %s from the zip and copy it into res://Fonts/" % target_name)
		return

	var fonts_dir := "res://Fonts"
	var dir := DirAccess.open(fonts_dir)
	if not dir:
		var root := DirAccess.open("res://")
		if not root:
			push_error("install_noto: cannot access res://")
			return
		root.make_dir("Fonts")
		dir = DirAccess.open(fonts_dir)
	if not dir:
		push_error("install_noto: cannot create/open %s" % fonts_dir)
		return
	var out_path := fonts_dir + "/" + target_name
	var f := FileAccess.open(out_path, FileAccess.ModeFlags.WRITE)
	if f == null:
		push_error("install_noto: cannot open file for writing: %s" % out_path)
		return
	f.store_buffer(body)
	f.close()
	print("install_noto: saved font to %s" % out_path)
	print("install_noto: restart editor or reload scenes to apply the font")
