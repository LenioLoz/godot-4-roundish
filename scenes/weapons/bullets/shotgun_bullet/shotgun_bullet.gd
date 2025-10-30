extends CharacterBody2D

@onready var hitbox_component: HitboxComponent = $MyHitboxComponent

var pos: Vector2
var rotat: float
var dir: Vector2
@export var speed: float = 150.0
@export var base_damage: int = 10
var damage_mul: float = 1.0
var owner_id: int = 0

func _ready() -> void:
	hitbox_component.damage = int(round(base_damage * damage_mul))
	hitbox_component.owner_id = owner_id

	# Ustawienie pozycji i kierunku
	global_position = pos
	global_rotation = rotat
	dir = Vector2.RIGHT.rotated(rotat)
	velocity = dir * speed

	# Uruchom timer życia pocisku
	$Timer.start()
	$Timer.timeout.connect(on_timer_timeout)

	add_to_group("projectile")
	hitbox_component.area_entered.connect(_on_hitbox_area_entered)


# 🔁 ODBICIE (natychmiastowe)
func _apply_reflect(new_owner_id: int, nudge: float = 6.0) -> void:
	# Poprzednie, proste odbicie: zmiana zwrotu prędkości
	speed *= -1
	owner_id = new_owner_id
	if hitbox_component:
		hitbox_component.owner_id = new_owner_id


# 🔁 RPC odbicia (sieciowo)
@rpc("any_peer", "call_local")
func rpc_reflect(new_owner_id: int, nudge: float = 6.0) -> void:
	_apply_reflect(new_owner_id, nudge)


# 🔄 RUCH
func _physics_process(delta: float) -> void:
	# Poprzednia logika strzału
	global_position += dir * speed * delta


# 🧨 Uderzenie w cel
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area is HurtboxComponent:
		queue_free()


func on_timer_timeout() -> void:
	queue_free()
