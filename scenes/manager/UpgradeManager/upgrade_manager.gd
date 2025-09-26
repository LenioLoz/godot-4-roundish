extends Node

@export var upgrade_pool: Array[Upgrade]
@export var enemy: PackedScene

var current_upgrades = {}
var acquired_list: Array[Upgrade] = []

const UPGRADE_SCREEN_SCENE := preload("res://scenes/ui/upgrade_s_creen.tscn")

func _ready() -> void:
	add_to_group("upgrade_manager")

func on_enemy_killed(_enemy: Node = null) -> void:
	# Pick two upgrade options
	var options := choose_upgrades(2)
	if options.is_empty():
		return
	# Show interactive upgrade screen before applying upgrade
	var screen := _show_upgrade_screen(options)
	# Pause the game while selecting
	get_tree().paused = true
	var selected: Upgrade = await screen.accepted
	# Resume and apply
	get_tree().paused = false
	_apply_upgrade(selected)
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_upgrade"):
		player.add_upgrade(selected)
	if is_instance_valid(screen):
		screen.queue_free()
	print("[UpgradeManager] Enemy killed -> granted:", selected.id)

func choose_random_upgrade() -> Upgrade:
	if upgrade_pool == null or upgrade_pool.is_empty():
		return null
	var idx = int(randi()) % upgrade_pool.size()
	return upgrade_pool[idx]

func choose_upgrades(count: int) -> Array[Upgrade]:
	var result: Array[Upgrade] = []
	if upgrade_pool == null or upgrade_pool.is_empty():
		return result
	# Make a shallow copy and shuffle to get unique choices
	var pool: Array[Upgrade] = []
	for u in upgrade_pool:
		pool.append(u)
	# Simple Fisher-Yates shuffle
	for i in range(pool.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var n = min(count, pool.size())
	for i in n:
		result.append(pool[i])
	return result

func _apply_upgrade(chosen_upgrade: Upgrade) -> void:
	if chosen_upgrade == null:
		return
	var has_upgrade = current_upgrades.has(chosen_upgrade.id)
	if !has_upgrade:
		current_upgrades[chosen_upgrade.id] = {
			"resource": chosen_upgrade,
			"quantity": 1
		}
	else:
		current_upgrades[chosen_upgrade.id]["quantity"] += 1
	acquired_list.append(chosen_upgrade)

func on_upgrade():
	# Optional manual trigger also uses interactive flow
	var options := choose_upgrades(2)
	if options.is_empty():
		return
	var screen := _show_upgrade_screen(options)
	get_tree().paused = true
	var selected: Upgrade = await screen.accepted
	get_tree().paused = false
	_apply_upgrade(selected)
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_upgrade"):
		player.add_upgrade(selected)
	if is_instance_valid(screen):
		screen.queue_free()
	print(current_upgrades)

func _show_upgrade_screen(upgrades: Array[Upgrade]) -> CanvasLayer:
	var screen: CanvasLayer = UPGRADE_SCREEN_SCENE.instantiate()
	# Ensure UI works during pause
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(screen)
	if screen.has_method("set_upgrade"):
		screen.set_upgrade(upgrades)
	return screen
