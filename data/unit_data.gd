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

@export_group("Combat ability flags")
## Number of RED Attack dice this unit contributes. 0 = use `attack` (the
## default — for regular units the printed Attack value IS the dice count).
## Special units whose dice count differs from their Attack stat set this.
@export var attack_dice: int = 0
## Sapperteur's Sticky Bomb: rolls this many Attack dice on enemies ENTERING
## its space, BEFORE the regular simultaneous round. 0 = no sticky bomb.
@export var sticky_bomb_dice: int = 2
## Grants the "controlled ground" +1 Defense aura WITHOUT a Control token
## (Shield Drone). Capped: never stacks with the Control-token +1.
@export var grants_ground_defense: bool = false   ## Shield Drone.
