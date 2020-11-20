# Godot Replicator Node Plugin

Adds a `Replicator` node that can replicates properties with interpolation and spawning and deletion of nodes between server and client without any code.

## Usage

Add a Replicator node to the node that has properties you want to replicate with all clients. This could be a `RigidBody` for example.

Increase the length of the `members` array by clicking the arrow next to the `length`.
Write the properties you want to replicate in the `name` text field of the Member resource. For example, if you want to replicate the position and rotation of a `RigidBody`, type in `transform`.

### Replicator

| Exported Property | What it does |
| ----------------- | ------------ |
| Replicate Automatically | Call `replicate_members` in a specified interval |
| Replicate Interval | The interval at which to call `replicate_members` |
| Replicate Spawning | Spawn on puppet instances when spawned on the master |
| Replicate Despawning | Despawn on puppet instances when despawned on the |
| Despawn On Disconnect | Despawn when the master disconnects |
| Spawn On JoiningPeers | Spawn on newly joined peers |
| Interpolate Changes | Use a generated Tween sibling to interpolate new |
| Logging | Log changes of members on puppet instances |

### Replicated Member

| Exported Property | What it does |
| ----------------- | ------------ |
| Name | The name of the property |
| Interpolate Changes | If the property should be smoothly interpolated when a new value is received |
| Replicate Automatically | If the property should be automatically replicated in the specified `replicate_interval` |
| Replicate Interval | If `replicate_automatically` is true, how many seconds to wait to send the next snapshot |
| Reliable | Whether to use NetworkedMultiplayerPeer.TRANSFER_MODE_RELIABLE instead of NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE |
| Logging | Whether to log when an update is received on a puppet peer |
| Max Interpolation Distance | If `replicate_automatically` is true, maximum difference between snapshots that is interpolated |

## How it works

The Replicator node uses Godot's high level networking API.

It adds Tween siblings if `interpolate_changes` is true, which interpolate the old value to the new value when replicating, and a timer which calls `replicate_members` on timeout.

The plugin adds an autoload singleton called "RemoteSpawner" to spawn nodes on newly joined peers.

It also removes "@"s from nodes names to be able to replicate node names, as it's impossible to use "@"s when setting a node name.

Example: `@Bullet@2@` becomes `Bullet2`
