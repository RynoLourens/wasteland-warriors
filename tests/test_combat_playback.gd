extends GutTest
## Section G.3 — combat playback queue logic. We don't assert on tween timing
## (that's visual), but the queue-building, per-event delays, and emphasis flags
## are pure and worth pinning so playback can't silently regress.

var _ro


func before_each() -> void:
	_ro = CombatReadout.new()
	add_child_autofree(_ro)


func test_delay_scales_with_event_drama() -> void:
	var miss := {"event": "die", "hit": false, "crit": false}
	var hit := {"event": "die", "hit": true, "crit": false}
	var crit := {"event": "die", "hit": true, "crit": true}
	assert_lt(_ro._delay_for(miss), _ro._delay_for(hit), "a hit lingers longer than a miss")
	assert_lt(_ro._delay_for(hit), _ro._delay_for(crit), "a crit lingers longer than a plain hit")


func test_emphasis_only_on_crits_and_deaths() -> void:
	assert_true(_ro._is_emphasis({"event": "death"}))
	assert_true(_ro._is_emphasis({"event": "die", "crit": true}))
	assert_false(_ro._is_emphasis({"event": "die", "hit": true, "crit": false}))
	assert_false(_ro._is_emphasis({"event": "round_start"}))


func test_show_log_builds_a_queue_and_starts_hidden() -> void:
	var log := [
		{"event": "combat_start", "sides": [&"green", &"red"]},
		{"event": "round_start", "round": 0},
		{"event": "die", "side": &"green", "face": 6, "hit": true, "crit": true},
		{"event": "death", "side": &"red", "unit": &"warrior"},
		{"event": "combat_end", "survivors": {&"green": [&"warrior"]}},
	]
	_ro.show_log(log)
	assert_gt(_ro._queue.size(), 0, "queue should be populated")
	# Every queued node starts invisible (revealed over time by _process).
	for entry in _ro._queue:
		assert_false(entry["node"].visible, "queued lines start hidden")


func test_skip_reveals_everything() -> void:
	var log := [
		{"event": "combat_start", "sides": [&"green", &"red"]},
		{"event": "die", "side": &"green", "face": 5, "hit": true, "crit": false},
	]
	_ro.show_log(log)
	_ro._skip_to_end()
	for entry in _ro._queue:
		assert_true(entry["node"].visible, "after SKIP all lines are visible")
		assert_almost_eq(entry["node"].modulate.a, 1.0, 0.001)
