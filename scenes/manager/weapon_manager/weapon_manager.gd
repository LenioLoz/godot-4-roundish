extends Node

@export var ak47: PackedScene
@export var sword: PackedScene
@export var deflect_shield: PackedScene
@export var shotgun: PackedScene

func _unhandled_input(event: InputEvent) -> void:
	# Ignore repeated key press events to avoid double switching
	if event is InputEventKey and event.echo:
		return

	var weapon_layer = get_tree().get_first_node_in_group("weaponlayer")
	if weapon_layer == null:
		return

	if event.is_action_pressed("select_weapon_1"):
		_equip_sword(weapon_layer)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_weapon_2"):
		# If player has shotgun upgrade, block switching to AK47
		var parent_node = get_parent()
		var has_shotgun := false
		if parent_node and parent_node.has_method("get"):
			var ups = parent_node.get("upgrades")
			if typeof(ups) == TYPE_ARRAY:
				for upg in ups:
					if upg and upg.has_method("get") and upg.get("id") == "shotgun":
						has_shotgun = true
						break
		if not has_shotgun:
			_equip_ak47(weapon_layer)
		get_viewport().set_input_as_handled()
	elif  event.is_action_pressed("deflect"):
		_equip_deflect_shield(weapon_layer)
		get_viewport().set_input_as_handled()

func equip_shotgun() -> void:
	var weapon_layer = get_tree().get_first_node_in_group("weaponlayer")
	if weapon_layer == null:
		return
	_equip_shotgun(weapon_layer)

func _equip_sword(weapon_layer: Node) -> void:
	var ak47_node = weapon_layer.get_node_or_null("Ak47")
	if is_instance_valid(ak47_node):
		ak47_node.queue_free()

	var sword_node = weapon_layer.get_node_or_null("Sword")
	if not is_instance_valid(sword_node):
		if sword:
			var sword_instance = sword.instantiate()
			sword_instance.player = get_parent()
			sword_instance.melee_range = get_parent().get_node_or_null("MeleeRange")
			weapon_layer.add_child(sword_instance)

func _equip_ak47(weapon_layer: Node) -> void:
	var sword_node = weapon_layer.get_node_or_null("Sword")
	if is_instance_valid(sword_node):
		sword_node.queue_free()

	var ak47_node = weapon_layer.get_node_or_null("Ak47")
	if not is_instance_valid(ak47_node):
		if ak47:
			var ak47_instance = ak47.instantiate() as Node2D
			weapon_layer.add_child(ak47_instance)
			ak47_instance.position = Vector2(0, -9)

func _equip_shotgun(weapon_layer: Node) -> void:
	# Remove other weapons
	var ak47_node = weapon_layer.get_node_or_null("Ak47")
	if is_instance_valid(ak47_node):
		ak47_node.queue_free()
	var sword_node = weapon_layer.get_node_or_null("Sword")
	if is_instance_valid(sword_node):
		sword_node.queue_free()
	# Spawn shotgun if not present
	var shotgun_node = weapon_layer.get_node_or_null("Shotgun")
	if not is_instance_valid(shotgun_node):
		if shotgun:
			var shotgun_instance = shotgun.instantiate() as Node2D
			weapon_layer.add_child(shotgun_instance)
			shotgun_instance.position = Vector2(0, -9)


func _equip_deflect_shield(weapon_layer: Node) -> void:
	var deflect_shield_node = weapon_layer.get_node_or_null("Deflect_shield")
	if not is_instance_valid(deflect_shield_node):
		if deflect_shield:
			var deflect_shield_instance = deflect_shield.instantiate() as Node2D
			weapon_layer.add_child(deflect_shield_instance)
			# Place the shield exactly on the player in world space
			var p = get_parent() as Node2D
			if p and deflect_shield_instance is Node2D:
				deflect_shield_instance.global_position = p.global_position
			
