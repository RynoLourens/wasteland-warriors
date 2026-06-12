extends Agent
class_name PassAgent
## Section F placeholder AI (per Corin's scope decision 2026-06-10: F is human-only /
## hotseat; AI seats are simple placeholders until the real medium AI lands in
## Section H). A PassAgent fills any non-human seat so the table is always full and
## the round flow runs end to end, but it never does anything interesting:
##   * Recruitment -> Deploy (draws 3, the safe default that keeps the bag moving).
##   * Action      -> Pass immediately.
##
## It implements the SAME Agent interface as HumanAgent and the future HeuristicAgent,
## so swapping in real AI later is a one-line construction change in GameController —
## no flow changes. Synchronous (no await): AI seats resolve instantly.

func decide_recruitment(_state, _color: StringName) -> Dictionary:
	return {"play_recruitment_card": -1, "choice": "deploy", "recruit_ids": []}


func decide_action(_state, _color: StringName) -> Dictionary:
	return {"type": "pass"}
