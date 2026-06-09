extends Resource
class_name ActionCardData
## Schema for an Action card. The rules engine dispatches on effect_id.
## Author ONLY finalized cards; deferred ones (exports 08/12) leave effect_id
## empty until designed.

enum CardType { RECRUITMENT, MOVEMENT, ATTACK }

@export var id: StringName
@export var card_name: String
@export_multiline var text: String
@export var card_type: CardType = CardType.RECRUITMENT
@export var effect_id: StringName     ## Rules engine dispatches on this.
