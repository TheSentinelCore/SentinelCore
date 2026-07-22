---
id: 17
title: Runtime Fix Tickets — Sylvannas API Compliance & Execution Model
type: Tracking
status: In Progress
---

## Waves (Dependency-Ordered)

Per `corrections.md_Corrections_ticket_order_workflow`, tickets must be addressed in dependency-ordered sequence.

### Wave 1 — Core Schema & Time API ✅ Completed

**Goal**: Fix blocking schema mismatches and replace forbidden `_G.GetTime` with Sylvannas APIs.

| Issue | Description | Dependencies | Status |
|-------|-------------|--------------|--------|
| 1 | **Schema Mismatch**: Lua `op.action` vs Rust `op.actions[]`<br>• File: `runtime_profile.lua:612`<br>• Change `local action = op.action` to use `op.actions[self._current_action_idx]`<br>• Add `self._current_action_idx` field to track current action within operation<br>• Initialize to 1 when operation changes, increment on action success, reset when moving to next operation | None | ✅ COMPLETED |
| 2 | **Position Field Mismatch**: Lua checks `p.position.x` but compiler emits `RuntimeWaypoint {map, world_x, world_y, world_z}`<br>• File: `runtime_profile.lua:852-853` in `_resolve_nav_target`<br>• Accept both `{x, y, z}` (legacy) and `{world_x, world_y, world_z, map}` formats<br>• File: `runtime_action.lua:105` in `execute_travel`<br>• Use `payload.position` when available (world_x/world_y/world_z) | None | ✅ COMPLETED |
| 3 | **Time API**: Replace `_G.GetTime()` with `core.time()` (seconds) or `core.game_time()/1000` (milliseconds)<br>• `runtime_profile.lua`: lines 81, 541, 567, 715, 763, 809, 832<br>• `runtime_action.lua`: lines 258, 262<br>• Use `core.time()` for script-time consistency (wait timers, etc.)<br>• Use `core.game_time()/1000` only if millisecond precision is specifically needed for game sync | None | ✅ COMPLETED |
| 4 | **Condition Serde Shape**: Lua expects `{type = "...", payload = ...}` but compiler emits externally tagged `{"QuestAccepted": 33}`<br>• File: `runtime_action.lua:281-301` in `evaluate_condition`<br>• Add support for externally tagged format: if `cond[typename]` exists, treat as `{type = typename, payload = cond[typename]}`<br>• Line 297 & 329: Change `return true` to `return false` for unknown conditions (fail closed, not fail open)<br>• This prevents gates from silently opening when condition types are unrecognized | None | ✅ COMPLETED |

### Wave 2 — Action Logic Fixes ✅ Completed

**Goal**: Fix broken action implementations that return incorrect status or never actually perform work.

| Issue | Description | Dependencies | Status |
|-------|-------------|--------------|--------|
| 5 | **Wait Action Always Returns "success"**: Never actually waits; lines 255-266 in `runtime_action.lua`<br>• Line 259: Returns "success" when starting wait (should be "blocked")<br>• Line 266: Returns "success" when still waiting (should be "blocked"/"retry")<br>• Fix: Return "blocked" while waiting, "success" when time elapsed | None | ✅ COMPLETED |
| 6 | **Kill Action False Success**: Returns "success" without verifying kill; lines 161-187<br>• Line 168-169: Returns "success" if target is already dead (correct)<br>• Line 186: Returns "success" when in range, trusting kill loop (INCORRECT)<br>• Fix: Actually track kills against `payload.quantity`<br>• Only return "success" when required number of kills achieved | None | ✅ COMPLETED |
| 7 | **TurnInQuest False Success**: Returns "success" when APIs missing or quest not completed; lines 94-99<br>• Line 94-96: Checks `_G.SentinelCore.HasQuest` but returns "success" on line 98-99 if check fails<br>• Fix: Return "retry" when APIs missing, "blocked" when not at NPC, only "success" when quest actually turned in | None | ✅ COMPLETED |
| 8 | **Vendor Always Success**: Lines 207-227 must verify vendor interaction results<br>• Currently always returns "success" if at NPC<br>• Fix: Check results of `_G.SentinelCore.SellGreys()`, `Repair()`, `BuyItems()` and return appropriate status | None | ✅ COMPLETED |
| 9 | **Soft-Lock on Blocked No Nav Target**: Lines 817-820 in `runtime_profile.lua` increment retries forever without checking `MAX_RETRIES_PER_ACTION`<br>• After `self._current_action_retries = self._current_action_retries + 1`<br>• Add: `if self._current_action_retries >= MAX_RETRIES_PER_ACTION then`<br>• `self._consecutive_failures = self._consecutive_failures + 1`<br>• `self:_check_consecutive_failures()`<br>• `self._current_operation_idx = self._current_operation_idx + 1`<br>• `return "running", "retries exhausted, skipping operation"` | Wave 1 | ✅ COMPLETED |

