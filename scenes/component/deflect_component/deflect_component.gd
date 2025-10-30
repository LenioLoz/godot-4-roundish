@tool
extends Area2D
class_name DeflectComponent

@export var target_path: NodePath
@export var affects_projectiles: bool = true
@export var affects_melee: bool = true
@export var melee_return_damage: float = 5.0
@export var reflect_cooldown_ms: int = 80

@export var flash_color: Color = Color(0.4, 0.6, 1.0, 1.0)
@export var flash_amount: float = 0.7
@export var flash_duration: float = 0.2

var _active: bool = false
@export var active: bool:
	set(value):
		if _active == value:
			return
		_active = value
		_apply_active_tint()
		_apply_hurtbox_block()
		if Engine.is_editor_hint():
			return
		set_deferred("monitoring", _active)
		set_deferred("monitorable", _active)
	get:
		return _active

@export var active_tint: Color = Color(0.6, 0.8, 1.0, 1.0)
@export var inactive_tint: Color = Color(1, 1, 1, 1)

var _target: CanvasItem = null
var _mat: ShaderMaterial = null
var _last_reflect: Dictionary = {}
var _hurtbox: Area2D = null

func _ready() -> void:
	_resolve_target()
	_setup_shader()
	_apply_active_tint()
	if Engine.is_editor_hint():
		return
	set_deferred("monitoring", active)
	set_deferred("monitorable", active)
	connect("area_entered", Callable(self, "_on_area_entered"))
	_resolve_hurtbox()
	_apply_hurtbox_block()

func _resolve_target() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path) as CanvasItem
	if _target == null:
		var host = owner if owner != null else get_parent()
		if host != null:
			_target = host.get_node_or_null("AnimatedSprite2D") as CanvasItem
			if _target == null:
				_target = host.get_node_or_null("Sprite2D") as CanvasItem

func _setup_shader() -> void:
	if _target == null:
		return
	var sm = _target.material as ShaderMaterial
	if sm == null:
		sm = ShaderMaterial.new()
		_target.material = sm
	if sm.shader == null:
		sm.shader = load("res://scenes/shaders/flash_tint.gdshader")
	_mat = sm
	_mat.set_shader_parameter("flash", 0.0)
	_mat.set_shader_parameter("tint", active_tint if active else inactive_tint)

func _on_area_entered(area: Area2D) -> void:
	if not active:
		return
	# Always try to reflect projectiles when active (ignore affects_projectiles flag)
	if _try_reflect_projectile(area):
		_do_flash()
		return
	# Optional: still allow melee parry according to flag
	if affects_melee and _try_parry_melee(area):
		_do_flash()
		return

func _try_reflect_projectile(area: Area2D) -> bool:
	var projectile_owner = area.get_parent()
	if projectile_owner == null:
		return false
	if not projectile_owner.is_in_group("projectile"):
		return false

	# --- Nie liczymy/nie używamy PID — odbijamy każdy pocisk bez transferu właściciela ---

	# Jeśli pocisk potrafi obsłużyć RPC odbicia, wywołaj je (z zachowaniem obecnego ownera)
	if projectile_owner.has_method("rpc_reflect"):
		# Jeżeli rpc_reflect oczekuje argumentu new_owner_id, podajemy obecnego ownera, 
		# aby nie zmieniać właściciela (możesz też zmodyfikować rpc_reflect, by przyjmowało brak argumentu).
		var current_owner_id := 0
		if projectile_owner.has_method("get") and projectile_owner.has("owner_id"):
			current_owner_id = int(projectile_owner.get("owner_id"))
		projectile_owner.rpc("rpc_reflect", current_owner_id)
	else:
		# Local fallback: tylko odwróć kierunek / rotację / velocity bez zmiany ownera
		if projectile_owner is Node2D:
			(projectile_owner as Node2D).rotation += PI
		if projectile_owner.has_method("get") and projectile_owner.has_method("set"):
			var d = projectile_owner.get("dir") if projectile_owner.has("dir") else null
			if d != null and (typeof(d) == TYPE_FLOAT or typeof(d) == TYPE_INT):
				# jeżeli dir jest kątem (float), dodaj PI
				projectile_owner.set("dir", float(d) + PI)
			var r = projectile_owner.get("rotat") if projectile_owner.has("rotat") else null
			if r != null and (typeof(r) == TYPE_FLOAT or typeof(r) == TYPE_INT):
				projectile_owner.set("rotat", float(r) + PI)
			var vel = projectile_owner.get("velocity") if projectile_owner.has("velocity") else null
			if vel != null and typeof(vel) == TYPE_VECTOR2:
				projectile_owner.set("velocity", -vel)
			var dir_v = projectile_owner.get("direction") if projectile_owner.has("direction") else null
			if dir_v != null and typeof(dir_v) == TYPE_VECTOR2:
				projectile_owner.set("direction", -dir_v)

		# NIE przenosimy owner_id ani nie dotykamy hitbox.owner_id
		# e.g. nie wykonujemy: projectile_owner.set("owner_id", pid)

	return true


func _try_parry_melee(area: Area2D) -> bool:
	if not (area is HitboxComponent):
		return false
	var attacker = area.get_parent()
	if attacker == null:
		return false
	if attacker.is_in_group("projectile"):
		return false
	var host = owner if owner != null else get_parent()
	if host != null and host.is_in_group("player"):
		var node: Node = attacker
		while node != null:
			if node.is_in_group("player"):
				return false
			node = node.get_parent()
	var cur = attacker
	while cur != null:
		var hc = cur.get_node_or_null("HealthComponent") as HealthComponent
		if hc != null:
			hc.damage(melee_return_damage)
			return true
		cur = cur.get_parent()
	return false

func _do_flash() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("flash_color", flash_color)
	_mat.set_shader_parameter("flash", flash_amount)
	if flash_duration <= 0.0:
		await get_tree().process_frame
		_mat.set_shader_parameter("flash", 0.0)
		return
	var tw = create_tween()
	tw.tween_method(func(v): _mat.set_shader_parameter("flash", v), flash_amount, 0.0, flash_duration)

func _apply_active_tint() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("tint", active_tint if active else inactive_tint)

func _notification(_what):
	if Engine.is_editor_hint():
		_apply_active_tint()

func _resolve_hurtbox() -> void:
	var host = owner if owner != null else get_parent()
	if host != null:
		_hurtbox = host.get_node_or_null("HurtboxComponent") as Area2D

func _apply_hurtbox_block() -> void:
	if Engine.is_editor_hint():
		return
	if _hurtbox == null:
		_resolve_hurtbox()
	if _hurtbox == null:
		return
	_hurtbox.set_deferred("monitoring", not active)
	_hurtbox.set_deferred("monitorable", not active)
