extends Node
class_name AmmoComponent

signal ammo_changed(current: int, max: int)
signal reload_started()
signal reload_finished()

@export var max_ammo: int = 15
var current_ammo: int = 0
@export var reload_time_s: float = 1.0
var is_reloading: bool = false

func _ready() -> void:
	add_to_group("ammo_component")
	if current_ammo <= 0:
		current_ammo = max_ammo
	current_ammo = clamp(current_ammo, 0, max_ammo)
	ammo_changed.emit(current_ammo, max_ammo)

func can_fire() -> bool:
	return not is_reloading and current_ammo > 0

func consume(amount: int = 1) -> bool:
	if not can_fire():
		return false
	current_ammo = max(0, current_ammo - amount)
	ammo_changed.emit(current_ammo, max_ammo)
	return true

func start_reload() -> void:
	if is_reloading:
		return
	if current_ammo >= max_ammo:
		return
	is_reloading = true
	reload_started.emit()
	var t = get_tree().create_timer(reload_time_s)
	await t.timeout
	current_ammo = max_ammo
	is_reloading = false
	ammo_changed.emit(current_ammo, max_ammo)
	reload_finished.emit()
