extends Node
class_name  HealthComponent

signal died
signal health_changed

@export var max_health: float=10
var current_health:float
var is_dead: bool = false

func _ready() -> void:
	current_health = max_health


func damage(damage_amount: float):
	if is_dead:
		return
	current_health = max(current_health-damage_amount,0)
	health_changed.emit()
	Callable(check_death).call_deferred()


func check_death():
	if is_dead:
		return
	if current_health ==0:
		is_dead = true
		died.emit()
		owner.queue_free()
