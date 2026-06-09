extends Node
## EventBus — a stateless signal hub.
##
## Per the architecture guide: UI listens, logic emits. This decouples the
## visual layer from the rules engine. NOTHING lives here but signal
## declarations — no state, no functions. (Section A, step 6.)

# --- Movement & board ---
signal unit_moved(unit, from_coord, to_coord)
signal token_flipped(coord, player, new_state)
signal control_changed(coord, player)

# --- Combat ---
signal combat_resolved(event_log)

# --- Phase / turn structure ---
signal phase_changed(new_phase)
signal turn_passed(player)

# --- Spawns & objectives ---
signal guardian_spawned(guardian, coord)
signal old_tech_captured(player, coord)
