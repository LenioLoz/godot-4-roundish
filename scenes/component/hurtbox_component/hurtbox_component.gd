extends Area2D
class_name HurtboxComponent

@export var health_component: HealthComponent
@export var debug_log: bool = false


func _ready():
	# Połączenie sygnału jest w .tscn; nie łączymy ręcznie.
	# Upewnij się, że nasłuch jest włączony
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)


func _on_area_entered(area: Area2D) -> void:
	if debug_log:
		print("[Hurtbox] area_entered from=", area, " layer=", area.collision_layer, " mask=", area.collision_mask)
	if not area is HitboxComponent:
		return
	if health_component == null:
		return
	var hitbox_component = area as HitboxComponent
	health_component.damage(hitbox_component.damage)
	# If the incoming hitbox belongs to a projectile, remove it on hit
	var hit_owner := area.get_parent()
	if is_instance_valid(hit_owner) and hit_owner.is_in_group("projectile"):
		hit_owner.queue_free()
