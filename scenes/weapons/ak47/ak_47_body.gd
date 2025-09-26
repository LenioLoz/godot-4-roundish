extends CharacterBody2D

@onready var ammo: AmmoComponent = null
@onready var _fire_timer: Timer = null

@export var bullet_path: PackedScene
@export var base_fire_cooldown_s: float = 0.22
@export var full_auto_fire_cooldown_s: float = 0.12

var player: Node2D
var direction: Vector2

var can_shoot: bool = true

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	# Ensure ammo component exists with defaults (15 rounds, 1s reload)
	ammo = get_node_or_null("AmmoComponent")
	if ammo == null:
		ammo = AmmoComponent.new()
		ammo.max_ammo = 15
		ammo.reload_time_s = 1.0
		add_child(ammo)
	# Connect reload signals once
	if not ammo.reload_started.is_connected(on_reload_started):
		ammo.reload_started.connect(on_reload_started)
	if not ammo.reload_finished.is_connected(on_reload_finished):
		ammo.reload_finished.connect(on_reload_finished)
	# Fire cooldown timer
	_fire_timer = Timer.new()
	_fire_timer.one_shot = true
	add_child(_fire_timer)
	_fire_timer.timeout.connect(func(): can_shoot = true)

func _input(event: InputEvent) -> void:
	if ammo == null:
		return
	# Block reload/use while weapons are disabled (during shield)
	if _weapons_locked():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R or event.physical_keycode == KEY_R:
			ammo.start_reload()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	direction = get_global_mouse_position() - global_position
	look_at(get_global_mouse_position())

	# flipowanie broni w zależności od strony
	if direction.x < 0:
		$Sprite2D.flip_v = true
		$Sprite2D.position.x = 2
	else:
		$Sprite2D.flip_v = false

	var want_shoot := false
	if _is_full_auto():
		want_shoot = Input.is_action_pressed("attack")
	else:
		want_shoot = Input.is_action_just_pressed("attack")
	if want_shoot and can_shoot and ammo and ammo.can_fire() and not _weapons_locked():
		fire()
		ammo.consume(1)

	# Play walk animation when player is moving (unless shooting or reloading)
	var anim_player: AnimationPlayer = $"../AnimationPlayer"
	if anim_player and not ((anim_player.current_animation == "shoot_animation" and anim_player.is_playing()) or (anim_player.current_animation == "reload" and anim_player.is_playing())):
		var moving := false
		var player_cb := player as CharacterBody2D
		if player_cb:
			moving = player_cb.velocity.length() > 5.0
		if moving:
			if anim_player.current_animation != "walk":
				anim_player.play("walk")
		else:
			if anim_player.current_animation == "walk":
				anim_player.play("RESET")

func fire() -> void:
	can_shoot = false
	var anim_player: AnimationPlayer = $"../AnimationPlayer"
	if anim_player and anim_player.has_animation("shoot_animation"):
		anim_player.play("shoot_animation")

	# Ensure bullet scene is set
	if bullet_path == null:
		# If no bullet scene, re-arm by cooldown
		_arm_after_cooldown()
		return

	var bullet = bullet_path.instantiate()
	bullet.dir = rotation
	bullet.pos = $BulletPosition.global_position
	bullet.rotat = global_rotation
	# Apply player upgrades to bullet (speed and size)
	var speed_mul := 1.0
	var size_mul := 1.0
	var dmg_mul := 1.0
	var ply = player
	if ply and ply.has_method("get_bullet_speed_multiplier"):
		speed_mul = ply.get_bullet_speed_multiplier()
	if ply and ply.has_method("get_bullet_size_multiplier"):
		size_mul = ply.get_bullet_size_multiplier()
	if ply and ply.has_method("get_bullet_damage_multiplier"):
		dmg_mul = ply.get_bullet_damage_multiplier()

	bullet.speed = float(bullet.speed) * speed_mul
	# Scale entire bullet node to affect visuals and collisions without mutating shared shapes
	if bullet is Node2D:
		(bullet as Node2D).scale *= Vector2(size_mul, size_mul)
	# Apply damage multiplier (rifle_bullet defines `damage_mul`)
	if bullet.has_method("set"):
		bullet.set("damage_mul", dmg_mul)

	# Spawn bullet in the current scene root so it doesn't inherit player movement
	get_tree().current_scene.add_child(bullet)

	# Arm again after a cooldown (animation may still be playing visually)
	_arm_after_cooldown()

func on_reload_started():
	$"../AnimationPlayer".play("reload")

func on_reload_finished():
	var ap: AnimationPlayer = $"../AnimationPlayer"
	if ap and ap.current_animation == "reload":
		ap.play("RESET")

func _weapons_locked() -> bool:
	var ply = player
	if ply and ply.has_method("are_weapons_disabled"):
		return ply.are_weapons_disabled()
	return false

func _arm_after_cooldown() -> void:
	var cd := base_fire_cooldown_s
	if _is_full_auto():
		cd = full_auto_fire_cooldown_s
		var ply = player
		if ply and ply.has_method("get_fire_cooldown_multiplier"):
			cd *= ply.get_fire_cooldown_multiplier()
	if _fire_timer:
		can_shoot = false
		_fire_timer.start(cd)
	else:
		can_shoot = true

func _is_full_auto() -> bool:
	var ply = player
	if ply and ply.has_method("is_full_auto_enabled"):
		return ply.is_full_auto_enabled()
	return false
