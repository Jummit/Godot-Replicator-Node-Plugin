tool
extends Node
class_name Replicator, "replicator_node_icon.svg"

"""
Replicates spawning, despawning and the properties listed in `members`.

Supports interpolation and replicating properties at specified intervals and
spawning on joining peers.

The `subject` is the node whose properties get replicated, and which is
spawned / despawned. It is the parent of the replicator by default, but can be
changed programatically.

For spawning to work the `subject` must be the root of the scene, as only the
filename of the scene is send over the network.

`members` is a list of `ReplicatedMember`s which store a number of settings
regarding replication. `replicate_member` can be called to replicate members
manually.

Even though `PlayerLocationManager` and `RemoteSpawner` are autoloads, they are
fetched manually. This allows for multiple instances at the same time, which is
needed to run server and client simultaniously.

Members are only replicated when they change, which is detected using the
native `equal_approx` method.
"""

# Emitted before the master/puppet are set up. This can be used to alter the
# Replicator before it does it's setup.
signal pre_init

export(Array, ReplicatedMember) var members : Array
# Spawn on puppet instances when spawned on the master instance.
export var replicate_spawning := false
# Despawn on puppet instances when despawned on the master instance.
export var replicate_despawning := false
# Despawn when the master disconnects.
export var despawn_on_disconnect := false
# The maxium distance `subject` can be away from the player and get replicated.
export var max_replication_distance := INF
# Log replication of members on the master instance.
export var enable_logging := false

var remote_spawner : RemoteSpawner
var player_location_manager : PlayerLocationManager

# Store which members where replicated,
# to only interpolate if the master sent us a state.
var already_replicated_once : Dictionary = {}
var last_replicated_values : Dictionary = {}

var NO_MEMBER := ReplicatedMember.new()

const TYPES_WITH_EQUAL_APPROX_METHOD := [TYPE_VECTOR2, TYPE_RECT2,
		TYPE_VECTOR3, TYPE_TRANSFORM2D, TYPE_PLANE, TYPE_QUAT, TYPE_AABB,
		TYPE_BASIS, TYPE_TRANSFORM, TYPE_COLOR]

const PlayerLocationManager = preload("player_location_manager.gd")
const RemoteSpawner = preload("remote_spawner.gd")
const ReplicatedMember = preload("replicated_member.gd")

onready var subject : Node = get_parent()

func _ready() -> void:
	set_process(Engine.editor_hint)
	if Engine.editor_hint:
		return
	if not multiplayer.connected():
		yield(multiplayer, "connected_to_server")
	
	emit_signal("pre_init")
	
	if is_network_master():
		_setup_master()
	else:
		_setup_puppet()
	
	# Make members unique so they can be modified on a per-instance basis.
	members = members.duplicate()
	for member_num in members.size():
		members[member_num] = members[member_num].duplicate()
	
	for member in members:
		setup_member(member)


func _process(_delta : float) -> void:
	update_configuration_warning()


func _get_configuration_warning() -> String:
	if replicate_spawning and not subject.filename:
		return "Can't replicate spawning if not attached to the root node of the scene."
	return ""


func setup_member(member : ReplicatedMember) -> void:
	if is_network_master():
		if member.replicate_automatically:
			var timer := Timer.new()
			timer.wait_time = member.replicate_interval
			timer.autostart = true
			timer.one_shot = false
			timer.connect("timeout", self, "_on_ReplicateTimer_timeout",
					[member])
			add_child(timer)
	else:
		var tween := Tween.new()
		tween.name = member.name
		add_child(tween)


