extends RefCounted
class_name Agent
## The pluggable per-player decision interface (Section D, step 3 + plan H step 1).
##
## CRITICAL architecture rule from the plan: "AI consumes the same intent API as
## the UI." The FSM never decides WHAT a player does — it asks that player's Agent
## for an *intent* (a small Dictionary), then validates and applies it through the
## logic layer. There is NO special AI back door into GameState, and the UI is just
## another Agent. This is what keeps hotseat / AI / (later) online from desyncing.
##
## Subclasses:
##   * ScriptedAgent (below)            — drives headless tests deterministically.
##   * (Section H) HeuristicAgent       — the real medium AI; same methods.
##   * (Section F) HumanAgent           — the UI fills the intent from taps; same methods.
##
## An "intent" is always a plain Dictionary so it can be logged, replayed, sent
## over a wire later, and validated in one place. The FSM is the only thing that
## mutates state; agents only PROPOSE.

## Recruitment intent. The FSM has already dealt this player their Action card.
##   {
##     "play_recruitment_card": int or -1,   # hand index of a Recruitment card to play, or -1
##     "choice": "deploy" | "recruit" | "punish"
##             | "control_room_spawn" | "hub_deploy" | "artefact_place_special",
##     "recruit_ids": Array[StringName],      # only for "recruit": which units to add
##     # Function/Artifact recruitment actions (Ch.13), each gated on Control:
##     "room": HexCoord,                      # control_room_spawn / hub_deploy: the Function room
##     "special_id": StringName,              # artefact_place_special: which Special Unit
##     "space": HexCoord,                     # artefact_place_special: Controlled space to place it
##   }
## `state` is a read-only view (the live GameState) so an agent can inspect its bag.
func decide_recruitment(state, color: StringName) -> Dictionary:
	return {"play_recruitment_card": -1, "choice": "deploy", "recruit_ids": []}


## Action-phase intent. Returns ONE action; the FSM loops calling this until the
## player passes. Shapes:
##   {"type": "pass"}
##   {"type": "card", "hand_index": int}                       # play a Movement card
##   {"type": "move_attack",
##      "activate": HexCoord,                                  # space to Activate
##      "moves": Array of {"from": HexCoord, "unit": <unit dict>},  # units to pull in
##      "carry_old_tech": bool}                                # carry Old Tech when leaving (needs Control)
##   {"type": "ranged_attack",                                 # Ch.11: fire WITHOUT moving in
##      "activate": HexCoord,                                  # your space holding Ranged Units
##      "target": HexCoord}                                    # enemy space within Range (no LoS)
func decide_action(state, color: StringName) -> Dictionary:
	return {"type": "pass"}


## ---------------------------------------------------------------------------
##  ScriptedAgent — a deterministic agent for headless tests.
## ---------------------------------------------------------------------------
## You hand it a queue of intents per phase; it pops them in order. When a queue
## runs dry it returns a safe default ("deploy" for recruitment, "pass" for
## action), so a test only has to script the interesting moves and let the rest
## drain to Pass. This is how the M4 full-game test stays readable.
class ScriptedAgent extends Agent:
	var recruitment_intents: Array = []
	var action_intents: Array = []

	func _init(_recruitment: Array = [], _action: Array = []) -> void:
		recruitment_intents = _recruitment.duplicate()
		action_intents = _action.duplicate()

	func decide_recruitment(_state, _color: StringName) -> Dictionary:
		if not recruitment_intents.is_empty():
			return recruitment_intents.pop_front()
		return {"play_recruitment_card": -1, "choice": "deploy", "recruit_ids": []}

	func decide_action(_state, _color: StringName) -> Dictionary:
		if not action_intents.is_empty():
			return action_intents.pop_front()
		return {"type": "pass"}
