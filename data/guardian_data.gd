extends Resource
class_name GuardianData
## Schema for a Guardian. Same shape as UnitData plus guardian-specific flags.
## The 8 designed Guardians: Blackout, The Ox, Blink, Cutter, Typhoon, Razor,
## Arachnid, Scrape. (Bag = 8 Guardians + 4 Scrap — confirm in playtest.)

@export var id: StringName
@export var display_name: String

@export_group("Stats")
@export var move: int = 1
@export var attack: int = 1
@export var defense: int = 1
@export var range: int = 1            ## Arachnid = 2 (shoots around corners).
@export var attack_dice: int = 1

@export_group("Ability flags")
@export var crit_on: int = 6
@export var hit_only_on: int = 0      ## Typhoon = 6.
@export var attacks_on_move: bool = false       ## The Ox.
@export var applies_hits_first: bool = false     ## Razor.
@export var extra_attack_rounds: int = 0         ## Scrape.
@export var moves_through_walls: bool = false    ## Blink.
@export var reduces_attack: bool = false         ## Blackout.
