extends CharacterBody2D

@onready var ammo: AmmoComponent = null
@onready var _fire_timer: Timer = null

@export var bullet_path: PackedScene
@export var base_fire_cooldown_s: float = 0.22
@export var full_auto_fire_cooldown_s: float = 0.12

var player: Node2D
var direction: Vector2

var can_shoot: bool = true
var _remote_aim_rot: float = 0.0
var _last_player_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Prefer deriving owner player from parent chain; fallback to first player
	var n: Node = self
	while n:
		if n.is_in_group("player"):
			player = n as Node2D
			break
		n = n.get_parent()
	if player == null:
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
	if is_instance_valid(player):
		_last_player_pos = player.global_position

func _input(event: InputEvent) -> void:
	if not _has_authority():
		return
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
	if not _has_authority():
		# Remote peer: apply replicated aim and mimic walking animation
		rotation = lerp_angle(rotation, _remote_aim_rot, 0.25)
		var facing_left = cos(_remote_aim_rot) < 0.0
		$Sprite2D.flip_v = facing_left
		var anim_player: AnimationPlayer = $"../AnimationPlayer"
		var dp_remote: Vector2 = player.global_position - _last_player_pos
		var moving_remote: bool = dp_remote.length() / max(delta, 0.0001) > 5.0
		_last_player_pos = player.global_position
		if anim_player and not ((anim_player.current_animation == "shoot_animation" and anim_player.is_playing()) or (anim_player.current_animation == "reload" and anim_player.is_playing())):
			if moving_remote:
				if anim_player.current_animation != "walk":
					anim_player.play("walk")
			else:
				if anim_player.current_animation == "walk":
					anim_player.play("RESET")
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
		var moving: bool = false
		var player_cb := player as CharacterBody2D
		if player_cb:
			moving = player_cb.velocity.length() > 5.0
		if moving:
			if anim_player.current_animation != "walk":
				anim_player.play("walk")
		else:
			if anim_player.current_animation == "walk":
				anim_player.play("RESET")
	# After handling owner logic above, broadcast minimal aim state for remotes
	var dp_b: Vector2 = player.global_position - _last_player_pos
	var moving_b: bool = dp_b.length() / max(delta, 0.0001) > 5.0
	_last_player_pos = player.global_position
	rpc("rpc_set_aim_state", rotation, moving_b)

func fire() -> void:
	can_shoot = false
	# Broadcast shoot animation for all peers (and local)
	rpc("rpc_play_shoot_anim")
	# Ensure bullet scene is set
	if bullet_path == null:
		_arm_after_cooldown()
		return
	# Gather bullet parameters on authority and replicate spawn to all peers
	var spawn_pos: Vector2 = $BulletPosition.global_position
	var rot: float = global_rotation
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
	# Spawn bullet via RPC so both owner and remote peers see identical projectile
	rpc("rpc_spawn_rifle_bullet", spawn_pos, rot, speed_mul, size_mul, dmg_mul)
	# Arm again after a cooldown
	_arm_after_cooldown()

@rpc("any_peer", "call_local")
func rpc_play_shoot_anim() -> void:
	var anim_player: AnimationPlayer = $"../AnimationPlayer"
	if anim_player and anim_player.has_animation("shoot_animation"):
		anim_player.play("shoot_animation")

@rpc("any_peer", "call_local")
func rpc_spawn_rifle_bullet(spawn_pos: Vector2, rot: float, speed_mul: float, size_mul: float, dmg_mul: float) -> void:
	# Only accept spawns from the owning player's authority (or local call)
	var sender_id := multiplayer.get_remote_sender_id()
	var expected_id := 0
	var ply = player
	if ply and ply.has_method("get_multiplayer_authority"):
		expected_id = ply.get_multiplayer_authority()
	else:
		expected_id = get_multiplayer_authority()
	if sender_id != 0 and sender_id != expected_id:
		return
	if bullet_path == null:
		return
	var bullet = bullet_path.instantiate()
	bullet.dir = rot
	bullet.pos = spawn_pos
	bullet.rotat = rot
	bullet.speed = float(bullet.speed) * speed_mul
	if bullet is Node2D:
		(bullet as Node2D).scale *= Vector2(size_mul, size_mul)
	if bullet.has_method("set"):
		bullet.set("damage_mul", dmg_mul)
	get_tree().current_scene.add_child(bullet)

@rpc("any_peer", "call_local")
func rpc_set_aim_state(rot: float, moving: bool) -> void:
	# Only accept updates from the owning player's authority (or local call)
	var sender_id := multiplayer.get_remote_sender_id()
	var expected_id := 0
	var ply = player
	if ply and ply.has_method("get_multiplayer_authority"):
		expected_id = ply.get_multiplayer_authority()
	else:
		expected_id = get_multiplayer_authority()
	if sender_id != 0 and sender_id != expected_id:
		return
	_remote_aim_rot = rot

func on_reload_started():
	rpc("rpc_play_reload")

func on_reload_finished():
	rpc("rpc_stop_reload")

@rpc("any_peer", "call_local")
func rpc_play_reload() -> void:
	$"../AnimationPlayer".play("reload")

@rpc("any_peer", "call_local")
func rpc_stop_reload() -> void:
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

func _has_authority() -> bool:
	var ply = player
	if ply and ply.has_method("is_multiplayer_authority"):
		return ply.is_multiplayer_authority()
	return is_multiplayer_authority()