### Wave 2 Additional Fix — "Any" Condition Handler Bug

During Wave 2 implementation, an additional bug was found in the condition evaluation logic:

- **Bug**: The "Any" condition handler at `runtime_action.lua:422` returned `false` instead of `true` when any sub-condition passed, causing gates with "Any" conditions to never open.
- **Fix**: Changed the return value to `true` when any sub-condition evaluates successfully, allowing "Any" conditions to properly short-circuit and pass through.

### Wave 3 — Sylvannas API Replacement ✅ Completed

**Goal**: Replace all fabricated/non-Sylvannas APIs with documented equivalents from `Documentation - Project Sylvannas/dev/api/`.

| Issue | Description | Dependencies | Status |
|-------|-------------|--------------|--------|
| 10 | **Fabricated `core.object_manager.*` APIs**: Replace `GetNearestCreature`, `GetNearestGameObject`, `GetCompletedQuests`, `GetActiveQuests`, `GetQuestObjectiveInfo`, `GetItemCount`, `GetPlayerInfo`<br>• Replace with: `core.object_manager.get_all_objects()` + filtering<br>• Or use `unit_helper` library for optimized retrieval<br>• Files: `runtime_profile.lua` (ctx:_get_npc_position, ctx:_get_object_position, ctx:is_at_npc, ctx:is_at_object, ctx:_refresh_quest_log, ctx:get_player_level, etc.)<br>• Files: `runtime_action.lua` (ctx:is_at_npc, ctx:is_at_object, ctx:get_item_count, ctx:get_money, etc.) | Wave 1 | ✅ COMPLETED |
| 11 | **Phantom `core.unit("player")` Facade**: Replace with `get_local_player():get_*()` methods<br>• `core.object_manager.get_local_player():get_level()` instead of `core.unit.get_level("player")`<br>• `get_local_player():get_class()` instead of `core.unit.get_class("player")`<br>• `get_local_player():get_race()` instead of `core.unit.get_race("player")`<br>• `get_local_player():get_health()` instead of `core.unit.get_health("player")`<br>• `core.inventory.get_gold()` instead of `core.unit.get_money()`<br>• Files: `runtime_profile.lua` and `runtime_action.lua` | Wave 1 | ✅ COMPLETED |
| 12 | **Wrong Method Casing**: Fix `IsValid()` → `is_valid()`, `IsDead()` → `is_dead()`<br>• Files: `runtime_profile.lua:271, 299, 884, 903`; `runtime_action.lua:167, 168, 433, 465, 476`<br>• All `game_object:*` methods use snake_case in Sylvannas API | Wave 1 | ✅ COMPLETED |
| 13 | **Wrong Input/Spell Namespaces**: Replace `core.input.move(x,y,z)`, `core.input.release_corpse()`, `core.spell.get_item_cooldown`, `core.print(...)` with documented APIs<br>• `core.input.move` → Use `NavigationAdapter` for movement (already wrapped in ctx.nav)<br>• `core.input.release_corpse` → `core.input.release_spirit()` or `core.input.resurrect_corpse()`<br>• `core.spell.get_item_cooldown` → Check item cooldown via `core.item.get_cooldown()` or similar<br>• `core.print` → `core.log` or `core.log_error`<br>• Files: `runtime_action.lua:153-155, 778-779, 508-509, 15-16, 67-68, 22` | Wave 1 | ✅ COMPLETED |
| 14 | **Phantom `_G.SentinelCore.*` Quest Helpers**: Replace `AutoAcceptQuest`, `SelectQuestEntry`, `TurnInQuest`, `SellGreys`, `Repair`, `BuyItems`, `Train`, `TakeFlight`, `UseHearthstone`, `LearnFlightPath`, `OpenMailbox`, `OpenBank`, `InteractNpc`<br>• Replace with proper `core.quests.*` + `core.input.*` + `core.object_manager.get_local_player()`<br>• Examples:<br>  - `AutoAcceptQuest` → `core.quests.accept_quest()`<br>  - `SelectQuestEntry` → `core.quests.select_available_quest(index)` or `select_active_quest(index)`<br>  - `TurnInQuest` → `core.quests.complete_quest()` + reward selection<br>  - `SellGreys`/`Repair`/`BuyItems` → Vendor interaction via core APIs<br>  - `TakeFlight`/`UseHearthstone`/`LearnFlightPath` → Flight path handling<br>  - `OpenMailbox`/`OpenBank` → `core.input.interact_with_object` + appropriate NPC detection<br>  - `InteractNpc` → `core.input.interact_with_object` + gossip handling<br>• Files: `runtime_action.lua` (all _G.SentinelCore.* references) | Wave 1 | ✅ COMPLETED |

