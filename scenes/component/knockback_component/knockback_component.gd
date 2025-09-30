extends Node
class_name KnockbackComponent

@export var decay_per_sec: float = 900.0
@export var scale_per_damage: float = 25.0
@export var max_speed: float = 500.0
@export var debug_log: bool = false

var _host: CharacterBody2D = null

func _ready() -> void:
	_host = owner as CharacterBody2D
	if _host == null:
		var p = get_parent()
		if p is CharacterBody2D:
			_host = p
	# Subscribe to Hurtbox signals to detect hits
	var hb = null
	if _host != null:
		hb = _host.get_node_or_null("HurtboxComponent")
	if hb != null and not hb.is_connected("area_entered", Callable(self, "_on_hurtbox_area_entered")):
		hb.connect("area_entered", Callable(self, "_on_hurtbox_area_entered"))

func add_impulse(dir: Vector2, strength: float) -> void:
	if _host == null:
		return
	if dir == Vector2.ZERO or strength <= 0.0:
		return
	_host.velocity += dir.normalized() * strength
	if debug_log:
		print("[Knockback] add_impulse dir=", dir, " strength=", strength, " host.vel=", _host.velocity)

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if not (area is HitboxComponent):
		return
	# Only apply knockback when player has the "knockback" upgrade
	if not _has_knockback_upgrade():
		return
	var proj_owner = area.get_parent()
	if not (is_instance_valid(proj_owner) and proj_owner.is_in_group("projectile")):
		return
	# Direction from projectile
	var dir_vec := Vector2.ZERO
	if proj_owner.has_method("get"):
		var v_dir = proj_owner.get("direction")
		if typeof(v_dir) == TYPE_VECTOR2 and v_dir != Vector2.ZERO:
			dir_vec = (v_dir as Vector2).normalized()
		else:
			var ang = proj_owner.get("dir")
			if typeof(ang) == TYPE_FLOAT or typeof(ang) == TYPE_INT:
				dir_vec = Vector2.RIGHT.rotated(float(ang)).normalized()
	if dir_vec == Vector2.ZERO and _host != null:
		dir_vec = (_host.global_position - proj_owner.global_position).normalized()
	# Strength: prefer explicit knockback_force on projectile
	var strength := 0.0
	if proj_owner.has_method("get"):
		var kb = proj_owner.get("knockback_force")
		if typeof(kb) == TYPE_FLOAT or typeof(kb) == TYPE_INT:
			strength = float(kb)
	if strength <= 0.0:
		var dmg := 0.0
		var hb2 = area as HitboxComponent
		if hb2 != null and typeof(hb2.damage) == TYPE_INT:
			dmg = float(hb2.damage)
		# Manual clamp to avoid negatives
		strength = dmg * scale_per_damage
		if strength < 0.0:
			strength = 0.0
	add_impulse(dir_vec, strength)

func _physics_process(delta: float) -> void:
	if _host == null:
		return
	# Damp host velocity so knockback decays naturally
	if _host.velocity.length() > 0.0:
		_host.velocity = _host.velocity.move_toward(Vector2.ZERO, decay_per_sec * delta)
	# Clamp top speed to prevent runaway
	var spd := _host.velocity.length()
	if spd > max_speed:
		_host.velocity = _host.velocity.normalized() * max_speed

func _has_knockback_upgrade() -> bool:
	var ply = get_tree().get_first_node_in_group("player")
	if ply == null:
		return false
	if ply.has_method("get"):
		var ups = ply.get("upgrades")
		if typeof(ups) == TYPE_ARRAY:
			for upg in ups:
				if upg and upg.has_method("get"):
					var idv = upg.get("id")
					if typeof(idv) == TYPE_STRING and idv == "knockback":
						return true
	return false
