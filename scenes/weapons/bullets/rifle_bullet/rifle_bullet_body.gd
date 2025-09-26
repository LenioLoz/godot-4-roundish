extends CharacterBody2D

@onready var hitbox_component: HitboxComponent = $MyHitboxComponent


var pos:Vector2
var rotat:float
var dir:float
var speed = 200
@export var base_damage: int = 5
var damage_mul: float = 1.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Compute damage at runtime to allow weapon/player modifiers
	hitbox_component.damage = int(round(base_damage * damage_mul))
	global_position = pos
	global_rotation = rotat
	$Timer.start()
	$Timer.timeout.connect(on_timer_timeout)
	add_to_group("projectile")
	# Remove bullet when it hits a hurtbox (enemy)
	hitbox_component.area_entered.connect(_on_hitbox_area_entered)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	velocity = Vector2(speed,0).rotated(dir)
	move_and_slide()


func on_timer_timeout():
	queue_free()

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area is HurtboxComponent:
		# Only remove the projectile; Hurtbox handles applying damage
		queue_free()
