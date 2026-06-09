extends Node
## GameState — the authoritative, headless board model.
##
## STUB ONLY. The real model is built in Section B (HexCoord, HexCell,
## per-player bags via seeded RNG, token-state enums, etc.). This file exists
## now so the autoload registers and the project opens clean (Section A).
##
## Keep this layer runnable with NO scene loaded — that is what makes it
## unit-testable with GUT.

## Token state per player per hex. Encoded explicitly — never inferred.
## (face-down CONTROL tokens behave differently from ACTIVE ones.)
enum TokenState { NONE, ACTIVE, CONTROL }

## Round phase order: Recruitment -> Action -> Guardian -> (repeat).
enum Phase { RECRUITMENT, ACTION, GUARDIAN }

# Section B fills these in:
# var board: Dictionary = {}        # HexCoord -> HexCell
# var players: Array = []           # Player models
# var turn_order: Array = []
# var current_phase: Phase = Phase.RECRUITMENT
# var rng := RandomNumberGenerator.new()   # seeded for reproducibility


func _ready() -> void:
	# Intentionally empty for now.
	pass
