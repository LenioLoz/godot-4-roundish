extends CanvasLayer
class_name AmmoHUD

var _label: Label
var _ammo: AmmoComponent = null
var _reloading: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 1
	_create_label()
	_update_text()
	# Periodically ensure we are connected to an ammo source
	var t := Timer.new()
	t.wait_time = 0.3
	t.autostart = true
	t.one_shot = false
	add_child(t)
	t.timeout.connect(_ensure_ammo_connected)

func _create_label() -> void:
	_label = Label.new()
	add_child(_label)
	# Anchor to bottom-right
	_label.anchor_left = 1.0
	_label.anchor_top = 1.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_right = -10
	_label.offset_bottom = -10
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.add_theme_font_size_override("font_size", 16)
	_label.text = "Ammo --/--"

func _ensure_ammo_connected() -> void:
	if is_instance_valid(_ammo) and _ammo.is_inside_tree():
		return
	# Try to find any AmmoComponent in the scene
	var nodes = get_tree().get_nodes_in_group("ammo_component")
	if nodes.size() == 0:
		return
	var candidate = nodes[0] as AmmoComponent
	if candidate == null:
		return
	_bind_ammo(candidate)

func _bind_ammo(ac: AmmoComponent) -> void:
	_ammo = ac
	_reloading = _ammo.is_reloading
	if not _ammo.ammo_changed.is_connected(_on_ammo_changed):
		_ammo.ammo_changed.connect(_on_ammo_changed)
	if not _ammo.reload_started.is_connected(_on_reload_started):
		_ammo.reload_started.connect(_on_reload_started)
	if not _ammo.reload_finished.is_connected(_on_reload_finished):
		_ammo.reload_finished.connect(_on_reload_finished)
	_update_text()

func _on_ammo_changed(current: int, maxv: int) -> void:
	_update_text(current, maxv)

func _on_reload_started() -> void:
	_reloading = true
	_update_text()

func _on_reload_finished() -> void:
	_reloading = false
	_update_text()

func _update_text(cur: int = -1, maxv: int = -1) -> void:
	if is_instance_valid(_ammo):
		var c = cur if cur >= 0 else _ammo.current_ammo
		var m = maxv if maxv >= 0 else _ammo.max_ammo
		var suffix = " (reloading)" if _reloading else ""
		_label.text = "Ammo %d/%d%s" % [c, m, suffix]
	else:
		_label.text = "Ammo --/--"
