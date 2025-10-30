extends Area2D
class_name HurtboxComponent

@export var health_component: HealthComponent
@export var debug_log: bool = false

func _ready():
	# Połączenie sygnału jest w .tscn; włącz nasłuch ręcznie na starcie.
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
	# Blokada obrażeń od własnych hitboxów (miecz/pocisk).
	# Po odbiciu pocisku (deflect) owner_id zostaje przepisany na odbijającego,
	# więc trafienie pierwotnego strzelca przejdzie (owner_id != victim_id).
	var victim_id := _get_victim_owner_id()
	if hitbox_component.owner_id != 0 and hitbox_component.owner_id == victim_id:
		return
	health_component.damage(hitbox_component.damage)
	# Jeśli hitbox należy do pocisku, usuń go po trafieniu
	var hit_owner := area.get_parent()
	if is_instance_valid(hit_owner) and hit_owner.is_in_group("projectile"):
		hit_owner.queue_free()

func _get_victim_owner_id() -> int:
	# Spróbuj wyciągnąć ID właściciela (authority) z węzła gracza nad hurtboxem
	var node: Node = owner if owner != null else get_parent()
	while node != null:
		if node.is_in_group("player"):
			if node.has_method("get_multiplayer_authority"):
				return int(node.get_multiplayer_authority())
			var nm := String(node.name)
			if nm.is_valid_int():
				return int(nm)
			break
		node = node.get_parent()
	return 0

