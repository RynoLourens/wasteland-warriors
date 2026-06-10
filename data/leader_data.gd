extends Resource
class_name LeaderData
## Schema for a Leader. ALL 5 leaders exist as .tres:
## Stormfoot, The Rat's Eye, Lady Seraph, Siyana, Lil' Minerva.
## (The game has 5 leaders total — not 7.) Engine dispatches on passive_effect_id.

@export var id: StringName
@export var display_name: String
@export_multiline var passive_text: String
@export var passive_effect_id: StringName
