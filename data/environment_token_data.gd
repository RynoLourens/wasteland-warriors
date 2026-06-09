extends Resource
class_name EnvironmentTokenData
## Schema for an Environment token (6 room + 8 corridor).
## Some persist in their room (Teleporter Node, Darkness, Tough Terrain).

@export var id: StringName
@export var display_name: String
@export_multiline var text: String
@export var effect_id: StringName
@export_enum("Room", "Corridor") var category: String = "Room"
@export var persists_in_room: bool = false
