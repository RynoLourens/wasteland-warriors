extends Resource
class_name LeaderData
## Schema for a Leader. Build the 4 DESIGNED leaders now
## (Stormfoot, The Rat's Eye, Lady Seraph, Siyana); schema stays ready for the
## other 3 (deferred). Engine dispatches on passive_effect_id.

@export var id: StringName
@export var display_name: String
@export_multiline var passive_text: String
@export var passive_effect_id: StringName