### Wave 4 — Architecture & Polish ✅ Completed

**Goal**: Fix architectural violations, implement missing features, and polish runtime execution.

| Issue | Description | Dependencies | Status |
|-------|-------------|--------------|--------|
| 15 | **Editor Embedded in Runtime**: Violates ADR-500 Part 1 (Lua NEVER edits/validates/compiles)<br>• Files: `editor_ui.lua`, `runtime_context.lua` referenced from runtime<br>• Fix: Move editor out of questing runtime module<br>• Runtime should only load and execute Runtime JSON<br>• Editor is a separate subsystem (ADR 01 §5.7) | Wave 3 | ✅ COMPLETED |
| 16 | **No Hot Reload**: Missing ADR-500 Part 7 implementation (detect change → version/fingerprint → swap profile → preserve variables → continue)<br>• Files: `runtime_profile.lua`<br>• Add file watcher for profile JSON changes<br>• On change: validate version/fingerprint, swap profile, preserve `_variables`, continue execution<br>• No restart required | Wave 3 | ✅ COMPLETED |
| 17 | **Profile Variables Not Initialized**: Lines 41, 204-226 ignore `variables` field from Runtime JSON<br>• File: `runtime_profile.lua:204-226` in `load()` method<br>• Fix: On load, initialize `self._variables[name] = current_value` from `self._profile.variables`<br>• Persist variables in save state<br>• Map `SetVariable` actions to update this structure | Wave 1 | ✅ COMPLETED |
| 18 | **Persistence Incomplete**: Missing current action index, completed quests, temp vars, visited vendors, flight paths, hearth, history<br>• File: `runtime_profile.lua:76-82` in `_serialize_state()`<br>• Add: `current_action_idx`, `completed_quests`, `temporary_variables`, `visited_vendors`, `known_flight_paths`, `known_hearth_location`, `execution_history`<br>• File: `runtime_profile.lua:152-157` in `_load_save()`<br>• Restore all new state fields | Wave 1 | ✅ COMPLETED |

## Acceptance Criteria

The runtime fix is complete when:
1. All `_G.GetTime` calls replaced with Sylvannas time APIs
2. Runtime correctly consumes `op.actions[]` array with proper action indexing
3. Position fields handled correctly for both legacy and new formats
4. Condition evaluation handles compiler's actual output format and fails closed on unknown types
5. Wait action properly blocks until duration elapses
6. Kill action accurately tracks and verifies required kills
7. TurnInQuest only succeeds when quest is actually turned in
8. Vendor actions verify interaction results before returning success
9. Blocked actions with no nav target respect retry limits and don't cause soft-locks
10. All fabricated APIs replaced with documented Sylvannas equivalents ✅
11. Editor completely separated from runtime execution ✅
12. Hot reload functional without losing execution state ✅
13. Variables properly initialized from Runtime JSON and persisted ✅
14. Save/restore includes all necessary execution state ✅
15. Zero clippy warnings in Rust components
16. Zero Sylvannas API violations in Lua modules ✅

## Dependencies

Wave 1 must be completed before Wave 2 can begin.
Wave 2 must be completed before Wave 3 can begin.
Wave 3 must be completed before Wave 4 can begin.

Each wave must maintain a working (though potentially incomplete) runtime after completion.