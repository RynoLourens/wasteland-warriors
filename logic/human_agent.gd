extends Agent
class_name HumanAgent
## Section F — the UI as an Agent.
##
## A HumanAgent does not decide anything itself: when the round flow asks it for a
## recruitment or action intent, it parks (awaits) until the UI calls submit(...).
## This keeps the plan's hard rule intact — "AI and UI both implement the SAME
## Agent interface; the flow only validates + applies" — while letting a phone tap
## drive the very same intent dictionary a ScriptedAgent or (Section H) HeuristicAgent
## would return. There is still no back door into GameState.
##
## Usage (driven by GameController, which runs in a coroutine):
##   var intent = await human_agent.decide_action(state, color)   # blocks for a tap
## and from the UI, when the player confirms:
##   human_agent.submit({"type": "move_attack", ...})
##
## A pending request is announced via the `awaiting_*` signals so the UI knows which
## panel to raise (Recruitment vs Action) and for whom.

signal awaiting_recruitment(color)
signal awaiting_action(color)

var _pending: bool = false
var _submitted: Dictionary = {}
var _has_value: bool = false


## Called by the UI to hand back the intent the player built with taps. Safe to
## call once per await; the awaiting coroutine resumes on the next idle frame.
func submit(intent: Dictionary) -> void:
	_submitted = intent
	_has_value = true
	_pending = false


func is_pending() -> bool:
	return _pending


func decide_recruitment(state, color: StringName) -> Dictionary:
	_pending = true
	_has_value = false
	awaiting_recruitment.emit(color)
	while not _has_value:
		await _frame(state)
	_has_value = false
	return _submitted


func decide_action(state, color: StringName) -> Dictionary:
	_pending = true
	_has_value = false
	awaiting_action.emit(color)
	while not _has_value:
		await _frame(state)
	_has_value = false
	return _submitted


## Yield one idle frame. We reach the SceneTree via the live GameState node (the
## autoload), so the agent itself needs no tree reference.
func _frame(state) -> void:
	if state != null and state.has_method("get_tree") and state.get_tree() != null:
		await state.get_tree().process_frame
	else:
		# No tree (pure headless): just return so the loop can re-check. This path
		# should not run in F (the UI always has a tree).
		await _noop()


func _noop() -> void:
	pass
