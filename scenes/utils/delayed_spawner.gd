extends Node
class_name DelayedSpawner

var scene: PackedScene
var pos: Vector2
var rot: float
var parent_path: NodePath = NodePath("/root/Main")
var delay: float = 0.2

func _ready() -> void:
	var timer := get_tree().create_timer(delay)
	await timer.timeout
	var parent = get_node_or_null(parent_path)
	if parent == null:
		parent = get_tree().current_scene
	if scene != null and parent != null:
		var inst = scene.instantiate()
		if inst is Node2D:
			(inst as Node2D).global_position = pos
			(inst as Node2D).global_rotation = rot
		parent.add_child(inst)
	queue_free()

