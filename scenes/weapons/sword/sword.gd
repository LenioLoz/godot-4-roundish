extends Node2D

enum State { FOLLOWING, ATTACKING }

@onready var hitbox_collision = $MyHitboxComponent/CollisionShape2D
@onready var hitbox_component: HitboxComponent = $MyHitboxComponent

var player: Node2D
var melee_range: CollisionShape2D
var state = State.FOLLOWING
var attack_scale_x = 1.0
var original_hitbox_pos_x: float
var attack_direction = 1

# Sway properties
var sway_angle = 0.0
const MAX_SWAY_ANGLE = 0.6
const SWAY_SPEED = 20.0
const SWAY_DECAY = 5.0
var _remote_pos: Vector2 = Vector2.ZERO
var _remote_rot: float = 0.0
var _remote_scale_x: float = 1.0
var _remote_hitbox_x: float = 0.0

func _ready():
	hitbox_collision.set_deferred("disabled", true)
	hitbox_component.damage = 5
	if has_node("AnimationPlayer"):
		$AnimationPlayer.animation_finished.connect(_on_animation_finished)
	else:
		print_debug("Sword is missing an AnimationPlayer node.")
	original_hitbox_pos_x = hitbox_collision.position.x
	# Deal damage directly when sword hitbox touches a Hurtbox
	$MyHitboxComponent.area_entered.connect(_on_hit_area_entered)


func _input(event):
	# Only the owning authority processes sword input
	if not _has_authority():
		return
	# Mouse sway input is only processed when following
	if event is InputEventMouseMotion and state == State.FOLLOWING:
		sway_angle = clamp(sway_angle - event.relative.x * 0.002, -MAX_SWAY_ANGLE, MAX_SWAY_ANGLE)
	# Attack input is only processed when following
	if Input.is_action_just_pressed("attack") and state == State.FOLLOWING and not _weapons_locked():
		# Compute attack direction on owner and replicate to all peers
		var mouse_pos = get_global_mouse_position()
		var direction_x = mouse_pos.x - player.global_position.x
		var dir := 1 if direction_x <= 0 else -1
		rpc("rpc_do_attack", dir)
		

func _process(delta):
	if not is_instance_valid(player):
		return

	var owner := _has_authority()
	if owner:
		# The sword's position is clamped to the melee_range hitbox based on owner mouse
		var mouse_pos = get_global_mouse_position()
		var new_pos = mouse_pos
		if is_instance_valid(melee_range):
			var hitbox_global_transform = melee_range.get_global_transform()
			var hitbox_global_pos = hitbox_global_transform.get_origin()
			var hitbox_scale = hitbox_global_transform.get_scale()
			var top_left: Vector2
			var bottom_right: Vector2
			var initialized = false
			if melee_range.shape is RectangleShape2D:
				var rect_shape = melee_range.shape as RectangleShape2D
				var hitbox_size = rect_shape.size * hitbox_scale
				var half_size = hitbox_size / 2.0
				top_left = hitbox_global_pos - half_size
				bottom_right = hitbox_global_pos + half_size
				initialized = true
			elif melee_range.shape is CapsuleShape2D:
				var capsule_shape = melee_range.shape as CapsuleShape2D
				var radius = capsule_shape.radius * max(hitbox_scale.x, hitbox_scale.y)
				var height = capsule_shape.height * hitbox_scale.y
				var half_width = radius
				var half_height = height / 2.0 + radius
				top_left = hitbox_global_pos - Vector2(half_width, half_height)
				bottom_right = hitbox_global_pos + Vector2(half_width, half_height)
				initialized = true
			elif melee_range.shape is CircleShape2D:
				var circle_shape = melee_range.shape as CircleShape2D
				var radius_c = circle_shape.radius * max(abs(hitbox_scale.x), abs(hitbox_scale.y))
				var to_mouse = new_pos - hitbox_global_pos
				if to_mouse.length() > radius_c:
					new_pos = hitbox_global_pos + to_mouse.normalized() * radius_c
			if initialized:
				new_pos.x = clamp(new_pos.x, top_left.x, bottom_right.x)
				new_pos.y = clamp(new_pos.y, top_left.y, bottom_right.y)
		global_position = new_pos
		var direction = global_position - player.global_position
		# State-based logic
		if state == State.FOLLOWING:
			# Flip the sprite based on mouse direction
			if direction.x != 0:
				$Sprite2D.scale.x = -sign(direction.x)
			# Apply sway effect
			sway_angle = lerp(sway_angle, 0.0, SWAY_DECAY * delta)
			rotation = lerp(rotation, sway_angle, SWAY_SPEED * delta)
			# Broadcast follow state to remotes (unreliable is fine for visuals)
			rpc("rpc_set_follow_state", global_position, rotation, $Sprite2D.scale.x, hitbox_collision.position.x)
		elif state == State.ATTACKING:
			# Forcibly set the scale every frame to override animation keyframes
			$Sprite2D.scale.x = attack_scale_x
			hitbox_collision.position.x = original_hitbox_pos_x * attack_direction
		return
	# Remote peer: apply replicated follow state when not attacking
	if state == State.FOLLOWING:
		global_position = _remote_pos
		rotation = _remote_rot
		$Sprite2D.scale.x = _remote_scale_x
		hitbox_collision.position.x = _remote_hitbox_x
		return
	elif state == State.ATTACKING:
		$Sprite2D.scale.x = attack_scale_x
		hitbox_collision.position.x = original_hitbox_pos_x * attack_direction

