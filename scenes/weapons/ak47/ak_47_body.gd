extends CharacterBody2D

@onready var ammo: AmmoComponent = null

@export var bullet_path: PackedScene

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

	if Input.is_action_just_pressed("attack") and can_shoot and ammo and ammo.can_fire() and not _weapons_locked():
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
		can_shoot = true
		return

	var bullet = bullet_path.instantiate()
	bullet.dir = rotation
	bullet.pos = $BulletPosition.global_position
	bullet.rotat = global_rotation
	# Apply player upgrades to bullet (speed and size)
	var speed_mul := 1.0
	var size_mul := 1.0
	var ply = player
	if ply and ply.has_method("get_bullet_speed_multiplier"):
		speed_mul = ply.get_bullet_speed_multiplier()
	if ply and ply.has_method("get_bullet_size_multiplier"):
		size_mul = ply.get_bullet_size_multiplier()

	bullet.speed = float(bullet.speed) * speed_mul
	# Scale entire bullet node to affect visuals and collisions without mutating shared shapes
	if bullet is Node2D:
		(bullet as Node2D).scale *= Vector2(size_mul, size_mul)

	# Spawn bullet in the current scene root so it doesn't inherit player movement
	get_tree().current_scene.add_child(bullet)

	# poczekaj aż animacja się skończy (jeśli odtwarzana)
	if anim_player and anim_player.is_playing():
		await anim_player.animation_finished
	can_shoot = true

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
