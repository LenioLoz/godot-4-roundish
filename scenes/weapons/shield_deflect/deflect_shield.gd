extends Node2D
class_name DeflectShield

@export var affects_projectiles: bool = true
@export var affects_melee: bool = true
@export var melee_return_damage: float = 5.0
@export var reflect_cooldown_ms: int = 80

@export var player_path: NodePath
@export var melee_range_path: NodePath
@export var shield_node_path: NodePath = NodePath("Shield")
@export var area_path: NodePath = NodePath("Shield/Area2D")
@export var sprite_path: NodePath = NodePath("Shield/Sprite2D")

var _active := false
var _player: Node2D = null
var _melee_range: CollisionShape2D = null
var _last_reflect: Dictionary = {}
var _shield_node: Node2D = null
var _area: Area2D = null
var _sprite: CanvasItem = null
var _mat: ShaderMaterial = null
@export var rotation_offset_rad: float = 0.0

func _ready() -> void:
	_resolve_refs()
	_resolve_nodes()
	set_active(false)
	if _area:
		_area.connect("area_entered", _on_area_entered)
	_setup_shader()

func set_active(v: bool) -> void:
	_active = v
	if _area:
		_area.set_deferred("monitoring", v)
		_area.set_deferred("monitorable", v)
	if _shield_node:
		_shield_node.visible = v

func is_active() -> bool:
	return _active

func _on_area_entered(area: Area2D) -> void:
	# Always reflect projectiles when they touch the shield area
	if affects_projectiles and _try_reflect_projectile(area):
		_do_flash()
		return
	# Melee parry only while the shield is active
	if not _active:
		return
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
	var _dir_val = null
	if projectile_owner.has_method("get"):
		_dir_val = projectile_owner.get("dir")
	if typeof(_dir_val) == TYPE_FLOAT or typeof(_dir_val) == TYPE_INT:
		projectile_owner.set("dir", float(_dir_val) + PI)
	if projectile_owner.has_method("set_rotation"):
		projectile_owner.set_rotation(projectile_owner.rotation + PI)
	return true

func _try_parry_melee(area: Area2D) -> bool:
	if not (area is HitboxComponent):
		return false
	var attacker = area.get_parent()
	if attacker == null:
		return false
	if attacker.is_in_group("projectile"):
		return false
	var cur = attacker
	while cur != null:
		var hc = cur.get_node_or_null("HealthComponent") as HealthComponent
		if hc != null:
			hc.damage(melee_return_damage)
			return true
		cur = cur.get_parent()
	return false

func _resolve_refs() -> void:
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Node2D
	if melee_range_path != NodePath(""):
		_melee_range = get_node_or_null(melee_range_path) as CollisionShape2D
	if _player == null:
		var p = get_parent()
		while p != null and _player == null:
			if p.is_in_group("player"):
				_player = p as Node2D
			p = p.get_parent()
	if _melee_range == null and _player != null:
		_melee_range = _player.get_node_or_null("MeleeRange") as CollisionShape2D

func _resolve_nodes() -> void:
	if shield_node_path != NodePath(""):
		_shield_node = get_node_or_null(shield_node_path) as Node2D
	if area_path != NodePath(""):
		_area = get_node_or_null(area_path) as Area2D
	if sprite_path != NodePath(""):
		_sprite = get_node_or_null(sprite_path) as CanvasItem


func _setup_shader() -> void:
	if _sprite == null:
		return
	var sm = _sprite.material as ShaderMaterial
	if sm == null:
		sm = ShaderMaterial.new()
		_sprite.material = sm
	if sm.shader == null:
		sm.shader = load("res://scenes/shaders/flash_tint.gdshader")
	_mat = sm
	_mat.set_shader_parameter("tint", Color(1,1,1,1))
	_mat.set_shader_parameter("desaturate", 0.0)
	_mat.set_shader_parameter("flash", 0.0)
	_mat.set_shader_parameter("flash_color", Vector3(1,1,1))
	_mat.set_shader_parameter("opacity", 1.0)

func _do_flash() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("flash_color", Color(0.7, 0.9, 1.0, 1.0))
	_mat.set_shader_parameter("flash", 0.9)
	var tw = create_tween()
	tw.tween_method(func(v): _mat.set_shader_parameter("flash", v), 0.9, 0.0, 0.15)
