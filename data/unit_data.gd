extends Resource
class_name UnitData
## Schema for a regular or special Unit. Instances become .tres files.
##
## Ability FLAGS (not hardcoded ifs) keep special units — Infiltrator,
## Berserker, Manstopper, Sapperteur — out of combat-code tangles.

@export var id: StringName
@export var display_name: String

@export_group("Stats")
@export var move: int = 1
@export var attack: int = 1
@export var defense: int = 1
@export var range: int = 1

@export_group("Ability flags")
@export var crit_on: int = 6          ## Berserker = 5 (crits on 5-6).
@export var hit_only_on: int = 0      ## 0 = normal; Infiltrator = 6.
@export var moves_through_enemies: bool = false   ## Infiltrator.
@export var extra_setup_move: bool = false
@export var places_sticky_bomb: bool = false      ## Sapperteur.
