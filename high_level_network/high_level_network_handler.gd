extends Node

const IP_ADDRESS: String = "localhost"
const PORT: int = 42069

var peer: ENetMultiplayerPeer
var ip_address_config: String = IP_ADDRESS

func set_ip_address(ip: String) -> void:
	if ip == null:
		return
	ip_address_config = ip.strip_edges()
	if ip_address_config == "":
		ip_address_config = IP_ADDRESS

func start_server() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 32)
	if err != OK:
		push_error("ENet server failed: %s" % [err])
		return
	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals()
	print("[NET] Server started on port ", PORT)
	# Spawn the host player only after a successful server start
	var sp = get_tree().get_first_node_in_group("multiplayer_spawner")
	if sp and sp.has_method("spawn_player"):
		sp.spawn_player(multiplayer.get_unique_id())

func start_client() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_address_config, PORT)
	if err != OK:
		push_error("ENet client failed: %s" % [err])
		return
	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals()
	print("[NET] Client connecting to ", ip_address_config, ":", PORT)

func _connect_multiplayer_signals() -> void:
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_connected_to_server() -> void:
	print("[NET] Connected to server")

func _on_connection_failed() -> void:
	push_error("[NET] Connection failed")

func _on_server_disconnected() -> void:
	push_error("[NET] Disconnected from server")
