extends Node
## AudioManager — Section G.6 audio + haptics hooks.
##
## Audio is OPTIONAL for v1: the game must be fully enjoyable muted. This autoload
## wires every "something happened" EventBus signal to a named cue so adding sound
## later is drop-in — register a stream in CUES and it plays; until then the cue is
## a no-op (and, on a phone, fires a short haptic so touch still feels responsive).
##
## To add sound later: drop CC0 files in res://audio/ and fill CUES, e.g.
##   CUES = { "unit_moved": preload("res://audio/move.ogg"), ... }
## No other code changes needed.

# cue name -> AudioStream (empty until audio is sourced; see Appendix A plan).
var CUES: Dictionary = {}

# cue name -> haptic duration (ms). Phones only; desktop ignores these.
const HAPTICS := {
	"unit_moved": 12,
	"token_flipped": 18,
	"control_changed": 22,
	"combat_resolved": 40,
	"crit": 55,
	"death": 45,
	"guardian_spawned": 30,
	"old_tech_captured": 60,
	"card_played": 15,
	"button": 10,
}

var _player: AudioStreamPlayer
var _haptics_enabled := true
var _muted := false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	var bus := get_tree().root.get_node_or_null("EventBus")
	if bus != null:
		# Every reaction is one cue() call — "every action gets a reaction."
		bus.unit_moved.connect(func(_u, _f, _t): cue("unit_moved"))
		bus.token_flipped.connect(func(_c, _p, _s): cue("token_flipped"))
		bus.control_changed.connect(func(_c, _p): cue("control_changed"))
		bus.combat_resolved.connect(_on_combat_resolved)
		bus.guardian_spawned.connect(func(_g, _c): cue("guardian_spawned"))
		bus.old_tech_captured.connect(func(_p, _c): cue("old_tech_captured"))


## Play (or no-op) a named cue, plus a haptic tick on handheld devices.
func cue(name: String) -> void:
	if not _muted and CUES.has(name) and CUES[name] != null and _player != null:
		_player.stream = CUES[name]
		_player.play()
	if _haptics_enabled and HAPTICS.has(name):
		# Safe on desktop (no-op); on Android/iOS gives a short vibration.
		Input.vibrate_handheld(int(HAPTICS[name]))


## Combat emits a richer cue: a bigger hit on crits/deaths in the log.
func _on_combat_resolved(event_log) -> void:
	var emphatic := false
	if event_log is Array:
		for ev in event_log:
			if ev is Dictionary:
				var e := str(ev.get("event", ""))
				if e == "death" or (e == "die" and ev.get("crit", false)):
					emphatic = true
					break
	cue("crit" if emphatic else "combat_resolved")


func set_muted(m: bool) -> void:
	_muted = m


func set_haptics(on: bool) -> void:
	_haptics_enabled = on
