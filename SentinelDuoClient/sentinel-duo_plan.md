SentinelDuo Implementation Plan

 Context

 SentinelDuo is a fully autonomous two-client TBC Frost Mage dungeon farming bot for Stratholme SE. The design doc at SentinelDuo/sentinel-duo-design.md is the authoritative spec. This plan implements all 8 phases in the order mandated by SentinelDuo/CLAUDE.md. The system has three components:
 - SentinelDuoCoordServer (Rust, :7300) — shared state bus, heartbeat, barriers, lockout
 - SentinelDuoFarm (Lua ×2) — one instance per WoW client, full farm loop
 - spell_data.lua — static MaNGOS spell table

 Output directory structure (all new files):
 SentinelDuo/
 ├── server/sentinel-duo-coord-server/   ← Phase 1
 └── client/SentinelDuoFarm/            ← Phases 2–8

 ---
 Phase 1: Rust Coordination Server

 Root: SentinelDuo/server/sentinel-duo-coord-server/

 Files to create

 Cargo.toml — standalone package (not workspace member):
 [package]
 name = "sentinel-duo-coord-server"
 version = "0.1.0"
 edition = "2021"
 [dependencies]
 tokio = { version = "1.35", features = ["full"] }
 axum = "0.7"
 serde = { version = "1.0", features = ["derive"] }
 serde_json = "1.0"
 tracing = "0.1"
 tracing-subscriber = "0.3"
 tower-http = { version = "0.5", features = ["trace", "timeout"] }
 anyhow = "1.0"
 toml = "0.8"
 [dev-dependencies]
 tower = { version = "0.4", features = ["util"] }
 http-body-util = "0.1"
 tokio = { version = "1.35", features = ["full"] }

 config.toml — from design doc §3.3 exactly.

 src/config.rs — Config { server: ServerConfig, session: SessionConfig, lockout: LockoutConfig } with TOML loading; fall back to defaults if file missing.

 src/error.rs — AppError enum with thiserror. Variants: InvalidParams(String)→400, NotFound(String)→404, Internal(String)→500. Implements IntoResponse → Json({"error":..., "code":...}).

 src/state.rs — All types from design doc §3.4 exactly:
 - ClientPhase (all 21 variants, serde(rename_all="snake_case"))
 - ClientState — IMPORTANT: last_heartbeat: Option<Instant> is NOT serializable. Implement custom Serialize that skips it, or keep last_heartbeat out of the serialized form and only serialize connected: bool. Use #[serde(skip)] on last_heartbeat.
 - BarrierState — similarly #[serde(skip)] on entered_at: Option<Instant>.
 - SessionPhase, LockoutState, SessionState
 - Additional fields needed (not in §3.4 but required by route logic):
   - SessionState.mage_a_advance_ready: bool
   - SessionState.mage_b_advance_ready: bool
   - SessionState.start_time: Option<Instant> (#[serde(skip)])
 - pub type SharedState = Arc<Mutex<SessionState>>

 src/routes/health.rs — GET /health. Computes uptime_secs from session_start. Returns JSON per design doc §3.5.

 src/routes/session.rs — Two handlers:
 1. GET /api/v1/session — lock mutex, serialize session, return JSON. Response includes session_phase, pull_index, puller_id, runs_completed, mage_a, mage_b.
 2. GET /api/v1/heartbeat?client_id=&phase=&hp=&mp=&bags_full=&is_dead=&in_instance= — Core endpoint:
   - Lock mutex
   - Role assignment: if client_id param is empty/unknown: if mage_a.id is empty → assign "mage_a", else assign "mage_b"
   - Update this client's record: phase, hp, mp, bags_full, is_dead, in_instance, last_heartbeat = Some(Instant::now()), connected = true
   - Check partner's last_heartbeat: if elapsed > heartbeat_timeout_ms → set partner connected=false, phase=Offline
   - Update session_start if None
   - Return extended session JSON with assigned_client_id, your_role, lockout, vendor_break_requested fields

 src/routes/barrier.rs — Three handlers:
 1. GET /api/v1/barrier/enter?client_id=&name= — Create barrier entry if missing; set mage_a_ready or mage_b_ready; return status. entered_at set on first client to enter.
 2. GET /api/v1/barrier/poll?client_id=&name= — Return current barrier state. If waiting_ms > barrier_timeout_ms AND partner is Offline → set partner_disconnected: true. waiting_ms = entered_at.elapsed().as_millis() (or 0 if not entered).
 3. GET /api/v1/barrier/release?client_id=&name= — Clear this client's ready flag from the barrier; if both cleared, remove barrier entry from map. Returns {"ok": true}.

 src/routes/role.rs — GET /api/v1/pull/advance?client_id= — Mark advance ready; if both ready: pull_index += 1, toggle puller_id, clear advance flags. Return {new_pull_index, new_puller_id, farm_complete}. farm_complete is always false on server (server doesn't know total pulls — Lua decides).

 src/routes/lockout.rs — GET /api/v1/lockout/record?client_id= — Implement record_reset() logic from design doc §8.2 exactly. Sliding 1-hour window. Returns {reset_count, near_limit, must_wait, wait_remaining_secs, window_resets_at_secs}.

 src/routes/vendor.rs — GET /api/v1/vendor/request?client_id= — Set vendor_requested_by = Some(client_id). Returns {vendor_break_active: true, requested_by}.

 src/routes/admin.rs — GET /api/v1/admin/reset — Replace *state = SessionState::default(). Returns {"ok": true}.

 src/routes/mod.rs — Register all routes with Axum Router. Apply TraceLayer.

 src/main.rs — Load config, init tracing subscriber, create SharedState, bind 0.0.0.0:7300 (or config), mount routes.

 tests/integration.rs — 9 integration tests using tower::ServiceExt::oneshot:
 1. Client A registers as mage_a on first heartbeat
 2. Client B registers as mage_b on second heartbeat
 3. Heartbeat updates state fields correctly
 4. Heartbeat timeout marks partner connected=false after heartbeat_timeout_ms
 5. Barrier enter→poll→release full flow (both clients enter → both_ready=true)
 6. Barrier timeout returns partner_disconnected when partner offline > 90s
 7. pull/advance increments index and toggles puller when both ready
 8. lockout/record tracks resets, near_limit at 4, must_wait at 5
 9. admin/reset clears all state

 Verification: cargo build && cargo test must pass with no warnings.

 ---
 Phase 2: Spell Data Layer

 Root: SentinelDuo/client/SentinelDuoFarm/spells/

 spell_data.lua — Copy exact table from design doc §5.2. All 27+ spell entries verbatim.

 SpellCatalog.lua — Implement interface from design doc §5.3:
 - SpellCatalog:new(spell_data_table) — build _by_name index: {[name] = [{spell_id, rank, entry},...]} sorted by rank ascending
 - SpellCatalog:resolve(spell_name, player) — iterate all entries for name, pcall(core.spell_book.has_spell, id), return id with highest rank
 - SpellCatalog:resolve_by_id(spell_id) → entry or nil
 - SpellCatalog:get_mana_cost(spell_name, player) → number (0 if not found)
 - SpellCatalog:get_cooldown_remaining(spell_name, player) → seconds via core.spell_book.get_spell_cooldown(resolved_id)
 - SpellCatalog:is_ready(spell_name, player) → bool: has_spell AND GCD < 0.1 AND cooldown < 0.1. Use pcall around all PS API calls.

 ---
 Phase 3: Lua Core Infrastructure

 Root: SentinelDuo/client/SentinelDuoFarm/

 lib/json.lua — Copy sentinel/lib/JSON.lua verbatim (it's a complete JSON encoder/decoder, 16KB). Reference: /mnt/c/Users/Levi/Desktop/Sylvannas/scripts/sentinel/lib/JSON.lua

 core/Config.lua — Static config table from design doc §4.3:
 local Config = {
     coord_server_url = "http://127.0.0.1:7300",
     poll_interval_ms = 300,
     barrier_poll_interval_ms = 500,
     http_timeout_ms = 600,
     debug_overlay = false,
     session_max_runtime_ms = 14400000,
 }
 return Config

 core/Blackboard.lua — Adapted from sentinel/core/blackboard.lua (simpler — no schema validation needed for duo):
 - Blackboard:new() → {_data = {}}
 - Blackboard:get(key, default), Blackboard:set(key, value), Blackboard:has(key), Blackboard:clear(key), Blackboard:clear_prefix(prefix) — iterate _data and remove matching keys
 - Blackboard:snapshot(prefix) — return copy of all keys starting with prefix

 core/EventBus.lua — Copy pattern from sentinel/core/event_bus.lua:
 - EventBus:new(), subscribe(event, handler) → token, publish(event, data), unsubscribe(token)
 - No priority sorting needed (simpler for duo context)

 core/StateMachine.lua — Table-driven FSM from design doc §4.6:
 -- states_table: { [state_name] = {enter=fn, update=fn, exit=fn} }
 -- update() returns next_state_name | nil
 StateMachine:new(name, states_table, initial_state, blackboard)
 StateMachine:tick(blackboard) -- call enter on init, update each frame, transition on non-nil return
 StateMachine:transition_to(state_name, blackboard) -- forced transition
 StateMachine:get_current_state() → string
 Every transition logs: [DuoFarm] STATE: {old} → {new}  [pull={idx}, role={role}, hp={hp}%, mp={mp}%]
 Store last 100 transitions in circular buffer at bb:get("duo._state_trace").

 coordination/PartnerState.lua — Data class from JSON response:
 - PartnerState:new(json_table) → parses phase, health_pct, mana_pct, bags_full, is_dead, in_instance, connected
 - PartnerState:is_alive() → not self.is_dead
 - PartnerState:is_online() → self.connected
 - PartnerState:is_in_combat() → phase is one of: pull_running, pull_ice_block, aoe_opening, aoe_both

 coordination/CoordClient.lua — HTTP coordination client per design doc §4.5:
 - CoordClient:new(config) → {_server_url, _poll_interval_ms, _pending=false, _pending_since_ms=0, _session=nil, _barrier_pending={}, _connected=false, _my_client_id=nil}
 - CoordClient:tick(blackboard, game_time_ms):
   - If _pending AND game_time_ms - _pending_since_ms > config.http_timeout_ms * 2: clear _pending, set duo.coord_connected=false
   - If not _pending AND game_time_ms - _last_poll_ms > _poll_interval_ms: dispatch heartbeat
   - Heartbeat URL: {url}/api/v1/heartbeat?client_id={id}&phase={phase}&hp={hp}&mp={mp}&bags_full={0|1}&is_dead={0|1}&in_instance={0|1}
   - Callback: parse JSON, update blackboard keys from §4.4, set _connected=true, store _session
 - CoordClient:enter_barrier(name) → dispatches GET /api/v1/barrier/enter?client_id=&name=, stores result in _barrier_results[name]
 - CoordClient:poll_barrier(name) → dispatches GET /api/v1/barrier/poll, returns true if both_ready, "timeout" if partner_disconnected; false otherwise
 - CoordClient:release_barrier(name) → dispatches GET /api/v1/barrier/release
 - CoordClient:advance_pull(), CoordClient:record_reset(), CoordClient:request_vendor_break() — fire-and-update pattern
 - CoordClient:get_session(), CoordClient:is_connected()
 - All core.http_get calls use pcall wrapper

 navigation/NavAdapter.lua — Adapted from sentinel/integrations/nav_client/adapter.lua:
 - Wraps _G.SentinelNavClient.client (requires SentinelNavClient to be loaded)
 - NavAdapter:new(), NavAdapter:move_to(target, opts), NavAdapter:follow_path(nodes, opts), NavAdapter:stop(reason), NavAdapter:poll() → (state, progress), NavAdapter:is_active(), NavAdapter:get_state()
 - States: "idle", "requesting_path", "moving", "stuck", "failed"

 navigation/DuoNav.lua — Thin wrapper per design doc §8.5:
 - DuoNav:new(nav_adapter, blackboard)
 - DuoNav:move_to(target_vec3) — calls nav_adapter, resets stuck counter
 - DuoNav:follow_path(waypoints) — delegates
 - DuoNav:poll() — polls adapter; on "stuck": increment duo.nav_stuck_count, after 3 publish duo:stuck_escalation; retry with apply_lateral_jitter(target, 2.0)
 - DuoNav:stop(), DuoNav:is_arrived(threshold_yards) — checks player position vs last target
 - apply_lateral_jitter(pos, max_yards) — random X/Y offset within max_yards

 core/App.lua — Top-level orchestrator per design doc §4.3:
 - Owns: Blackboard, EventBus, Config, CoordClient, NavAdapter, DuoNav, SpellCatalog, master StateMachine, UI, profile
 - App:new(), App:initialize() — create all subsystems, build master FSM state table, register all states
 - App:on_pre_tick() — safety guard (nil check player)
 - App:on_update():
   a. Guard: local player = core.object_manager.get_local_player(); if not player then return end
   b. Refresh sensors → write to blackboard: player.hp_pct, player.mp_pct, player.position, player.is_dead, player.is_ghost, player.is_casting, player.in_instance (via core.get_map_id() == profile.instance_map_id)
   c. Count free bag slots → duo.bags_full_local; if full → coord_client:request_vendor_break()
   d. coord_client:tick(bb, core.game_time())
   e. duo_nav:poll()
   f. master_fsm:tick(bb)
   g. If in farm state: call active_combat:tick(bb) if applicable
   h. ui:sync(bb)
 - App:on_render() — overlay rendering (§9.4)
 - App:on_render_menu() — PS menu tree node
 - Helper: count_free_bag_slots() from design doc §8.3 exactly

 ---
 Phase 4: Farm States & Combat

 Root: SentinelDuo/client/SentinelDuoFarm/

 combat/AoeRotation.lua — AoE rotation per design doc §7.3. Priority order:
 1. HP < 20% → Ice Block (or Cold Snap + IB). core.input.cast_self_spell(ice_block_id)
 2. Ice Barrier missing → cast Ice Barrier
 3. Blizzard recast: game_time - channel_start_ms >= 7500 → core.input.cast_position_spell(blizzard_id, blizzard_center)
 4. Frost Nova off CD AND mobs not all rooted → cast Nova
 5. Mana < 20% AND Cold Snap ready → Cold Snap
 6. Mana < 15% AND Evocation ready AND no mobs in 8yd → Evocation
 - Track _channel_start_ms in blackboard duo.blizzard_channel_start_ms
 - Mob scan every 500ms: unit_helper:get_enemy_list_around(blizzard_center, 25, false, false). Count == 0 for 2 consecutive → duo.all_mobs_dead = true
 - All cast calls guarded by pcall and last_cast_ms >= 100ms

 combat/DefensiveManager.lua — Defensive CDs:
 - Track Ice Barrier buff: player:get_aura(ice_barrier_id) via pcall
 - Track Ice Block active: check if duo.ice_block_cast_ms is within 10s
 - Emergency IB on HP < 20%
 - Cold Snap usage tracking
 - DefensiveManager:tick(bb) — called every frame in farm states

 combat/PullExecutor.lua — Pull running logic per design doc §7.2:
 - PullExecutor:new(duo_nav, spell_catalog, blackboard)
 - PullExecutor:start(pull_def) — set waypoint index 0, reset mob count
 - PullExecutor:tick(bb) → returns "running" | "ib_time" | "abort":
   - Navigate to next waypoint via duo_nav; on arrival: scan enemies in aggro_radius
   - Tag mobs: cast pull_tag_spell on nearest untagged enemy via core.input.cast_target_spell()
   - Track mob count in duo.mob_count_in_pack
   - If mob_count >= timing.pull_to_ib_mob_count: return "ib_time"
   - If at path end with < expected_mob_count_min: return "abort"
   - Check mob_ids_avoid to skip elites

 states/StateInit.lua — Per design doc §7.1:
 - enter: start coord server polling
 - update: check bb:get("duo.my_client_id") not nil (set by first heartbeat response)
   - Detect Key to the City: scan bag -2 and bags 0-4 for item 12382 via core.inventory.get_items_in_bag(bag_id); set duo.has_instance_key
   - If duo.my_client_id set: return "COORD_CONNECT"
   - If 5s elapsed with no response: core.log_error; retry
 - exit: log role assigned

 states/StateCoordConnect.lua — Wait for partner:
 - update: if duo.partner_connected == true: return "BUFFING"; if 120s timeout: return "BUFFING" (solo mode, log warning)

 states/StateBuffing.lua — Per design doc §7.1:
 - Cast Ice Armor (highest rank via SpellCatalog), Ice Barrier
 - Conjure Water if < 5 stack
 - Drink if mana < 80%
 - Transition to "TRAVEL_TO_INSTANCE" when all buffs active AND mana > 80%

 states/StateTravelToInstance.lua:
 - enter: duo_nav:follow_path(profile.entrance_walk_path)
 - update: if player.position within 5 yards of profile.entrance_position: duo.at_instance_entrance=true; return "ENTERING"

 states/StateEntering.lua — Per design doc §7.1:
 - If duo.is_puller AND duo.has_instance_key AND gate not open (player Z matches outdoor): interact gate object via core.input.interact_object(gate_obj) (find by object_id)
 - Wait at enter_instance barrier
 - Detect core.get_map_id() == profile.instance_map_id → return "FARMING"

 states/StateFarming.lua — Farm sub-FSM controller:
 - Owns farm sub-FSM (separate StateMachine instance)
 - enter: create farm sub-FSM, bb:set("duo.farm_exit_reason", nil)
 - update: tick farm sub-FSM; handle vendor_break_active and bags_full conditions; on farm_complete or vendor_break_active: return "EXITING"; on player.is_dead: return "DEAD"
 - exit: stop farm sub-FSM

 states/farm/ — All farm sub-states:

 FarmPositioning.lua:
 - Puller: nav to pull.pull_path[1]; support: nav to pull.safe_position
 - On arrival: enter pull_start barrier

 FarmPullRunning.lua:
 - Puller: delegate to PullExecutor:tick(). On "ib_time": return "FARM_PULL_ICEBLOCK". On "abort": return "FARM_ABORT_PULL"
 - Support: wait at safe_position, tick DefensiveManager

 FarmPullIceBlock.lua:
 - Puller: nav to pull.ice_block_position, cast Ice Block: core.input.cast_self_spell(45438), set duo.ice_block_cast_ms, enter ice_block_up barrier
 - Support: wait, tick defensive

 FarmAoeOpening.lua:
 - Support: cast Blizzard at pull.blizzard_center, set duo.blizzard_channel_start_ms, enter ice_block_cancel barrier
 - Puller: remain in Ice Block, monitor duration

 FarmIceBlockCancel.lua:
 - Wait timing.ice_block_cancel_delay_ms (jittered)
 - Puller: cast any spell to cancel IB (Frost Nova cancels it; per design doc §7.2 "cast any spell"), then Frost Nova, nav to pull.puller_reposition
 - Support: continue Blizzard
 - Both: return "FARM_AOE_BOTH" when ready

 FarmAoeBoth.lua:
 - Both: tick AoeRotation:tick(bb, pull.blizzard_center)
 - On duo.all_mobs_dead == true: enter pull_complete barrier → return "FARM_LOOTING"

 FarmLooting.lua:
 - Wait timing.loot_settle_ms (jittered)
 - Delegate to LootEngine:loot_all_in_area(pull.blizzard_center, 30)
 - On complete: enter loot_complete barrier → call coord_client:advance_pull() → return "FARM_ADVANCE"

 states/StateExiting.lua:
 - If profile.exit_use_death == true: run to mobs to die (or just let health drop) — in practice nav toward Profile.exit_position which puts player in mob range
 - Detect outside instance (core.get_map_id() != profile.instance_map_id)
 - Enter ready_to_exit barrier
 - Check bb:get("duo.farm_exit_reason"): if "vendor" → return "TRAVEL_TO_VENDOR"; else → return "RESETTING"

 states/StateResetting.lua:
 - Enter ready_to_reset barrier
 - If duo.my_client_id == "mage_a" (party leader): call core.game_ui.reset_instances() then coord_client:record_reset()
 - Check duo.lockout.must_wait: if true → return "WAITING_LOCKOUT"
 - Else → bb:clear_prefix("duo.farm_"), return "BUFFING"

 states/StateWaitingLockout.lua:
 - Sit, drink, rebuff
 - update: if duo.lockout.wait_secs <= 0: return "BUFFING"

 states/StateDead.lua — Per design doc §8.1:
 - enter: record death in duo.deaths_this_session + 1
 - update: if player.is_ghost: nav to core.game_ui.get_corpse_position(); if within 4 yards AND core.game_ui.get_resurrect_corpse_delay() <= 0: call core.game_ui.resurrect_corpse() with jitter 0-3s; if alive: return "BUFFING"

 states/StatePaused.lua:
 - enter: stop nav, stop combat
 - update: check duo.user_paused flag; if false: return previous state

 states/StateError.lua:
 - enter: log error, stop all, set duo.bot_running = false

 ---
 Phase 5: Travel & Vendor States

 loot/LootEngine.lua:
 - LootEngine:scan_lootable_corpses(center, radius) — core.object_manager.get_all_objects(), filter: obj:is_dead() AND obj:can_be_looted() (or :is_glow())
 - LootEngine:loot_corpse(corpse) — nav within 4 yards, pcall(corpse.interact, corpse), wait for loot window, loot all items with core.input.loot_item(slot) with 150-350ms jittered delays
 - LootEngine:loot_all_in_area(center, radius) — iterate all, loot each, skip if timeout 5s

 travel/HearthstoneManager.lua — Per design doc §8.3:
 - Find HS in bags (item 6948): scan bags 0-4, use core.input.use_item(bag_id, slot_id)
 - Wait for cast (10s): detect via player:is_casting_spell(8690) or 10s timer
 - Poll core.get_map_id() until == profile.vendor_route.hearthstone_dest_map_id
 - Timeout after hs_landing_detect_timeout_ms

 travel/VendorInteractor.lua:
 - Nav to vendor_position via DuoNav
 - Find vendor NPC in core.object_manager.get_all_objects() by npc:get_npc_id() == vendor_npc_id
 - pcall(vendor.interact, vendor) to open vendor window
 - Sell all items: iterate bags, skip protected items (12382, 6948, conjured), sell with 200-500ms jitter
 - Repair if profile.vendor_route.repair_at_vendor

 travel/FlightMasterInteractor.lua:
 - Nav to flight_master_position via DuoNav
 - Interact with NPC
 - Select flight: core.input.select_taxi_route(dest_name) — TODO if PS API not available
 - Detect landing: player stops moving AND core.get_map_id() == flight_dest_map_id AND position near flight_dest_position
 - Timeout after flight_arrive_detect_timeout_ms

 states/StateTravelToVendor.lua:
 - enter: set duo.vendor_sell_complete = false
 - update: orchestrate HearthstoneManager → VendorInteractor in sequence
 - Enter ready_to_vendor barrier, then vendor_complete barrier → return "TRAVEL_RETURN"

 states/StateVendoring.lua:
 - Delegate to VendorInteractor
 - Conjure food/water after selling
 - Signal vendor_complete barrier

 states/StateTravelReturn.lua:
 - Nav to flight_master_position, interact FlightMasterInteractor
 - After flight lands: duo_nav:follow_path(profile.vendor_route.walkback_path)
 - On arrival at profile.entrance_position: enter return_complete barrier → return "BUFFING"

 ---
 Phase 6: Profiles

 profiles/ProfileLoader.lua:
 - ProfileLoader:load(profile_name) — require("profiles/" .. profile_name), validate required fields exist (id, pulls, vendor_route, etc.), return table

 profiles/stratholme_se.lua — Copy exact profile from design doc §6.3 verbatim. Every vec3 gets a comment: -- VERIFY IN-GAME: approximate

 ---
 Phase 7: UI

 ui/DuoWindow.lua — Create SentinelUI window (import or copy rotation_settings_ui.lua as lib/sentinel_ui.lua):
 local _ui = SentinelUI.new({ id="sentinel_duo_control", title="SentinelDuo",
     default_x=560, default_y=80, default_w=900, default_h=720, theme="sentinel", render_layer=1 })
 Owns 5 tab modules.

 ui/tabs/DashboardTab.lua — Per design doc §9.3 Tab 1:
 - Bot status indicator
 - START/STOP/PAUSE/FORCE VENDOR/EMERGENCY STOP buttons via core.menu.button
 - Mage A / Mage B panels (HP/MP bars via core.graphics.rect_2d_filled, labels via core.graphics.text_2d)
 - Session stats bar
 - Lockout alert banner

 ui/tabs/CoordTab.lua — Server status, partner heartbeat, barrier state table, Reset Session button.

 ui/tabs/StatsTab.lua — Runs, gold, GPH, run time, deaths, vendor trips, items looted. Reset stats button.

 ui/tabs/ProfileTab.lua — Profile dropdown, timing sliders, min mana/HP sliders, bags threshold, Reload Profile button.

 ui/tabs/DebugTab.lua — View selector (1=blackboard dump, 2=state trace, 3=coord log). All from blackboard.

 3D Overlay in App:on_render() — Per design doc §9.4: draw pull paths (blue lines), Blizzard circles (purple), safe positions (green), mob count text at IB positions. Toggle via duo.show_overlay.

 ---
 Phase 8: Integration Wiring

 header.lua:
 plugin["name"] = "SentinelDuoFarm"
 plugin["version"] = "1.0.0"
 plugin["author"] = "Levi + Codex"
 local player = core.object_manager.get_local_player()
 local ok = player and (player:get_class() == enums.class_id.MAGE)
     and (core.get_game_version and core.get_game_version() == "Tbc")
 plugin["load"] = ok == true

 main.lua — Per design doc §4.2 exactly:
 local App = require("core/App")
 local _app = nil
 core.register_on_pre_tick_callback(function() if _app then _app:on_pre_tick() end end)
 core.register_on_update_callback(function()
     if not _app then _app = App:new(); _app:initialize() end
     _app:on_update()
 end)
 core.register_on_render_callback(function() if _app then _app:on_render() end end)
 core.register_on_render_menu_callback(function() if _app then _app:on_render_menu() end end)

 lib/helpers.lua — Shared helpers:
 local function jitter(base_ms, pct) ... end  -- §11.1
 local function log(msg) pcall(core.log, "[DuoFarm] " .. tostring(msg)) end
 local function log_err(msg) pcall(core.log_error, "[DuoFarm] ERROR: " .. tostring(msg)) end

 Final validation checklist:
 - Every coord server endpoint called from Lua has a corresponding Rust handler
 - Every duo.* blackboard key written has a reader
 - All 21 Lua state handlers have enter/update/exit
 - All 11 barrier names in CoordClient match the Rust barrier table
 - All farm sub-FSM states from design doc §7.2 implemented
 - cargo build && cargo test passes
 - luac -p passes on all Lua files

 ---
 Critical Implementation Notes

 1. Instant serialization: ClientState.last_heartbeat and BarrierState.entered_at use #[serde(skip)]. The connected: bool field communicates liveness in JSON. Barrier waiting_ms is computed on-the-fly from entered_at.elapsed().
 2. Async HTTP pattern: Never assume core.http_get callback fires synchronously. CoordClient uses _pending=true guard. Timeout detection: if game_time - _pending_since_ms > http_timeout_ms * 2, clear pending and mark disconnected.
 3. require() paths: Relative to the script root (SentinelDuoFarm/). Use require("core/Config"), require("spells/spell_data"), etc.
 4. Lua Blackboard vs sentinel Blackboard: DuoFarm's Blackboard is a simplified copy — no schema validation. All keys prefixed duo. to avoid collision.
 5. Pull advance logic: Server tracks mage_a_advance_ready and mage_b_advance_ready in SessionState (extra fields beyond §3.4). When both true: increment pull_index, swap puller.
 6. Ice Block cancel: In TBC, casting any spell while Ice Block is active cancels it. PullExecutor casts Frost Nova immediately after entering FARM_ICE_BLOCK_CANCEL state, which both cancels Ice Block and roots mobs.
 7. SentinelNavClient dependency: NavAdapter requires _G.SentinelNavClient.client to be loaded. DuoFarm expects SentinelNavClient to be enabled. Document in CLAUDE.md.

 ---
 Verification

 Rust server:
 cd SentinelDuo/server/sentinel-duo-coord-server
 cargo build --release   # must succeed
 cargo test              # all 9 tests must pass
 cargo clippy            # no warnings

 Lua files:
 # For each .lua file:
 luac -p SentinelDuo/client/SentinelDuoFarm/main.lua
 luac -p SentinelDuo/client/SentinelDuoFarm/core/App.lua
 # ... etc for all files

 End-to-end smoke test (manual, in-game):
 1. Start coord server: ./sentinel-duo-coord-server
 2. GET http://127.0.0.1:7300/health → should return {"status":"ok",...}
 3. Load SentinelDuoFarm on a Mage character → plugin loads, no errors in console
 4. UI window opens with Dashboard tab
 5. First heartbeat: check GET /health shows clients_connected: 1