func replicate_member(member : ReplicatedMember) -> void:
	var last_value = last_replicated_values.get(member.name)
	var node := get_node(member.node)
	var current_value = node.get(member.name)
	
	assert(member.name in node, "member %s not found on %s" % [member.name,
			node.name])
	
	if _is_variant_equal_approx(current_value, last_value):
		if member.reliable:
			return
		else:
			if randf() > member.importance:
				member.importance += 0.1
				return
	
	if member.logging:
		_log("Replicating %s of %s with value of %s" %
				[member.name, subject.name, current_value])
	
	for peer in multiplayer.get_network_connected_peers():
		if peer == multiplayer.get_network_unique_id():
			continue
		if player_location_manager.get_distance(subject, peer) <\
				max_replication_distance:
			if member.reliable:
				rpc_id(peer, "_set_member_on_puppet", member.name,
						current_value)
			else:
				rpc_unreliable_id(peer, "_set_member_on_puppet", member.name,
						current_value)
	
	last_replicated_values[member.name] = current_value


func get_member_configuration(member_name : String) -> ReplicatedMember:
	for member in members:
		if member.name == member_name:
			return member
	return NO_MEMBER


func _setup_master() -> void:
	remote_spawner = _find_node_on_parents(self, "RemoteSpawner")
	player_location_manager = _find_node_on_parents(self,
			"PlayerLocationManager")
	
	if replicate_spawning and subject.filename:
		multiplayer.connect("network_peer_connected", self,
				"_on_network_peer_connected")
	if replicate_spawning:
		_log("Spawning %s on connected peers" % subject.name)
		remote_spawner.replicate_node(subject)
		yield(get_tree(), "idle_frame")
		for member in members:
			replicate_member(member)
	if replicate_despawning:
		connect("tree_exiting", self, "_on_tree_exiting")


func _setup_puppet() -> void:
	if despawn_on_disconnect:
		multiplayer.connect("network_peer_disconnected", self,
				"_on_network_peer_disconnected")


puppet func _set_member_on_puppet(member : String, value) -> void:
	var configuration := get_member_configuration(member)
	var node := get_node(configuration.node)
	var old_value = node.get(member)
	var difference := _distance(old_value, value)
	if configuration.min_replication_difference and\
			difference < configuration.min_replication_difference:
		return
	if configuration.logging:
		_log("%s of %s set to %s" % [member, subject.name, value])
	if configuration.interpolate_changes and\
			difference < configuration.max_interpolation_distance\
			and already_replicated_once.has(member):
		get_node(member).interpolate_property(node, member,
				node.get(member), value, configuration.replicate_interval)
		get_node(member).start()
	else:
		node.set(member, value)
		already_replicated_once[member] = true


# Called when the master node exits the tree.
puppet func _despawn() -> void:
	subject.queue_free()
	_log("%s despawned as master (%s) disconnected" % [subject.name,
			subject.get_network_master()])


func _on_tree_exiting() -> void:
	rpc("_despawn")


func _on_network_peer_connected(id : int) -> void:
	_log("Spawning %s on newly connected peer (%s)" % [subject.filename, id])
	remote_spawner.replicate_node(subject, id)


func _on_network_peer_disconnected(id : int) -> void:
	if id == get_network_master():
		subject.queue_free()
		_log("%s despawned as master (%s) disconnected" % [subject.name,
				get_network_master()])


func _on_ReplicateTimer_timeout(member : ReplicatedMember) -> void:
	if is_inside_tree():
		replicate_member(member)


func _log(message : String) -> void:
	if enable_logging:
		print(message)


static func _is_variant_equal_approx(a, b) -> bool:
	if typeof(a) in TYPES_WITH_EQUAL_APPROX_METHOD and (typeof(a) == typeof(b)):
		return a.is_equal_approx(b)
	else:
		return a == b


static func _distance(a, b) -> float:
	if typeof(a) == typeof(b):
		match typeof(a):
			TYPE_TRANSFORM, TYPE_TRANSFORM2D:
				return a.origin.distance_to(b.origin)
			TYPE_VECTOR2, TYPE_VECTOR3:
				return a.distance_to(b)
	if (a is float or a is int) and (b is float or b is int):
		return a - b
	return INF


static func _find_node_on_parents(start_node : Node, node_name : String):
	if not start_node.get_parent():
		return false
	var node := start_node.get_parent().find_node(node_name, false, false)
	if node:
		return node
	return _find_node_on_parents(start_node.get_parent(), node_name)
