extends Control

@onready var _ip: LineEdit = $VBoxContainer/Ip if has_node("VBoxContainer/Ip") else null





func _on_server_pressed() -> void:
	HighLevelNetworkHandler.start_server()


func _on_client_pressed() -> void:
	if _ip and String(_ip.text).strip_edges() != "":
		HighLevelNetworkHandler.set_ip_address(_ip.text)
	HighLevelNetworkHandler.start_client()
