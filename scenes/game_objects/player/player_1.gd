extends CharacterBody2D

const MAX_SPEED = 150
const ACCELERATION_SMOOTHING = 15
const DODGE_SPEED = 350

var is_dodging = false
var mouse_position: Vector2
var look_position: Vector2
@onready var _deflect: DeflectComponent = get_node_or_null("Deflect")
@export var deflect_shield_scene: PackedScene
var _active_shield: DeflectShield = null
@onready var _dodge_timer: Timer = null
var upgrades: Array[Upgrade] = []
var bullet_speed_multiplier: float = 1.0
var bullet_size_multiplier: float = 1.0
var bullet_damage_multiplier: float = 1.0
var dodge_speed_multiplier: float = 1.0
@export var dodge_cooldown_s: float = 0.6
var dodge_invulnerable: bool = false
@onready var _dodge_cd_timer: Timer = null
var _dodge_on_cooldown: bool = false
@export var deflect_duration_s: float = 2
@export var deflect_cooldown_s: float = 1.5
@onready var _deflect_timer: Timer = null
@onready var _deflect_cd_timer: Timer = null
var _deflect_on_cooldown: bool = false
var weapons_disabled: bool = false
var full_auto_enabled: bool = false
var fire_cooldown_multiplier: float = 1.0

func _ready() -> void:
	# Connect the animation finished signal to handle the end of the dodge
	$AnimatedSprite2D.connect("animation_finished", Callable(self, "_on_animation_finished"))
	# Ensure shader material on sprite (tint/flash)
	_ensure_sprite_shader()
	# Create internal timer used to end dodge if the animation signal fails
	_dodge_timer = Timer.new()
	_dodge_timer.one_shot = true
	add_child(_dodge_timer)
	_dodge_timer.timeout.connect(_on_dodge_timer_timeout)

	# Dodge cooldown timer
	_dodge_cd_timer = Timer.new()
	_dodge_cd_timer.one_shot = true
	add_child(_dodge_cd_timer)
	_dodge_cd_timer.timeout.connect(_on_dodge_cd_timeout)

	# Ensure deflect starts deactivated on player objects
	if _deflect:
		_deflect.active = false
	if _active_shield:
		_active_shield.set_active(false)

	# Deflect timers (duration and cooldown)
	_deflect_timer = Timer.new()
	_deflect_timer.one_shot = true
	add_child(_deflect_timer)
	_deflect_timer.timeout.connect(_on_deflect_timer_timeout)

	_deflect_cd_timer = Timer.new()
	_deflect_cd_timer.one_shot = true
	add_child(_deflect_cd_timer)
	_deflect_cd_timer.timeout.connect(_on_deflect_cd_timer_timeout)

	# Ensure Ammo HUD exists in the scene tree
	var hud_present := false
	for c in get_tree().root.get_children():
		if c is AmmoHUD:
			hud_present = true
			break
	if not hud_present:
		var hud := AmmoHUD.new()
		get_tree().root.add_child(hud)



