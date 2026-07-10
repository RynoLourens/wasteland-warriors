extends Node
## ArtRegistry — central id -> Texture2D lookup for all game art (Section G.1).
##
## Why an autoload instead of texture fields on every .tres: it keeps the data
## layer art-agnostic, lets the visual layer ask for art by id, and gives ONE
## place to handle missing assets. Any lookup that has no file returns null, and
## the board view falls back to its greybox shape — so a missing texture (e.g.
## the ancient_artifact /
## falling_debris env tokens) degrades gracefully instead of crashing.
##
## Textures are loaded lazily and cached via load(); ResourceLoader.exists()
## guards each call so an absent (or not-yet-imported) file yields null and the
## board view falls back to its greybox shape instead of erroring.

const ART := "res://art/"

# Map a unit/guardian/token/card/leader/tile id -> path under res://art/.
# Units (note: the SOLDIER token art represents the "warrior" id).
const UNIT_PATHS := {
	&"warrior": "tokens/units/warrior.png",
	&"heavy": "tokens/units/heavy.png",
	&"scout": "tokens/units/scout.png",
	&"gunner": "tokens/units/gunner.png",
	&"berserker": "tokens/special/berserker.png",
	&"infiltrator": "tokens/special/infiltrator.png",
	&"manstopper": "tokens/special/manstopper.png",
	&"sapperteur": "tokens/special/sapperteur.png",
}

const GUARDIAN_PATHS := {
	&"arachnid": "tokens/guardians/arachnid.png",
	&"blackout": "tokens/guardians/blackout.png",
	&"blink": "tokens/guardians/blink.png",
	&"cutter": "tokens/guardians/cutter.png",
	&"scrape": "tokens/guardians/scrape.png",
	&"typhoon": "tokens/guardians/typhoon.png",
	&"the_ox": "tokens/guardians/the_ox.png",
	&"razor": "tokens/guardians/razor.png",
}

const LEADER_PATHS := {
	&"general_stormfoot": "leaders/general_stormfoot.png",
	&"lady_seraph": "leaders/lady_seraph.png",
	&"siyana_the_shield": "leaders/siyana_the_shield.png",
	&"the_rats_eye": "leaders/the_rats_eye.png",
	&"lil_minerva": "leaders/lil_minerva.png",
}

const ARTEFACT_PATHS := {
	&"medical_machine": "artefacts/medical_machine.png",
	&"psychic_control_belt": "artefacts/psychic_control_belt.png",
	&"snooperbot_6000": "artefacts/snooperbot_6000.png",
	&"sunstone_fragments": "artefacts/sunstone_fragments.png",
	&"the_jam_gobbar": "artefacts/the_jam_gobbar.png",
}

# Env-token id -> art (ids carry env_room_/env_corridor_ prefixes in the .tres).
const ENV_PATHS := {
	&"env_room_dehydration": "tokens/env/dehydration.png",
	&"env_room_guardian": "tokens/env/guardian.png",
	&"env_room_turrets": "tokens/env/turrets.png",
	&"env_room_schematics": "tokens/env/schematics.png",
	&"env_room_gang_press_survivors": "tokens/env/gang_press_survivors.png",
	&"env_corridor_darkness": "tokens/env/darkness.png",
	&"env_corridor_local_fauna": "tokens/env/local_fauna.png",
	&"env_corridor_tough_terrain": "tokens/env/tough_terrain.png",
	&"env_corridor_troubling_tales": "tokens/env/troubling_tales.png",
	&"env_corridor_dead_silence": "tokens/env/dead_silence.png",
	&"env_corridor_supplies": "tokens/env/supplies.png",
	&"env_corridor_teleporter_node": "tokens/env/teleporter_node.png",
	# env_corridor_ancient_artifact, env_room_falling_debris: no art -> chip fallback.
}

const FUNC_PATHS := {
	&"func_defensive_turrets": "tokens/func/defensive_turrets.png",
	&"func_guardian_control_room": "tokens/func/guardian_control_room.png",
	&"func_shield_drones": "tokens/func/shield_drones.png",
	&"func_teleporter_hub": "tokens/func/teleporter_hub.png",
}

# Tile faces. The board generator assigns numbered drafts; we cycle the
# available faces per tile_type so different rooms/corridors look distinct.
const ROOM_TILES := ["01", "03", "04", "05", "06", "07", "09", "10"]
const CORRIDOR_TILES := ["01", "02", "03", "04", "05", "06", "07", "08", "09"]

