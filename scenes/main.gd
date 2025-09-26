extends Node

@export var enemy_scene: PackedScene

func spawn_enemy_at(pos: Vector2, rot: float) -> void:
	if enemy_scene == null:
		return
	var clone = enemy_scene.instantiate()
	if clone is Node2D:
		(clone as Node2D).global_position = pos
		(clone as Node2D).global_rotation = rot
	add_child(clone)
