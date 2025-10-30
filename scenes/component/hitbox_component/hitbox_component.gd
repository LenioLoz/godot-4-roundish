extends Area2D
class_name HitboxComponent

@export var damage: int = 0
# Id właściciela, który wygenerował ten hitbox (np. authority gracza).
# 0 oznacza brak/nieznanego właściciela.
@export var owner_id: int = 0
