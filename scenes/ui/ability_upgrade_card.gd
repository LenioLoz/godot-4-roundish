extends PanelContainer

signal clicked(upgrade: Upgrade)

@onready var name_label: Label = %NameLabel
@onready var description_label: Label = %DescriptionLabel

@export var name_font_size: int = 18
@export var description_font_size: int = 12

var _upgrade: Upgrade

func _ready() -> void:
	# Ensure wrapping and smaller fonts
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", name_font_size)
	description_label.add_theme_font_size_override("font_size", description_font_size)

func set_upgrade(upgrade: Upgrade):
	_upgrade = upgrade
	name_label.text = upgrade.name
	description_label.text = upgrade.description

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _upgrade != null:
			emit_signal("clicked", _upgrade)
