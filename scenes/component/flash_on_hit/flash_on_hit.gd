extends Node
class_name FlashOnHit

@export var target_path: NodePath
@export var flash_color: Color = Color(1, 1, 1, 1)
@export var flash_amount: float = 0.8
@export var flash_duration: float = 0.3
@export var use_opacity: bool = false
@export var opacity_on_flash: float = 1.0
@export var debug_log: bool = false

var _target: CanvasItem
var _shader_material: ShaderMaterial
var _health: HealthComponent
var _last_health: float = -1.0

func _ready() -> void:
	_resolve_target()
	_setup_shader()
	_try_connect_health()
	_try_connect_hurtbox()

func _resolve_target() -> void:
	if target_path != NodePath(""):
		_target = get_node_or_null(target_path) as CanvasItem
	if _target == null:
		var n = owner if owner != null else get_parent()
		if n:
			_target = n.get_node_or_null("AnimatedSprite2D") as CanvasItem
			if _target == null:
				_target = n.get_node_or_null("Sprite2D") as CanvasItem
	if debug_log:
		if _target == null:
			print("[FlashOnHit] No target found (", self, ")")
		else:
			print("[FlashOnHit] Target:", _target)

func _setup_shader() -> void:
	if _target == null:
		return
	var sm = _target.material as ShaderMaterial
	if sm == null:
		sm = ShaderMaterial.new()
		_target.material = sm
	if sm.shader == null:
		sm.shader = load("res://scenes/shaders/flash_tint.gdshader")
	_shader_material = sm
	# Ensure neutral defaults so sprites don't stay tinted
	_shader_material.set_shader_parameter("tint", Color(1,1,1,1))
	_shader_material.set_shader_parameter("desaturate", 0.0)
	_shader_material.set_shader_parameter("flash", 0.0)
	_shader_material.set_shader_parameter("flash_color", Vector3(1,1,1))
	_shader_material.set_shader_parameter("opacity", 1.0)
	if debug_log:
		print("[FlashOnHit] Shader ready on:", _target)

func _try_connect_health() -> void:
	var n = owner if owner != null else get_parent()
	if n:
		_health = n.get_node_or_null("HealthComponent") as HealthComponent
	if _health:
		_last_health = _health.current_health
		_health.health_changed.connect(_on_health_changed)

func _on_health_changed() -> void:
	if _health == null:
		return
	if _last_health < 0:
		_last_health = _health.current_health
	var decreased = _health.current_health < _last_health
	_last_health = _health.current_health
	if debug_log:
		print("[FlashOnHit] Health changed, decreased=", decreased, " current=", _health.current_health)
	if decreased:
		trigger_flash()

func _try_connect_hurtbox() -> void:
	if _health != null:
		return
	var n = owner if owner != null else get_parent()
	if n:
		var hb = n.get_node_or_null("HurtboxComponent") as Area2D
		if hb:
			hb.area_entered.connect(_on_hurtbox_area_entered)

func _on_hurtbox_area_entered(_area: Area2D) -> void:
	trigger_flash()

func trigger_flash() -> void:
	if _shader_material == null:
		return
	if debug_log:
		print("[FlashOnHit] trigger_flash amount=", flash_amount, " duration=", flash_duration)
	_shader_material.set_shader_parameter("flash_color", flash_color)
	_shader_material.set_shader_parameter("flash", flash_amount)
	if use_opacity:
		_shader_material.set_shader_parameter("opacity", opacity_on_flash)
	if flash_duration <= 0.0:
		await get_tree().process_frame
		_shader_material.set_shader_parameter("flash", 0.0)
		if use_opacity:
			_shader_material.set_shader_parameter("opacity", 1.0)
		return

	var tw = create_tween()
	tw.tween_method(func(v): _shader_material.set_shader_parameter("flash", v), flash_amount, 0.0, flash_duration)
	if use_opacity:
		tw.tween_method(func(v): _shader_material.set_shader_parameter("opacity", v), opacity_on_flash, 1.0, flash_duration)