func _physics_process(delta: float) -> void:

	# aktualizuj pozycję myszy względem gracza
	mouse_position = get_global_mouse_position()
	look_position = mouse_position - global_position

	# Flipowanie tylko w osi X (horyzontalnie)
	if look_position.x < 0:
		$AnimatedSprite2D.flip_h = true   # lewo
	else:
		$AnimatedSprite2D.flip_h = false  # prawo

	# Jeśli trwa unik – kontynuuj ruch z prędkością uniku
	if is_dodging:
		move_and_slide()
		return

	# --- Ruch normalny ---
	var movement_vector = get_movement_vector()
	var direction = movement_vector.normalized()

	# --- Dodge ---
	if Input.is_action_just_pressed("dodge"):
		if direction != Vector2.ZERO and not _dodge_on_cooldown:
			is_dodging = true
			velocity = direction * (DODGE_SPEED * dodge_speed_multiplier)
			$AnimatedSprite2D.play("dodge")
			# Hide weapon layer during dodge
			var weapon_layer = get_node_or_null("Weapon")
			if weapon_layer:
				weapon_layer.visible = false
			# Flash effect during dodge
			var sm := $AnimatedSprite2D.material as ShaderMaterial
			if sm:
				sm.set_shader_parameter("flash", 0.6)
				sm.set_shader_parameter("flash_color", Color(0.1, 0.1, 0.1))
				sm.set_shader_parameter("opacity", 0.7)
			# Start fallback timer based on dodge animation duration
			var duration := 0.25
			var sf = $AnimatedSprite2D.sprite_frames
			if sf and sf.has_animation("dodge"):
				var frames = sf.get_frame_count("dodge")
				var speed = sf.get_animation_speed("dodge")
				if speed > 0:
					duration = float(frames) / float(speed)
			_dodge_timer.start(duration)
			# Start dodge cooldown
			_dodge_on_cooldown = true
			_dodge_cd_timer.start(dodge_cooldown_s)
			# Temporary i-frames by disabling Hurtbox monitoring
			if dodge_invulnerable:
				var hb := get_node_or_null("HurtboxComponent") as Area2D
				if hb:
					hb.set_deferred("monitoring", false)
					hb.set_deferred("monitorable", false)
			move_and_slide()
			return

	# --- Normalna prędkość ---
	var target_velocity = direction * MAX_SPEED
	velocity = velocity.lerp(target_velocity, 1 - exp(-delta * ACCELERATION_SMOOTHING))

	# Animacje w zależności od ruchu
	if velocity.length() < 5:
		$AnimatedSprite2D.play("default")
	else:
		$AnimatedSprite2D.play("run")

	move_and_slide()

	# Deflect input handled in _input to avoid double triggers




func get_movement_vector() -> Vector2:
	var x_movement = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var y_movement = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	return Vector2(x_movement, y_movement)

func _on_animation_finished() -> void:
	if $AnimatedSprite2D.animation == "dodge":
		_end_dodge()

func _on_dodge_timer_timeout() -> void:
	if is_dodging:
		_end_dodge()

func _on_dodge_cd_timeout() -> void:
	_dodge_on_cooldown = false


func _spawn_and_activate_shield() -> void:
	if _deflect_on_cooldown:
		return
	# Spawn shield instance on demand; fallback to old deflect if needed
	if deflect_shield_scene != null:
		# Hide current weapons first, then ensure no leftover shields
		weapons_disabled = true
		_set_weapons_visible(false)
		_remove_existing_shields()
		# Clean up tracked instance if still present
		if is_instance_valid(_active_shield):
			_active_shield.queue_free()
		_active_shield = deflect_shield_scene.instantiate() as DeflectShield
		# Parent to Weapon layer if present for proper draw order
		var weapon_layer = get_node_or_null("Weapon")
		if weapon_layer:
			weapon_layer.add_child(_active_shield)
		else:
			add_child(_active_shield)
		# Always spawn shield exactly at player's position in world space
		if _active_shield is Node2D:
			(_active_shield as Node2D).global_position = global_position - Vector2(0, 13)
		# Assign explicit paths so shield can resolve player and melee range reliably
		var player_np: NodePath = _active_shield.get_path_to(self)
		_active_shield.player_path = player_np
		var mr = get_node_or_null("MeleeRange")
		if mr:
			_active_shield.melee_range_path = _active_shield.get_path_to(mr)
		_active_shield.set_active(true)
		_deflect_timer.start(deflect_duration_s)
		_deflect_on_cooldown = true
		_deflect_cd_timer.start(deflect_cooldown_s)
		# Weapons already hidden; start shield duration
	elif _deflect:
		# Fallback legacy deflect
		weapons_disabled = true
		_set_weapons_visible(false)
		_deflect.active = true
		_deflect_timer.start(deflect_duration_s)
		_deflect_on_cooldown = true
		_deflect_cd_timer.start(deflect_cooldown_s)


func _on_deflect_timer_timeout() -> void:
	if is_instance_valid(_active_shield):
		_active_shield.set_active(false)
		_active_shield.queue_free()
		_active_shield = null
	elif _deflect:
		_deflect.active = false
	# Ensure no stray shields remain (e.g., from other systems)
	_remove_existing_shields()
	# Unlock and show weapon layer again after shield ends
	weapons_disabled = false
	_set_weapons_visible(true)

func _set_weapons_visible(v: bool) -> void:
	var layer = get_node_or_null("Weapon")
	if layer == null:
		return
	for child in layer.get_children():
		if child == null:
			continue
		# Keep shield visible during parry; only toggle actual weapons
		if String(child.name) == "DeflectShield":
			continue
		var ci := child as CanvasItem
		if ci:
			ci.visible = v

