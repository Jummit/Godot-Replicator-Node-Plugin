extends Node

func _ready():
	get_tree().connect("node_added", self, "_on_SceneTree_node_added")


# node names are replicated in `spawn()`,
# but there is no way to include @s in custom names
func _on_SceneTree_node_added(node : Node):
	node.name = node.name.replace("@", "")


remote func spawn(node_name : String, network_master : int, scene_path : String, path : NodePath) -> void:
	print("Spawned instance of %s with the name of %s as child of %s on peer %s" % [scene_path, node_name, path, multiplayer.get_network_unique_id()])
	var instance : Node = load(scene_path).instance()
	instance.name = node_name
	instance.set_network_master(network_master)
	
	# use a path relative to multiplayer.root_node to make it possible
	# to run server and client on the same machine
	multiplayer.root_node.get_node(path).add_child(instance)

	# hide the instance as its position may not yet be
	# replicated to avoid seeing the instance at the origin
	if instance.has_method("show") and instance.has_method("hide"):
		instance.hide()
		yield(get_tree().create_timer(.01), "timeout")
		instance.show()