const MISC_PATHS := {
	&"old_tech": "tokens/misc/old_tech.png",
	&"activation_front": "tokens/misc/activation_front.png",
	&"activation_back": "tokens/misc/activation_back.png",
	&"center": "tiles/center.png",
	&"room_back": "tiles/room_back.png",
	&"corridor_back": "tiles/corridor_back.png",
	&"card_back": "cards/_back.png",
	&"unit_back": "tokens/units/_back.png",
}

# Player-colour art variants (WP2 prep): internal player id -> palette suffix.
# The recoloured token PNGs live beside the originals as <id>_<palette>.png;
# the plain files remain the neutral fallback (and the greybox contract holds).
const PLAYER_PALETTE := {
	&"green": "amber",
	&"blue": "cyan",
	&"red": "crimson",
}

var _cache: Dictionary = {}

func _norm(id) -> StringName:
	return StringName(String(id))

## Lazily load + cache a texture from a res:// path. Returns null if missing
## (or not yet imported), so callers degrade to greybox.
func _tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var full := ART + path
	var t: Texture2D = null
	# Load the imported Texture2D the normal way. ResourceLoader.exists() guards the
	# call so a missing/not-yet-imported file yields null (greybox) instead of an
	# error. Requires the editor to have imported the PNGs (it does so on open).
	if ResourceLoader.exists(full):
		var res = load(full)
		if res is Texture2D:
			t = res
	_cache[path] = t
	return t

func _from(map: Dictionary, id) -> Texture2D:
	var key := _norm(id)
	if map.has(key):
		return _tex(map[key])
	return null

# --- Public lookups (all return null on miss -> caller draws greybox) ---
func unit(id) -> Texture2D: return _from(UNIT_PATHS, id)

## Owner-coloured unit token (falls back to the neutral art, then greybox).
func unit_owned(id, owner) -> Texture2D:
	var key := _norm(id)
	var pal_key := _norm(owner)
	if UNIT_PATHS.has(key) and PLAYER_PALETTE.has(pal_key):
		var base: String = UNIT_PATHS[key]
		var pal: String = PLAYER_PALETTE[pal_key]
		var t := _tex(base.replace(".png", "_" + pal + ".png"))
		if t != null:
			return t
	return unit(key)
func guardian(id) -> Texture2D: return _from(GUARDIAN_PATHS, id)
func leader(id) -> Texture2D: return _from(LEADER_PATHS, id)
func artefact(id) -> Texture2D: return _from(ARTEFACT_PATHS, id)
func env(id) -> Texture2D: return _from(ENV_PATHS, id)
func func_token(id) -> Texture2D: return _from(FUNC_PATHS, id)
func misc(id) -> Texture2D: return _from(MISC_PATHS, id)

## Action card art by id ("action_01") OR by display number.
func card(id) -> Texture2D:
	var s := String(id)
	if not s.begins_with("action_"):
		s = "action_" + s
	return _tex("cards/" + s + ".png")

## A tile face for a coord. Deterministic per (q,r) so a given hex always shows
## the same face across redraws. tile_type: "room"/"corridor"/"center".
func tile(tile_type: String, q: int, r: int) -> Texture2D:
	match tile_type:
		"center":
			return _tex("tiles/center.png")
		"corridor":
			var fc: String = CORRIDOR_TILES[abs(q * 7 + r * 13) % CORRIDOR_TILES.size()]
			return _tex("tiles/corridor_" + fc + ".png")
		_:
			var fr: String = ROOM_TILES[abs(q * 7 + r * 13) % ROOM_TILES.size()]
			return _tex("tiles/room_" + fr + ".png")

## A specific tile face by name ("room_01", "corridor_05", "center") — used by
## the WP1 exit-true render path (TileArtMatcher decides WHICH face).
func tile_face(face_name: String) -> Texture2D:
	return _tex("tiles/" + face_name + ".png")


## Edge patch sprites for WP1: kind is "door" (paint a doorway over rock where a
## real exit has no painted door) or "wall" (rock over a spurious painted door).
func tile_patch(kind: String) -> Texture2D:
	return _tex("tiles/patch_" + kind + ".png")


## True if ANY art loaded — lets the board view decide greybox vs sprite mode.
func any_art_present() -> bool:
	return _tex("tiles/center.png") != null or _tex("tokens/units/warrior.png") != null