func _remove_existing_shields() -> void:
	var layer = get_node_or_null("Weapon")
	if layer == null:
		return
	for child in layer.get_children():
		if child == null:
			continue
		if String(child.name) == "DeflectShield" or (child is DeflectShield):
			(child as Node).queue_free()

func _on_deflect_cd_timer_timeout() -> void:
	_deflect_on_cooldown = false


func _end_dodge() -> void:
	is_dodging = false
	velocity = Vector2.ZERO
	# Show weapon layer after dodge animation ends
	var weapon_layer = get_node_or_null("Weapon")
	if weapon_layer:
		weapon_layer.visible = true
	# Reset flash after dodge
	var sm := $AnimatedSprite2D.material as ShaderMaterial
	if sm:
		sm.set_shader_parameter("flash", 0.0)
		sm.set_shader_parameter("opacity", 1.0)
	# Re-enable Hurtbox after i-frames
	if dodge_invulnerable:
		var hb := get_node_or_null("HurtboxComponent") as Area2D
		if hb:
			hb.set_deferred("monitoring", true)
			hb.set_deferred("monitorable", true)


func _ensure_sprite_shader() -> void:
	var spr := $AnimatedSprite2D
	var sm := spr.material as ShaderMaterial
	if sm == null:
		sm = ShaderMaterial.new()
		spr.material = sm
	if sm.shader == null:
		sm.shader = load("res://scenes/shaders/flash_tint.gdshader")
	# Defaults
	sm.set_shader_parameter("tint", Color(1,1,1,1))
	sm.set_shader_parameter("desaturate", 0.0)
	sm.set_shader_parameter("flash", 0.0)
	sm.set_shader_parameter("flash_color", Color(1,1,1,1))
	sm.set_shader_parameter("opacity", 1.0)

func add_upgrade(upgrade: Upgrade) -> void:
	if upgrade == null:
		return
	upgrades.append(upgrade)
	print("[Player] Received upgrade:", upgrade.id)
	apply_upgrades()

func apply_upgrades() -> void:
	# Reset to base values
	bullet_speed_multiplier = 1.0
	bullet_size_multiplier = 1.0
	bullet_damage_multiplier = 1.0
	dodge_speed_multiplier = 1.0
	dodge_cooldown_s = 0.6
	dodge_invulnerable = false
	full_auto_enabled = false
	fire_cooldown_multiplier = 1.0
	# Apply all upgrades cumulatively
	var want_shotgun := false
	for upg in upgrades:
		match upg.id:
			"bullet_speed":
				bullet_speed_multiplier *= 1.1
				bullet_size_multiplier *= 0.9
			"big_bullets":
				bullet_size_multiplier *= 1.1
				bullet_speed_multiplier *= 0.9
			"heavy_bullets":
				bullet_damage_multiplier *= 1.2
			"long_dodge":
				dodge_speed_multiplier *= 1.2
				dodge_cooldown_s *= 1.25
			"fromsoftwatre_dodge":
				dodge_invulnerable = true
				dodge_cooldown_s *= 2.0
			"full_auto":
				full_auto_enabled = true
				# Global fire-rate multiplier (lower is faster)
				fire_cooldown_multiplier *= 0.6
				# Tradeoff: slower bullets in full-auto
				bullet_speed_multiplier *= 0.7
			"shotgun":
				want_shotgun = true

	# Equip shotgun if requested by upgrades
	if want_shotgun:
		var wm = get_node_or_null("WeaponManager")
		if wm and wm.has_method("equip_shotgun"):
			wm.equip_shotgun()

func get_bullet_speed_multiplier() -> float:
	return bullet_speed_multiplier

func get_bullet_size_multiplier() -> float:
	return bullet_size_multiplier

func get_bullet_damage_multiplier() -> float:
	return bullet_damage_multiplier


func are_weapons_disabled() -> bool:
	return weapons_disabled
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("deflect") and not _deflect_on_cooldown:
		_spawn_and_activate_shield()
		get_viewport().set_input_as_handled()

func is_full_auto_enabled() -> bool:
	return full_auto_enabled

func get_fire_cooldown_multiplier() -> float:
	return fire_cooldown_multiplier
