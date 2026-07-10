extends CanvasLayer
## WP2 — Tap-to-inspect bottom sheet (the touch-first stat card).
##
## One instance lives in BoardView; `open(info)` repopulates and slides it up.
## info = {texture: Texture2D or null, title: String, lines: Array of String}.
## Closes on: tap outside (the dim), swipe-down on the sheet, or the ✕ button.
## Pure presentation — reads nothing from GameState, mutates nothing.

const SHEET_H := 250.0

var _dim: ColorRect = null
var _panel: PanelContainer = null
var _art: TextureRect = null
var _title: Label = null
var _lines_box: VBoxContainer = null
var _drag_y0: float = -1.0
var _tween: Tween = null


func _init() -> void:
	layer = 25
	visible = false


func _ready() -> void:
	# Full-screen dim that also catches taps-outside to close.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.115, 0.14, 0.98)
	sb.border_color = Color(0.62, 0.44, 0.22)      # rust accent
	sb.border_width_top = 2
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -SHEET_H
	_panel.offset_bottom = 0.0
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_panel.add_child(row)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.custom_minimum_size = Vector2(200, 200)
	_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_art)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	var top := HBoxContainer.new()
	col.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.95, 0.91, 0.82))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	top.add_child(close_btn)

	_lines_box = VBoxContainer.new()
	_lines_box.add_theme_constant_override("separation", 3)
	col.add_child(_lines_box)


func is_open() -> bool:
	return visible


## Repopulate and slide the sheet up. `info` keys: texture, title, lines.
func open(info: Dictionary) -> void:
	_art.texture = info.get("texture")
	_art.visible = _art.texture != null
	_title.text = str(info.get("title", ""))
	for child in _lines_box.get_children():
		child.queue_free()
	for line in info.get("lines", []):
		var l := Label.new()
		l.text = str(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.88, 0.87, 0.84))
		_lines_box.add_child(l)
	visible = true
	_slide_in()


func close() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "offset_top", -SHEET_H + 60.0, 0.14)
	_tween.parallel().tween_property(_panel, "offset_bottom", 60.0, 0.14)
	_tween.parallel().tween_property(_dim, "modulate:a", 0.0, 0.14)
	_tween.tween_callback(hide)


## Slide up from just below the screen edge + fade the dim in.
func _slide_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.offset_top = -SHEET_H + 60.0
	_panel.offset_bottom = 60.0
	_dim.modulate.a = 0.0
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "offset_top", -SHEET_H, 0.18)
	_tween.parallel().tween_property(_panel, "offset_bottom", 0.0, 0.18)
	_tween.parallel().tween_property(_dim, "modulate:a", 1.0, 0.18)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


## Swipe-down on the sheet closes it (drag > 40 px). Mouse events cover touch
## via Godot's emulate_mouse_from_touch (project default).
func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag_y0 = event.position.y if event.pressed else -1.0
	elif event is InputEventMouseMotion and _drag_y0 >= 0.0:
		if event.position.y - _drag_y0 > 40.0:
			_drag_y0 = -1.0
			close()
