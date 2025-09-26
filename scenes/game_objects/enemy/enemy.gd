extends CharacterBody2D

var _deflect_enabled: bool = true
@export var deflect_enabled: bool:
	set(value):
		_deflect_enabled = value
		# Apply immediately when possible; defer if not inside tree yet
		if Engine.is_editor_hint():
			return
		if is_inside_tree():
			_apply_deflect_toggle()
		else: 
			call_deferred("_apply_deflect_toggle")
	get:
		return _deflect_enabled

@onready var health: HealthComponent = get_node_or_null("HealthComponent")
@onready var deflect: DeflectComponent = get_node_or_null("DeflectComponent")
# Avoid cyclic preload of this scene which caused "Busy" parse error
var ammo_component: PackedScene = preload("res://scenes/component/AmmoComponent/ammo_component.tscn")
func _ready() -> void:
	# [style] Indentation below uses tabs
	if health != null:
		health.died.connect(Callable(self, "_on_died"))
	# Apply deflect toggle from export with hard safeguards
	_apply_deflect_toggle()
	# Ensure enemy Hurtbox is enabled so it can receive damage
	# We force monitoring/monitorable to true regardless of Deflect state
	# to avoid any timing/race where Deflect changes it during _ready.
	var hb := get_node_or_null("HurtboxComponent") as Area2D
	if hb != null:
		hb.set_deferred("monitoring", true)
		hb.set_deferred("monitorable", true)
	# Ensure enemy sprite uses shared shader material without replacing existing refs
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		# Reset CanvasItem modulate to neutral white (doesn't replace material)
		spr.modulate = Color(1,1,1,1)
		var sm := spr.material as ShaderMaterial
		if sm == null:
			sm = ShaderMaterial.new()
			spr.material = sm
		if sm.shader == null:
			sm.shader = load("res://scenes/shaders/flash_tint.gdshader")
		# Initialize neutral defaults; components (FlashOnHit/Deflect) will modify live instance
		sm.set_shader_parameter("tint", Color(1, 1, 1, 1))
		sm.set_shader_parameter("desaturate", 0.0)
		sm.set_shader_parameter("flash", 0.0)
		sm.set_shader_parameter("flash_color", Vector3(1, 1, 1))
		sm.set_shader_parameter("opacity", 1.0)

func _on_died() -> void:
	# Notify UpgradeManager about the kill so it can grant upgrades
	var mgr = get_tree().get_first_node_in_group("upgrade_manager")
	if mgr != null and mgr.has_method("on_enemy_killed"):
		mgr.on_enemy_killed(self)
	# Capture transform before this node is freed
	var pos := global_position
	var rot := global_rotation
	# Use a detached helper that survives after this node is freed
	var spawner := DelayedSpawner.new()
	var path := scene_file_path
	var next_scene: PackedScene = null
	if path != "":
		next_scene = load(path)
	if next_scene == null:
		next_scene = load("res://scenes/game_objects/enemy/enemy.tscn")
	spawner.scene = next_scene
	spawner.pos = pos
	spawner.rot = rot
	spawner.delay = 0.2
	spawner.parent_path = NodePath("/root/Main")
	get_tree().root.add_child(spawner)

func _apply_deflect_toggle() -> void:
	if deflect == null:
		return
	# Set logical active flag
	deflect.active = deflect_enabled
	# Force collision state to match toggle (belt-and-braces)
	deflect.set_deferred("monitoring", deflect_enabled)
	deflect.set_deferred("monitorable", deflect_enabled)
	# Also clamp collision layers/masks so disabled deflect cannot detect anything
	if deflect_enabled:
		deflect.collision_layer = 1
		deflect.collision_mask = 2
		# Ensure tint doesn't colorize sprite when active
		deflect.active_tint = Color(1,1,1,1)
		deflect.inactive_tint = Color(1,1,1,1)
	else:
		deflect.collision_layer = 0
		deflect.collision_mask = 0
	# Ensure enemy hurtbox remains enabled regardless of deflect
	var hb := get_node_or_null("HurtboxComponent") as Area2D
	if hb != null:
		hb.set_deferred("monitoring", true)
		hb.set_deferred("monitorable", true)
