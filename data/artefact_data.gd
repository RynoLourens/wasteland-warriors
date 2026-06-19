extends Resource
class_name ArtefactData
## Schema for an Artifact card (the Artifact Deck — ONE deck).
## The Ancient Artifact environment draws from this same deck.
## 5 designed: Medical Machine, Psychic Control Belt, Snooperbot 6000,
## Sunstone Fragments, The Jam Gobbar.

@export var id: StringName
@export var display_name: String
@export_multiline var text: String
@export var effect_id: StringName
