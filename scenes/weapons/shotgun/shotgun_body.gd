extends CharacterBody2D

@onready var ammo: AmmoComponent = null
@onready var _fire_timer: Timer = null

@export var bullet_path: PackedScene
@export var base_fire_cooldown_s: float = 0.22
@export var pellet_spread_deg: float = 15.0
@export var bullet_count: int = 3

var player: Node2D
var direction: Vector2

var can_shoot: bool = true
var _queued_aim_dir: Vector2 = Vector2.ZERO
var _has_queued_aim: bool = false

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	ammo = get_node_or_null("AmmoComponent")
	if ammo == null:
		ammo = AmmoComponent.new()
		ammo.max_ammo = 5
		ammo.reload_time_s = 2
		add_child(ammo)
	if not ammo.reload_started.is_connected(on_reload_started):
		ammo.reload_started.connect(on_reload_started)
	if not ammo.reload_finished.is_connected(on_reload_finished):
		ammo.reload_finished.connect(on_reload_finished)
	_fire_timer = Timer.new()
	_fire_timer.one_shot = true
	add_child(_fire_timer)
	_fire_timer.timeout.connect(func(): can_shoot = true)

func _input(event: InputEvent) -> void:
	if ammo == null:
		return
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
	# Keep recoil consistent: flip vertically when facing left
	var ang = direction.angle()
	var facing_left = abs(wrapf(ang, -PI, PI)) > PI/2.0
	$Sprite2D.flip_v = facing_left
	$Sprite2D.flip_h = false
	var want_shoot := Input.is_action_just_pressed("attack")
	if want_shoot and can_shoot and ammo and ammo.can_fire() and not _weapons_locked():
		var spawn_pos_click: Vector2 = $BulletPosition.global_position
		_queued_aim_dir = (get_global_mouse_position() - spawn_pos_click)
		_has_queued_aim = true
		fire()
		ammo.consume(1)
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
	if bullet_path == null:
		_arm_after_cooldown()
		return

	# Read player multipliers once
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

	# Fire 3 pellets with angular spread: center and ±pellet_spread_deg
	# Use GLOBAL transform for both movement direction and visual rotation
	# to avoid discrepancies when the weapon node has parent transforms.
	var spread: float = deg_to_rad(pellet_spread_deg)
	# Start with raw spawn (no mirroring)
	var spawn_pos_raw: Vector2 = $BulletPosition.global_position
	# Compute a provisional base angle from click (preferred) or current mouse
	var base_angle: float
	if _has_queued_aim and _queued_aim_dir != Vector2.ZERO:
		base_angle = _queued_aim_dir.angle()
	else:
		base_angle = (get_global_mouse_position() - spawn_pos_raw).angle()
	# Mirror BulletPosition's local Y when aiming left to match sprite flipping
	var local_muzzle: Vector2 = $BulletPosition.position
	var facing_left: bool = cos(base_angle) < 0.0
	if facing_left:
		local_muzzle.y = -local_muzzle.y
	var spawn_pos: Vector2 = to_global(local_muzzle)
	# Safe forward offset so pellets spawn slightly ahead of the muzzle
	var forward: Vector2 = Vector2.RIGHT.rotated(base_angle)
	spawn_pos += forward * 10.0
	# If we didn't have a queued aim, refine base angle using the mirrored spawn
	if not _has_queued_aim or _queued_aim_dir == Vector2.ZERO:
		base_angle = (get_global_mouse_position() - spawn_pos).angle()
	var count: int = max(1, bullet_count)
	if count == 1:
		var bullet = bullet_path.instantiate()
		bullet.dir = base_angle
		bullet.pos = spawn_pos
		bullet.rotat = base_angle
		bullet.speed = float(bullet.speed) * speed_mul
		if bullet is Node2D:
			(bullet as Node2D).scale *= Vector2(size_mul, size_mul)
		if bullet.has_method("set"):
			bullet.set("damage_mul", dmg_mul)
		get_tree().current_scene.add_child(bullet)
	else:
		var step: float = (spread * 2.0) / float(count - 1)
		for i in range(count):
			var off: float = spread
			var bullet = bullet_path.instantiate()
			bullet.pos = spawn_pos
			var increment = spread/(bullet_count -1)
			bullet.rotat = (global_rotation) + increment * i - spread/2
			bullet.speed = float(bullet.speed) * speed_mul
			if bullet is Node2D:
				(bullet as Node2D).scale *= Vector2(size_mul, size_mul)
			if bullet.has_method("set"):
				bullet.set("damage_mul", dmg_mul)
			get_tree().current_scene.add_child(bullet)
	_has_queued_aim = false

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
	var cd := 0.4
	if _fire_timer:
		can_shoot = false
		_fire_timer.start(cd)
	else:
		can_shoot = true
