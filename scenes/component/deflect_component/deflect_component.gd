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

# Active state visual (constant tint when deflect is active)
var _active: bool = false
@export var active: bool:
	set(value):
		if _active == value:
			return
		_active = value
		_apply_active_tint()
		_apply_hurtbox_block()
		# In the editor, avoid deferred calls to prevent progress dialog warnings
		if Engine.is_editor_hint():
			return
		# Enable/disable collision monitoring based on active state
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

# Editable hitbox exports
@export var use_custom_shape: bool = false
@export var custom_shape: Shape2D
@export_enum("Circle", "Rectangle", "Capsule") var shape_type: int = 0
@export var circle_radius: float = 18.0
@export var rect_size: Vector2 = Vector2(36, 18)
@export var capsule_radius: float = 10.0
@export var capsule_height: float = 20.0

func _ready() -> void:
	_resolve_target()
	_setup_shader()
	_apply_shape_settings()
	_apply_active_tint()
	# In the editor, avoid enabling runtime collision and signal logic
	if Engine.is_editor_hint():
		return
	# Start with monitoring depending on current active state
	set_deferred("monitoring", active)
	set_deferred("monitorable", active)
	connect("area_entered", Callable(self, "_on_area_entered"))
	_resolve_hurtbox()
	_apply_hurtbox_block()

## set/get handled inline on `active` property above

func _resolve_hurtbox() -> void:
	var host = owner if owner != null else get_parent()
	if host != null:
		_hurtbox = host.get_node_or_null("HurtboxComponent") as Area2D

func _get_collision_shape() -> CollisionShape2D:
	# Rely on shape provided in the scene; avoid creating children during setup
	return get_node_or_null("CollisionShape2D") as CollisionShape2D

func _apply_shape_settings() -> void:
	var cs := _get_collision_shape()
	if cs == null:
		return
	if use_custom_shape and custom_shape != null:
		cs.shape = custom_shape
		return
	match shape_type:
		0:
			var s := cs.shape as CircleShape2D
			if s == null:
				s = CircleShape2D.new()
				cs.shape = s
			s.radius = circle_radius
		1:
			var r := cs.shape as RectangleShape2D
			if r == null:
				r = RectangleShape2D.new()
				cs.shape = r
			r.size = rect_size
		2:
			var c := cs.shape as CapsuleShape2D
			if c == null:
				c = CapsuleShape2D.new()
				cs.shape = c
			c.radius = capsule_radius
			c.height = capsule_height
		_:
			pass

#func _notification(what):
	#if Engine.is_editor_hint() and what == NOTIFICATION_EDITOR_PROPERTY_CHANGED:
		#_apply_shape_settings()

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
	# Ensure base tint is initialized
	_mat.set_shader_parameter("tint", active_tint if active else inactive_tint)

func _on_area_entered(area: Area2D) -> void:
	# Only react when deflect is active
	if not active:
		return
	# Projectiles
	if affects_projectiles and _try_reflect_projectile(area):
		_do_flash()
		return
	# Melee
	if affects_melee and _try_parry_melee(area):
		_do_flash()
		return

func _try_reflect_projectile(area: Area2D) -> bool:
	var projectile_owner = area.get_parent()
	if projectile_owner == null:
		return false
	if not projectile_owner.is_in_group("projectile"):
		return false
	var id = projectile_owner.get_instance_id()
	var now = Time.get_ticks_msec()
	if _last_reflect.has(id) and int(now) - int(_last_reflect[id]) < reflect_cooldown_ms:
		return true
	_last_reflect[id] = now
	# Try to flip bullet direction (robust property access)
	var _dir_val = null
	if projectile_owner.has_method("get"):
		_dir_val = projectile_owner.get("dir")
	if typeof(_dir_val) == TYPE_FLOAT or typeof(_dir_val) == TYPE_INT:
		projectile_owner.set("dir", float(_dir_val) + PI)
	# Optional: rotate sprite if present (not required for logic)
	if projectile_owner.has_method("set_rotation"):
		projectile_owner.set_rotation(projectile_owner.rotation + PI)
	return true

func _try_parry_melee(area: Area2D) -> bool:
	# Only parry non-projectile hitboxes
	if not (area is HitboxComponent):
		return false
	var attacker = area.get_parent()
	if attacker == null:
		return false
	if attacker.is_in_group("projectile"):
		return false
	# Avoid self-damage: if attacker shares player group with host, skip
	var host = owner if owner != null else get_parent()
	if host != null and host.is_in_group("player"):
		var node = attacker
		while node != null:
			if node.is_in_group("player"):
				return false
			node = node.get_parent()
	# Find HealthComponent upwards from attacker
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
	# Refresh preview in editor without relying on editor-only constants
	if Engine.is_editor_hint():
		_apply_shape_settings()
		_apply_active_tint()

func _apply_hurtbox_block() -> void:
	# Do not toggle hurtbox while in editor to prevent editor-time collisions
	if Engine.is_editor_hint():
		return
	if _hurtbox == null:
		_resolve_hurtbox()
	if _hurtbox == null:
		return
	# When deflect is active, disable hurtbox so it doesn't take damage
	_hurtbox.set_deferred("monitoring", not active)
	_hurtbox.set_deferred("monitorable", not active)
