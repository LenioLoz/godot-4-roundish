extends Node

@export var ak47: PackedScene
@export var sword: PackedScene
@export var deflect_shield: PackedScene
@export var shotgun: PackedScene

func _unhandled_input(event: InputEvent) -> void:
	# Only the authority of the owning player can change weapons
	if not _has_authority():
		return
	# Ignore repeated key press events to avoid double switching
	if event is InputEventKey and event.echo:
		return

	var weapon_layer = _get_weapon_layer()
	if weapon_layer == null:
		return

	if event.is_action_pressed("select_weapon_1"):
		# Broadcast equip to all peers (and apply locally)
		rpc("rpc_equip", "sword")
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
		if has_shotgun:
			# Broadcast equip to all peers (and apply locally)
			rpc("rpc_equip", "shotgun")
			get_viewport().set_input_as_handled()
		if not has_shotgun:
			# Broadcast equip to all peers (and apply locally)
			rpc("rpc_equip", "ak47")
		get_viewport().set_input_as_handled()
	elif  event.is_action_pressed("deflect"):
		# Broadcast equip to all peers (and apply locally)
		rpc("rpc_equip", "deflect")
		get_viewport().set_input_as_handled()

@rpc("any_peer", "call_local")
func rpc_equip(kind: String) -> void:
	# Ensure the RPC only affects the weapon manager of the player
	# who actually sent it (prevents host/client cross-equips).
	var sender_id := multiplayer.get_remote_sender_id()
	var expected_id := 0
	var parent_node := get_parent()
	if parent_node and parent_node.has_method("get_multiplayer_authority"):
		expected_id = parent_node.get_multiplayer_authority()
	else:
		expected_id = get_multiplayer_authority()
	# Allow local call_local execution (sender_id == 0) or when sender matches authority
	if sender_id != 0 and sender_id != expected_id:
		return

	var weapon_layer = _get_weapon_layer()
	if weapon_layer == null:
		return
	match kind:
		"sword":
			_equip_sword(weapon_layer)
		"ak47":
			_equip_ak47(weapon_layer)
		"shotgun":
			_equip_shotgun(weapon_layer)
		"deflect":
			_equip_deflect_shield(weapon_layer)

func _has_authority() -> bool:
	var ply = get_parent()
	if ply and ply.has_method("is_multiplayer_authority"):
		return ply.is_multiplayer_authority()
	return is_multiplayer_authority()

func equip_shotgun() -> void:
	var weapon_layer = _get_weapon_layer()
	if weapon_layer == null:
		return
	_equip_shotgun(weapon_layer)

func _get_weapon_layer() -> Node:
	var p = get_parent()
	if p:
		return p.get_node_or_null("Weapon")
	return null

func _equip_sword(weapon_layer: Node) -> void:
	var ak47_node = weapon_layer.get_node_or_null("Ak47")
	if is_instance_valid(ak47_node):
		ak47_node.queue_free()
		
	var shotgun_node = weapon_layer.get_node_or_null("Shotgun")
	if is_instance_valid(shotgun_node):
		shotgun_node.queue_free()

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
			# Bind weapon body to owning player for proper authority checks
			var body = ak47_instance.get_node_or_null("Ak47Body")
			if body and body.has_method("set"):
				body.set("player", get_parent())

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
			# Bind weapon body to owning player for proper authority checks
			var body = shotgun_instance.get_node_or_null("ShotgunBody")
			if body and body.has_method("set"):
				body.set("player", get_parent())


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
			
