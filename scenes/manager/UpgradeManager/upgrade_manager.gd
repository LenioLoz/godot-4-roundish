extends Node

@export var upgrade_pool: Array[Upgrade]
@export var enemy: PackedScene

var current_upgrades = {}
var acquired_list: Array[Upgrade] = []

const UPGRADE_SCREEN_SCENE := preload("res://scenes/ui/upgrade_s_creen.tscn")

func _ready() -> void:
	randomize()
	add_to_group("upgrade_manager")
	# Debug: log configured upgrade pool ids and max_quantity
	var dbg_ids := []
	for u in upgrade_pool:
		if u != null and u.has_method("get"):
			var iid = u.get("id")
			var mq = u.get("max_quantity") if u.has_method("get") else -1
			dbg_ids.append("%s(max=%s)" % [str(iid), str(mq)])
	print("[UpgradeManager] Pool:", ", ".join(dbg_ids))

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
	# Build available pool based on max_quantity
	var pool: Array[Upgrade] = []
	for u in upgrade_pool:
		if _is_upgrade_available(u):
			pool.append(u)
	if pool.is_empty():
		return result
	# Force-include shotgun when available
	var sg: Upgrade = null
	for u in pool:
		var uid := ""
		if u != null and u.has_method("get"):
			var v = u.get("id")
			if typeof(v) == TYPE_STRING:
				uid = v
		if uid == "shotgun":
			sg = u
			break
	var picks_left = count
	if sg != null and picks_left > 0:
		result.append(sg)
		picks_left -= 1
		# Remove sg from pool
		var filtered: Array[Upgrade] = []
		for u2 in pool:
			if u2 != sg:
				filtered.append(u2)
		pool = filtered
	# Shuffle remaining pool
	for i in range(pool.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var n = min(picks_left, pool.size())
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

	# If shotgun is acquired, remove full_auto from future options
	if chosen_upgrade.id == "shotgun":
		upgrade_pool = upgrade_pool.filter(func(u: Upgrade): return u.id != "full_auto")

	# If this upgrade reached its max quantity, remove it from the pool
	var qty: int = int(current_upgrades[chosen_upgrade.id]["quantity"])
	var maxq: int = 0
	if chosen_upgrade != null and chosen_upgrade.has_method("get"):
		var v = chosen_upgrade.get("max_quantity")
		if typeof(v) == TYPE_INT:
			maxq = v
	if maxq > 0 and qty >= maxq:
		upgrade_pool = upgrade_pool.filter(func(u: Upgrade): return u.id != chosen_upgrade.id)

func _is_upgrade_available(u: Upgrade) -> bool:
	if u == null:
		return false
	var maxq: int = 0
	if u.has_method("get"):
		var v = u.get("max_quantity")
		if typeof(v) == TYPE_INT:
			maxq = v
	if maxq <= 0:
		return true
	var qty: int = 0
	if current_upgrades.has(u.id):
		var entry = current_upgrades[u.id]
		if typeof(entry) == TYPE_DICTIONARY and entry.has("quantity"):
			qty = int(entry["quantity"])
	return qty < maxq

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
