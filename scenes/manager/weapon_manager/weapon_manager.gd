extends Node

@export var ak47: PackedScene
@export var sword: PackedScene
@export var deflect_shield: PackedScene

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
		_equip_ak47(weapon_layer)
		get_viewport().set_input_as_handled()
	elif  event.is_action_pressed("deflect"):
		_equip_deflect_shield(weapon_layer)
		get_viewport().set_input_as_handled()

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


func _equip_deflect_shield(weapon_layer: Node) -> void:
	var deflect_shield_node = weapon_layer.get_node_or_null("Deflect_shield")
	if not is_instance_valid(deflect_shield_node):
		if deflect_shield:
			var deflect_shield_instance = deflect_shield.instantiate() as Node2D
			weapon_layer.add_child(deflect_shield_instance)
			
