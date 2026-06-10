extends GutTest
## Player bag: seeded, sample-without-replacement, reproducible (Section B step 3).


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func test_starting_bag_composition() -> void:
	var p := Player.new(&"green")
	p.load_starting_bag()
	assert_eq(p.bag_size(), 12, "starting bag = 12")
	assert_eq(p.coward_count(), 6, "6 cowards")
	assert_eq(p.count_in_bag(&"warrior"), 6, "6 warriors")


func test_draw_removes_without_replacement() -> void:
	var p := Player.new(&"green")
	p.load_starting_bag()
	var drawn := p.draw_from_bag(3, _rng(1))
	assert_eq(drawn.size(), 3, "drew 3")
	assert_eq(p.bag_size(), 9, "bag shrank by 3 (no replacement)")


func test_draw_capped_at_bag_size() -> void:
	var p := Player.new(&"green")
	p.load_starting_bag()
	var drawn := p.draw_from_bag(99, _rng(1))
	assert_eq(drawn.size(), 12, "can't draw more than the bag holds")
	assert_eq(p.bag_size(), 0, "bag emptied")


func test_same_seed_same_draw() -> void:
	# Reproducibility is the whole point of seeded RNG.
	var a := Player.new(&"green"); a.load_starting_bag()
	var b := Player.new(&"green"); b.load_starting_bag()
	var da := a.draw_from_bag(5, _rng(42))
	var db := b.draw_from_bag(5, _rng(42))
	assert_eq(da, db, "identical seed -> identical draw sequence")


func test_different_seed_usually_differs() -> void:
	var a := Player.new(&"green"); a.load_starting_bag()
	var b := Player.new(&"green"); b.load_starting_bag()
	var da := a.draw_from_bag(8, _rng(1))
	var db := b.draw_from_bag(8, _rng(2))
	assert_ne(da, db, "different seeds -> different draws (overwhelmingly likely)")


func test_deploy_returns_cowards_keeps_units_out() -> void:
	var p := Player.new(&"green")
	p.load_starting_bag()
	var before := p.bag_size()
	var deployed := p.deploy(_rng(7))
	# Deployed units left the bag; cowards drawn went back. So bag shrinks by
	# exactly the number of units deployed.
	assert_eq(p.bag_size(), before - deployed.size(),
		"bag shrinks only by deployed unit count")
	for e in deployed:
		assert_ne(e, Player.COWARD, "no cowards in the deployed list")


func test_punish_removes_cowards_returns_units() -> void:
	var p := Player.new(&"green")
	p.load_starting_bag()
	var before_cowards := p.coward_count()
	var removed := p.punish_cowards(_rng(3))
	assert_eq(p.coward_count(), before_cowards - removed,
		"coward count drops by number removed")
	# Units always go back: only cowards leave.
	assert_eq(p.count_in_bag(&"warrior"), 6, "all warriors returned to bag")


func test_recruit_adds_to_bag() -> void:
	var p := Player.new(&"green")
	p.load_starting_bag()
	p.recruit([&"warrior", &"warrior", &"scout"])
	assert_eq(p.bag_size(), 15, "recruit added 3 units")
	assert_eq(p.count_in_bag(&"scout"), 1, "scout is in the bag")


func test_win_condition() -> void:
	var p := Player.new(&"green")
	assert_false(p.has_won(), "0 old tech is not a win")
	p.old_tech_count = 3
	assert_true(p.has_won(), "3 old tech wins")
