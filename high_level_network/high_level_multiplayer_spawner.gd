extends MultiplayerSpawner

@export var network_player: PackedScene
@export var network_player_client: PackedScene

func _ready() -> void:
	add_to_group("multiplayer_spawner")
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[Spawner] Ready. is_server=", multiplayer.is_server(), " spawn_path=", spawn_path)
	# When a new peer connects, also tell it about all existing players
	multiplayer.peer_connected.connect(_on_peer_connected_broadcast)




func spawn_player(id: int) -> void:
	if !multiplayer.is_server():
		return
	if network_player == null:
		return
	var parent := _get_spawn_parent()
	if parent == null:
		return
	# Avoid duplicates if already spawned
	if parent.get_node_or_null(str(id)) != null:
		return
	var scene_to_use: PackedScene = network_player
	if id != 1 and network_player_client != null:
		scene_to_use = network_player_client
	var player: Node = scene_to_use.instantiate()
	player.name = str(id)
	# Add immediately so MultiplayerSynchronizer path exists without a frame delay
	parent.add_child(player)
	# Inform all clients to spawn this player locally (host and others already have it)
	rpc("client_spawn_player", id)

@rpc("any_peer")
func client_spawn_player(id: int) -> void:
	# Runs on clients; ensure player for given id exists
	var parent := _get_spawn_parent()
	if parent == null:
		return
	if parent.get_node_or_null(str(id)) != null:
		return
	if network_player == null and network_player_client == null:
		return
	var scene_to_use: PackedScene = network_player
	if id != 1 and network_player_client != null:
		scene_to_use = network_player_client
	var player: Node = scene_to_use.instantiate()
	player.name = str(id)
	parent.add_child(player)

func _on_peer_disconnected(id: int) -> void:
	if !multiplayer.is_server():
		return
	var parent := _get_spawn_parent()
	if parent == null:
		return
	var n := parent.get_node_or_null(str(id))
	if n:
		n.queue_free()

func _on_peer_connected_broadcast(id: int) -> void:
	# Send the list of already present players (including host) to the newly joined peer
	if !multiplayer.is_server():
		return
	var parent := _get_spawn_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child == null:
			continue
		var pid := int(str(child.name)) if String(child.name).is_valid_int() else -1
		if pid > 0:
			rpc_id(id, "client_spawn_player", pid)

func _get_spawn_parent() -> Node:
	var parent := get_node_or_null(spawn_path)
	if parent == null:
		parent = get_parent()
	if parent == null:
		parent = get_tree().get_root().get_child(0) # likely Main
	return parent
