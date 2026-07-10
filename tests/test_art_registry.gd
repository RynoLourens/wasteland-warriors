extends GutTest
## Section G.1 — art import/wiring smoke tests for the ArtRegistry autoload.
## These prove the id -> texture mapping resolves for the assets we shipped and
## degrades to null (greybox fallback) for the known-missing ones, so a missing
## file can never crash the board view.


func test_unit_textures_resolve() -> void:
	for id in [&"warrior", &"heavy", &"scout", &"gunner",
			&"berserker", &"infiltrator", &"manstopper", &"sapperteur"]:
		assert_not_null(ArtRegistry.unit(id), "unit art missing: %s" % id)


func test_guardian_textures_resolve() -> void:
	for id in [&"arachnid", &"blackout", &"blink", &"cutter",
			&"scrape", &"typhoon", &"the_ox", &"razor"]:
		assert_not_null(ArtRegistry.guardian(id), "guardian art missing: %s" % id)


func test_known_missing_art_returns_null_not_crash() -> void:
	# The ancient_artifact / falling_debris env tokens have no art (WP4 wired
	# Razor + Lil' Minerva). Both must fall back to null, never crash.
	assert_null(ArtRegistry.env(&"env_corridor_ancient_artifact"))
	assert_null(ArtRegistry.env(&"env_room_falling_debris"))


func test_unknown_id_returns_null() -> void:
	assert_null(ArtRegistry.unit(&"not_a_real_unit"))
	assert_null(ArtRegistry.card(&"action_99"))


func test_leaders_and_artefacts_resolve() -> void:
	for id in [&"general_stormfoot", &"lady_seraph", &"siyana_the_shield",
			&"the_rats_eye", &"lil_minerva"]:
		assert_not_null(ArtRegistry.leader(id), "leader art missing: %s" % id)
	for id in [&"medical_machine", &"psychic_control_belt", &"snooperbot_6000",
			&"sunstone_fragments", &"the_jam_gobbar"]:
		assert_not_null(ArtRegistry.artefact(id), "artefact art missing: %s" % id)


func test_env_func_tokens_resolve() -> void:
	for id in [&"env_room_dehydration", &"env_corridor_darkness", &"env_room_schematics"]:
		assert_not_null(ArtRegistry.env(id), "env art missing: %s" % id)
	for id in [&"func_defensive_turrets", &"func_shield_drones", &"func_teleporter_hub"]:
		assert_not_null(ArtRegistry.func_token(id), "func art missing: %s" % id)


func test_cards_resolve_by_id_and_number() -> void:
	assert_not_null(ArtRegistry.card(&"action_01"))
	assert_not_null(ArtRegistry.card("01"), "card lookup by bare number should work")


func test_tiles_resolve_and_are_deterministic() -> void:
	var a := ArtRegistry.tile("room", 2, -1)
	var b := ArtRegistry.tile("room", 2, -1)
	assert_not_null(a, "room tile should resolve")
	assert_eq(a, b, "same coord must map to the same tile face")
	assert_not_null(ArtRegistry.tile("corridor", 0, 3))
	assert_not_null(ArtRegistry.tile("center", 0, 0))


func test_any_art_present() -> void:
	assert_true(ArtRegistry.any_art_present(), "art should be detected as present")
