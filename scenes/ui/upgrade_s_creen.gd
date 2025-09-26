extends CanvasLayer

signal accepted(upgrade: Upgrade)

@export var upgrade_card_scene: PackedScene
@onready var card_container: HBoxContainer = %CardContainer

var pending_upgrades: Array[Upgrade] = []
var _accepted_emitted := false

func _ready() -> void:
	# Ensure this UI works while the game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_upgrade(upgrades: Array[Upgrade]):
	# Reset state and clear previous cards
	_accepted_emitted = false
	pending_upgrades.clear()
	for child in card_container.get_children():
		child.queue_free()
	# Add new cards and store options
	for upgrade in upgrades:
		var card_instance = upgrade_card_scene.instantiate()
		card_container.add_child(card_instance)
		if card_instance.has_method("set_upgrade"):
			card_instance.set_upgrade(upgrade)
		# Connect card click to selection
		if card_instance.has_signal("clicked"):
			card_instance.clicked.connect(_on_card_clicked)
		pending_upgrades.append(upgrade)

func _on_card_clicked(upg: Upgrade) -> void:
	if _accepted_emitted:
		return
	_accepted_emitted = true
	emit_signal("accepted", upg)