func _on_animation_finished(anim_name):
	# When the attack animation finishes, return to following state
	if anim_name == "attack" or anim_name == "swing_right": 
		state = State.FOLLOWING

@rpc("any_peer", "call_local")
func rpc_set_follow_state(pos: Vector2, rot: float, scale_x: float, hitbox_x: float) -> void:
	# Only accept updates from the owning player's authority (or local call)
	var sender_id := multiplayer.get_remote_sender_id()
	var expected_id := 0
	if player and player.has_method("get_multiplayer_authority"):
		expected_id = player.get_multiplayer_authority()
	else:
		expected_id = get_multiplayer_authority()
	if sender_id != 0 and sender_id != expected_id:
		return
	_remote_pos = pos
	_remote_rot = rot
	_remote_scale_x = scale_x
	_remote_hitbox_x = hitbox_x

@rpc("any_peer", "call_local")
func rpc_do_attack(dir: int) -> void:
	# Optional sender/authority guard to avoid cross-control
	var sender_id := multiplayer.get_remote_sender_id()
	var expected_id := 0
	if player and player.has_method("get_multiplayer_authority"):
		expected_id = player.get_multiplayer_authority()
	else:
		expected_id = get_multiplayer_authority()
	if sender_id != 0 and sender_id != expected_id:
		return
	state = State.ATTACKING
	# Stop sway and reset rotation before animation
	sway_angle = 0.0
	rotation = 0.0
	attack_direction = dir
	if dir == 1:
		$AnimationPlayer.play("attack")
	else:
		$AnimationPlayer.play("swing_right")
	$Sprite2D.scale.x = attack_scale_x

func _on_hit_area_entered(area: Area2D) -> void:
	# [style] Indentation in this function uses tabs
	# Intentionally do not apply damage here to avoid double-hit.
	# Damage is applied by the enemy's HurtboxComponent.
	if not (area is HurtboxComponent):
		return
	# print("[Sword] Hit hurtbox detected (damage handled by Hurtbox):", area)

func _weapons_locked() -> bool:
	if player and player.has_method("are_weapons_disabled"):
		return player.are_weapons_disabled()
	return false

func _has_authority() -> bool:
	if player and player.has_method("is_multiplayer_authority"):
		return player.is_multiplayer_authority()
	return is_multiplayer_authority()
