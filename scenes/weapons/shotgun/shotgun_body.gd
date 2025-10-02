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
	if is_instance_valid(player):
		_last_player_pos = player.global_position

func _input(event: InputEvent) -> void:
	if not _has_authority():
		return
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
	if not _has_authority():
		# Remote peer: apply replicated aim and mimic walking animation
		rotation = lerp_angle(rotation, _remote_aim_rot, 0.25)
		var facing_left_r = cos(_remote_aim_rot) < 0.0
		$Sprite2D.flip_v = facing_left_r
		$Sprite2D.flip_h = false
		var anim_player_r: AnimationPlayer = $"../AnimationPlayer"
		var dp_remote: Vector2 = player.global_position - _last_player_pos
		var moving_remote: bool = dp_remote.length() / max(delta, 0.0001) > 5.0
		_last_player_pos = player.global_position
		if anim_player_r and not ((anim_player_r.current_animation == "shoot_animation" and anim_player_r.is_playing()) or (anim_player_r.current_animation == "reload" and anim_player_r.is_playing())):
			if moving_remote:
				if anim_player_r.current_animation != "walk":
					anim_player_r.play("walk")
			else:
				if anim_player_r.current_animation == "walk":
					anim_player_r.play("RESET")
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
		var dp: Vector2 = player.global_position - _last_player_pos
		var moving: bool = dp.length() / max(delta, 0.0001) > 5.0
		_last_player_pos = player.global_position
		if moving:
			if anim_player.current_animation != "walk":
				anim_player.play("walk")
		else:
			if anim_player.current_animation == "walk":
				anim_player.play("RESET")
	# Broadcast aim rotation and movement state for remotes
	rpc("rpc_set_shotgun_aim", rotation)

func fire() -> void:
	can_shoot = false
	# Broadcast shoot animation for all peers (and local)
	rpc("rpc_play_shoot_anim")
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
	var specs: Array = []
	if count == 1:
		specs.append({
			"pos": spawn_pos,
			"rot": base_angle,
			"speed_mul": speed_mul,
			"size_mul": size_mul,
			"dmg_mul": dmg_mul,
		})
	else:
		var increment = spread / (bullet_count - 1)
		for i in range(count):
			var rot_i = (global_rotation) + increment * i - spread / 2.0
			specs.append({
				"pos": spawn_pos,
				"rot": rot_i,
				"speed_mul": speed_mul,
				"size_mul": size_mul,
				"dmg_mul": dmg_mul,
			})
	# Replicate pellets to all peers (and local) so visuals match exactly
	rpc("rpc_spawn_shotgun_pellets", specs)
	_has_queued_aim = false

	_arm_after_cooldown()

@rpc("any_peer", "call_local")
func rpc_play_shoot_anim() -> void:
	var anim_player: AnimationPlayer = $"../AnimationPlayer"
	if anim_player and anim_player.has_animation("shoot_animation"):
		anim_player.play("shoot_animation")

@rpc("any_peer", "call_local")
func rpc_spawn_shotgun_pellets(specs: Array) -> void:
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
	for s in specs:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var spawn_pos: Vector2 = s.get("pos", $BulletPosition.global_position)
		var rot: float = float(s.get("rot", global_rotation))
		var speed_mul: float = float(s.get("speed_mul", 1.0))
		var size_mul: float = float(s.get("size_mul", 1.0))
		var dmg_mul: float = float(s.get("dmg_mul", 1.0))
		var bullet = bullet_path.instantiate()
		bullet.pos = spawn_pos
		bullet.dir = rot
		bullet.rotat = rot
		bullet.speed = float(bullet.speed) * speed_mul
		if bullet is Node2D:
			(bullet as Node2D).scale *= Vector2(size_mul, size_mul)
		if bullet.has_method("set"):
			bullet.set("damage_mul", dmg_mul)
		get_tree().current_scene.add_child(bullet)

@rpc("any_peer", "call_local")
func rpc_set_shotgun_aim(rot: float) -> void:
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
	var cd := 0.4
	if _fire_timer:
		can_shoot = false
		_fire_timer.start(cd)
	else:
		can_shoot = true

func _has_authority() -> bool:
	var ply = player
	if ply and ply.has_method("is_multiplayer_authority"):
		return ply.is_multiplayer_authority()
	return is_multiplayer_authority()
