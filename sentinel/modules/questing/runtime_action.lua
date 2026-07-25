--- Sentinel Runtime Action Executor
--- Executes RuntimeAction types defined in RuntimeProfile
--- Returns: "success", "retry", "blocked", "failed", "skipped"

-- ============================================================================
-- Named constants for navigation and proximity (W3.1, W3.6)
-- ============================================================================
local NAV_RETRY_DELAY = 1.0    -- Seconds between navigation retries
local CORPSE_LOOT_RANGE = 4.0  -- Must stand this close to loot a corpse
local LOOT_ATTEMPTS = 3        -- Bound per corpse so an unlootable one cannot wedge the run
local ABANDON_RANGE = 50.0     -- Give up on a committed target that has run this far away
local HEARTH_TIMEOUT = 20.0    -- Cast is 10s; a teleport not observed by 20s means it failed
local HEARTH_JUMP_SQ = 500.0 * 500.0 -- Position jump proving the teleport landed (squared yd)
local LOOT_VERIFY_TIMEOUT = 5.0 -- Item must appear in bags within this after the loot interaction

-- Nil-safe distance (returns infinity on bad input) — used to notice a chased target drifting.
local Geometry = (function()
    local ok, mod = pcall(require, "core/geometry")
    if ok and type(mod) == "table" and mod.distance and mod.distance_sq then return mod end
    return nil
end)()

--- Squared distance helper for the nearest-neighbor loops below (no sqrt on
--- the hot path). Falls back to a manual squared distance if Geometry failed
--- to load, keeping the same math.huge "unmeasurable" sentinel either way.
local function distance_sq(a, b)
    if Geometry then
        return Geometry.distance_sq(a, b)
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return dx * dx + dy * dy + dz * dz
end

--- Stable per-corpse identity, used both to dedupe kill counting and to bound
--- loot attempts. Prefers the GUID; falls back to rounded position + npc id so a
--- client without get_guid still distinguishes two corpses lying side by side.
local function corpse_key(unit)
    if not unit then
        return nil
    end
    if type(unit.get_guid) == "function" then
        local ok, guid = pcall(unit.get_guid, unit)
        if ok and guid ~= nil and guid ~= "" then
            return "guid:" .. tostring(guid)
        end
    end
    local npc_id = "?"
    if type(unit.get_npc_id) == "function" then
        local ok, id = pcall(unit.get_npc_id, unit)
        if ok then npc_id = tostring(id) end
    end
    if type(unit.get_position) == "function" then
        local ok, pos = pcall(unit.get_position, unit)
        if ok and pos and pos.x then
            return string.format("pos:%s:%.1f:%.1f:%.1f", npc_id, pos.x, pos.y, pos.z)
        end
    end
    return nil
end

local RuntimeAction = {}

-- ============================================================================
-- Unit Helper: Optimized object retrieval with Sylvannas API compliance
-- Replaces fabricated core.object_manager.GetNearest* APIs
-- ============================================================================
local UnitHelper = {}

-- ============================================================================
-- F4: per-execute_kill object snapshot
-- ============================================================================
-- The docs flag get_all_objects as the most expensive call available (object-manager.md:45).
-- A single Kill tick used to trigger 3+ full scans: the sticky-target re-check, the
-- fresh-target reacquire, and any nested UnitHelper lookups they touch. Scoped tightly to ONE
-- execute_kill invocation (not a wall-clock/game-tick key) so every other caller — every other
-- action type, and Kill's own nested calls made OUTSIDE the wrapper below — is completely
-- unaffected and still gets a fresh scan every time, matching prior behavior exactly.
UnitHelper._snapshot_active = false
UnitHelper._snapshot_objects = nil
UnitHelper._snapshot_scan_count = 0 -- exposed for offline testing only (F4 regression guard)

--- Begin a snapshot window: the next call(s) to _get_all_objects() while active share one scan.
function UnitHelper._begin_snapshot()
    UnitHelper._snapshot_active = true
    UnitHelper._snapshot_objects = nil
end

--- End the snapshot window and drop the cached scan.
function UnitHelper._end_snapshot()
    UnitHelper._snapshot_active = false
    UnitHelper._snapshot_objects = nil
end

--- Get all objects from object manager (Sylvannas API)
--- @return table|nil Array of game_object items
function UnitHelper._get_all_objects()
    if UnitHelper._snapshot_active then
        if UnitHelper._snapshot_objects == nil then
            -- Lazily populate once per snapshot window; `false` marks "queried, nothing usable"
            -- so a missing/erroring API doesn't get re-queried on every lookup within the window.
            UnitHelper._snapshot_scan_count = UnitHelper._snapshot_scan_count + 1
            local objs = nil
            if core and core.object_manager and core.object_manager.get_all_objects then
                local ok, result = pcall(core.object_manager.get_all_objects, core.object_manager)
                if ok and type(result) == "table" then
                    objs = result
                end
            end
            UnitHelper._snapshot_objects = objs or false
        end
        if UnitHelper._snapshot_objects == false then
            return nil
        end
        return UnitHelper._snapshot_objects
    end

    UnitHelper._snapshot_scan_count = UnitHelper._snapshot_scan_count + 1
    if core and core.object_manager and core.object_manager.get_all_objects then
        local ok, objs = pcall(core.object_manager.get_all_objects, core.object_manager)
        if ok and type(objs) == "table" then
            return objs
        end
    end
    return nil
end

--- Find nearest creature by entry ID(s)
--- Uses core.object_manager.get_all_objects() + filtering (per Sylvannas API docs)
--- @param entries table|number List of NPC entries or single entry
--- @param filter function|nil Optional predicate(obj) -> boolean; false rejects the candidate
--- @return game_object|nil Nearest matching creature
function UnitHelper.get_nearest_creature(entries, filter)
    if type(entries) ~= "table" then
        entries = { entries }
    end

    -- Build a set for O(1) lookup
    local entry_set = {}
    for _, e in ipairs(entries) do
        entry_set[tostring(e)] = true
    end

    local all_objects = UnitHelper._get_all_objects()
    if not all_objects then
        return nil
    end

    -- Find nearest valid creature by entry
    -- F5: Geometry.distance_sq's math.huge sentinel (was a private 999999999,
    -- behind a dead `math.hfov and ... or ...` check — math.hfov never exists).
    local nearest_obj = nil
    local nearest_dist_sq = math.huge

    local player_pos
    if core and core.object_manager and core.object_manager.get_local_player then
        local ok, player = pcall(core.object_manager.get_local_player, core.object_manager)
        if ok and player and player.get_position then
            local ok2, pos = pcall(player.get_position, player)
            if ok2 and pos then
                player_pos = pos
            end
        end
    end

    for _, obj in ipairs(all_objects) do
        -- Check if object is valid and is a unit
        if obj and obj.is_valid and obj:is_valid() and obj.is_unit and obj:is_unit() then
            local npc_id
            if obj.get_npc_id then
                local ok, id = pcall(obj.get_npc_id, obj)
                npc_id = ok and tostring(id) or nil
            end

            local accepted = npc_id and entry_set[npc_id]
            if accepted and filter then
                local ok_filter, keep = pcall(filter, obj)
                accepted = ok_filter and keep ~= false
            end

            if accepted then
                -- Check distance if we have player position
                local dist_sq = nearest_dist_sq
                if player_pos and obj.get_position then
                    local ok, pos = pcall(obj.get_position, obj)
                    if ok and pos then
                        dist_sq = distance_sq(player_pos, pos)
                    end
                end

                if dist_sq < nearest_dist_sq then
                    nearest_dist_sq = dist_sq
                    nearest_obj = obj
                end
            end
        end
    end

    return nearest_obj
end

--- Find nearest game object by entry ID(s)
--- Uses core.object_manager.get_all_objects() + filtering
--- @param entries table|number List of object entries or single entry
--- @return game_object|nil Nearest matching game object
function UnitHelper.get_nearest_game_object(entries)
    if type(entries) ~= "table" then
        entries = { entries }
    end

    local entry_set = {}
    for _, e in ipairs(entries) do
        entry_set[tostring(e)] = true
    end

    local all_objects = UnitHelper._get_all_objects()
    if not all_objects then
        return nil
    end

    -- F5: math.huge sentinel (was a private 999999999), matching Geometry's convention.
    local nearest_obj = nil
    local nearest_dist_sq = math.huge

    local player_pos
    if core and core.object_manager and core.object_manager.get_local_player then
        local ok, player = pcall(core.object_manager.get_local_player, core.object_manager)
        if ok and player and player.get_position then
            local ok2, pos = pcall(player.get_position, player)
            if ok2 and pos then
                player_pos = pos
            end
        end
    end

    for _, obj in ipairs(all_objects) do
        -- Check if object is valid and is a game object (not a unit)
        if obj and obj.is_valid and obj:is_valid() and obj.is_game_object and obj:is_game_object() then
            -- Game objects have get_entry_id or get_item_id for identification
            local obj_id
            if obj.get_entry_id then
                local ok, id = pcall(obj.get_entry_id, obj)
                obj_id = ok and tostring(id) or nil
            elseif obj.get_item_id then
                local ok, id = pcall(obj.get_item_id, obj)
                obj_id = ok and tostring(id) or nil
            end

            if obj_id and entry_set[obj_id] then
                local dist_sq = nearest_dist_sq
                if player_pos and obj.get_position then
                    local ok, pos = pcall(obj.get_position, obj)
                    if ok and pos then
                        dist_sq = distance_sq(player_pos, pos)
                    end
                end

                if dist_sq < nearest_dist_sq then
                    nearest_dist_sq = dist_sq
                    nearest_obj = obj
                end
            end
        end
    end

    return nearest_obj
end

--- Get the local player game object
--- @return game_object|nil
function UnitHelper.get_local_player()
    if core and core.object_manager and core.object_manager.get_local_player then
        local ok, player = pcall(core.object_manager.get_local_player, core.object_manager)
        if ok then
            return player
        end
    end
    return nil
end

-- Expose as module-level for backward compatibility
RuntimeAction.UnitHelper = UnitHelper

-- Execute a single action
function RuntimeAction.execute(action, ctx)
    local payload = action.payload
    local action_type = action.type

    if action_type == "AcceptQuest" then
        return RuntimeAction.execute_accept_quest(payload, ctx)
    elseif action_type == "TurnInQuest" then
        return RuntimeAction.execute_turnin_quest(payload, ctx)
    elseif action_type == "Travel" then
        return RuntimeAction.execute_travel(payload, ctx)
    elseif action_type == "Kill" then
        return RuntimeAction.execute_kill(payload, ctx)
    elseif action_type == "Vendor" then
        return RuntimeAction.execute_vendor(payload, ctx)
    elseif action_type == "Train" then
        return RuntimeAction.execute_train(payload, ctx)
    elseif action_type == "Flight" then
        return RuntimeAction.execute_flight(payload, ctx)
    elseif action_type == "Hearth" then
        return RuntimeAction.execute_hearth(payload, ctx)
    elseif action_type == "Wait" then
        return RuntimeAction.execute_wait(payload, ctx)
    elseif action_type == "UseItem" then
        return RuntimeAction.execute_use_item(payload, ctx)
    elseif action_type == "Comment" then
        return "success" -- Comments are no-ops
    elseif action_type == "Condition" then
        return RuntimeAction.execute_condition(payload, ctx)
    elseif action_type == "SetVariable" then
        return RuntimeAction.execute_set_variable(payload, ctx)
    elseif action_type == "Repair" then
        return RuntimeAction.execute_repair(payload, ctx)
    elseif action_type == "LearnFlightPath" then
        return RuntimeAction.execute_learn_flight_path(payload, ctx)
    elseif action_type == "Mailbox" then
        return RuntimeAction.execute_mailbox(payload, ctx)
    elseif action_type == "Bank" then
        return RuntimeAction.execute_bank(payload, ctx)
    elseif action_type == "InteractNpc" then
        return RuntimeAction.execute_interact_npc(payload, ctx)
    elseif action_type == "Loot" then
        return RuntimeAction.execute_loot(payload, ctx)
    elseif action_type == "Grind" then
        return RuntimeAction.execute_grind(payload, ctx)
    elseif action_type == "Escort" then
        return RuntimeAction.execute_escort(payload, ctx)
    elseif action_type == "Patrol" then
        return RuntimeAction.execute_patrol(payload, ctx)
    elseif action_type == "AbandonQuest" then
        return RuntimeAction.execute_abandon_quest(payload, ctx)
    else
        return "failed" -- Unknown action type
    end
end

--- Open the quest/gossip dialog on an NPC, if it is not already open.
---
--- Nothing previously interacted with the NPC at all: `accept_quest()` was called with no dialog
--- open and no target, so it did nothing while the action still reported success. Returns true once
--- the gossip frame is shown.
local function ensure_gossip_open(npc_entry)
    if not (core and core.quests) then return false end
    if core.quests.is_gossip_frame_shown and core.quests.is_gossip_frame_shown() then
        return true
    end
    local npc = UnitHelper.get_nearest_creature({ npc_entry })
    if not npc then return false end
    if core.input and core.input.interact_with_object then
        pcall(core.input.interact_with_object, npc)
    end
    -- The frame opens asynchronously; the caller retries on a later tick.
    return core.quests.is_gossip_frame_shown and core.quests.is_gossip_frame_shown() or false
end

--- Is the quest currently in the player's log?
local function is_on_quest(quest_id)
    if not (core and core.quests and core.quests.is_on_quest) then return false end
    local ok, on = pcall(core.quests.is_on_quest, quest_id)
    return ok and on == true
end

--- Has the quest already been turned in?
local function is_quest_rewarded(quest_id)
    if not (core and core.quests and core.quests.is_quest_flagged_completed) then return false end
    local ok, done = pcall(core.quests.is_quest_flagged_completed, quest_id)
    return ok and done == true
end

-- Gossip is asynchronous: interact → the frame opens a few frames later → the
-- accept/turn-in round-trips to the server. Raw "retry" returns burned the whole 5-attempt
-- budget inside ~5 frames (live 2026-07-23: action_retry x5 in under a second, quest 7
-- never turned in, and the route moved on without it). Pace to one REAL attempt per
-- interval; between attempts hold with "waiting", which never consumes the retry budget —
-- so the 5 retries now span ~10s of genuine attempts instead of five frames.
local GOSSIP_RETRY_INTERVAL = 2.0

--- True when this paced action may attempt now (stamps the next slot); false while holding.
local function gossip_attempt_due(ctx, pace_key)
    local P = ctx.persist or ctx
    P._gossip_next_try = P._gossip_next_try or {}
    local now = (core and core.time and core.time()) or 0
    local next_try = P._gossip_next_try[pace_key]
    if next_try and now < next_try then
        return false
    end
    P._gossip_next_try[pace_key] = now + GOSSIP_RETRY_INTERVAL
    return true
end

local function gossip_pace_clear(ctx, pace_key)
    local P = ctx.persist or ctx
    if P._gossip_next_try then P._gossip_next_try[pace_key] = nil end
end

--- Surface an action-level observation on the shared questing log channel. Actions have no
--- handle on RuntimeProfile:_log_event; questing:log is the same stream its entries ride.
local function publish_action_note(ctx, event, data)
    if ctx and ctx.event_bus and ctx.event_bus.publish then
        local entry = { event = event }
        if data then
            for k, v in pairs(data) do entry[k] = v end
        end
        pcall(ctx.event_bus.publish, ctx.event_bus, "questing:log", entry)
    end
end

function RuntimeAction.execute_accept_quest(payload, ctx)
    local quest_id = payload.quest_id
    local npc_entry = payload.npc_entry
    local pace_key = "accept:" .. tostring(quest_id)

    -- Already done? Nothing to do — treat as satisfied rather than retrying forever.
    -- Also the settle path: a paced attempt from a previous tick lands here as success.
    if is_on_quest(quest_id) or is_quest_rewarded(quest_id) then
        gossip_pace_clear(ctx, pace_key)
        return "success"
    end

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end
    if not gossip_attempt_due(ctx, pace_key) then
        return "waiting" -- previous attempt still settling; re-verified above every tick
    end
    if not ensure_gossip_open(npc_entry) then
        return "retry" -- dialog not up yet; interact was issued, attempt again next interval
    end

    -- Pick THIS quest out of the NPC's offer list, then accept it.
    if core.quests.select_gossip_available_quest then
        pcall(core.quests.select_gossip_available_quest, quest_id)
    end
    if core.quests.accept_quest then
        pcall(core.quests.accept_quest)
    end

    -- Verify against the quest log. Reporting success without this is how the runner claimed to
    -- accept quests while the log stayed empty.
    if is_on_quest(quest_id) then
        gossip_pace_clear(ctx, pace_key)
        return "success"
    end
    return "retry"
end

function RuntimeAction.execute_turnin_quest(payload, ctx)
    local quest_id = payload.quest_id
    local npc_entry = payload.npc_entry

    local pace_key = "turnin:" .. tostring(quest_id)

    -- Already handed in — satisfied, not a failure to retry.
    -- Also the settle path: a paced attempt from a previous tick lands here as success.
    if is_quest_rewarded(quest_id) then
        gossip_pace_clear(ctx, pace_key)
        return "success"
    end
    -- Not in the log and not rewarded: there is nothing to turn in here.
    if not is_on_quest(quest_id) then
        gossip_pace_clear(ctx, pace_key)
        return "skipped"
    end

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end
    if not gossip_attempt_due(ctx, pace_key) then
        return "waiting" -- previous attempt still settling; re-verified above every tick
    end
    if not ensure_gossip_open(npc_entry) then
        return "retry"
    end

    if core.quests.select_gossip_active_quest then
        pcall(core.quests.select_gossip_active_quest, quest_id)
    end
    if core.quests.complete_quest then
        pcall(core.quests.complete_quest)
    end
    -- ALWAYS claim: complete_quest lands on the reward frame, and the turn-in is not
    -- final until get_quest_reward confirms it — even for quests with a single fixed
    -- reward. Only claiming when the guide specified a choice left choice-reward quests
    -- stalled on the frame through the whole retry budget (live: quest 33 burned all 5
    -- attempts and only completed on the trailing edge). Slot 1 is the default when the
    -- guide does not care.
    if core.quests.get_quest_reward then
        local choice = payload.choose_reward or payload.reward_choice or 1
        pcall(core.quests.get_quest_reward, choice)
    end

    -- Verify: the quest must have left the log (or be flagged complete).
    if is_quest_rewarded(quest_id) or not is_on_quest(quest_id) then
        gossip_pace_clear(ctx, pace_key)
        return "success"
    end
    return "retry"
end

--- Resolve a ground Z for a target that has none.
---
--- RestedXP guides carry only zone x/y, so the compiler emits `world_z = 0` — a point buried in
--- the terrain rather than standing on it. Left alone, a target 3 yards away in x/y reads as ~83
--- yards distant, never satisfies the arrival tolerance, and the navmesh query looks for a polygon
--- underground. Ask the client for the surface height; if that terrain is not loaded (the API
--- returns 0 for distant chunks) fall back to the player's own Z, which assumes same-ground and is
--- far closer than 0.
function RuntimeAction.resolve_ground_z(x, y, z)
    local player_z = nil
    local player = UnitHelper.get_local_player()
    if player and player.get_position then
        local ok_p, pos = pcall(player.get_position, player)
        if ok_p and type(pos) == "table" and type(pos.z) == "number" then
            player_z = pos.z
        end
    end

    -- A recorded Z is trusted only when PLAUSIBLE. Guides never carry heights, and one
    -- importer bug baked a .goto reach RADIUS (45) into world_z — waypoints ~35yd inside
    -- the terrain at Echo Ridge, no navmesh polygon, travel wedged in awaiting_path
    -- forever (live-caught). More than 30yd of vertical disagreement with the player on
    -- a single travel leg means the number is not a height; re-resolve it.
    if type(z) == "number" and z ~= 0 then
        if player_z == nil or math.abs(z - player_z) <= 30 then
            return z
        end
    end
    if core and core.get_height_for_position then
        local ok, h = pcall(core.get_height_for_position, { x = x, y = y, z = 0 })
        if ok and type(h) == "number" and h ~= 0 then
            return h
        end
    end
    if player_z ~= nil then
        return player_z
    end
    return z or 0
end

-- A12: is_at_destination_2d used to live here. It was carefully documented but had no caller —
-- its horizontal-arrival logic was inlined directly into execute_travel (below) instead. Verified
-- no requirer anywhere in sentinel/ before removal.

function RuntimeAction.execute_travel(payload, ctx)
    local dest   = payload.destination    -- string zone name (e.g. "Elwynn Forest")
    local tol    = payload.tolerance or 5.0
    local target = payload.position       -- {x, y, z} from compiler (preferred)

    -- Resolve target position: prefer explicit coords, fall back to zone waypoint
    local target_pos = nil
    if type(target) == "table" then
        if target.x then
            -- Legacy format: {x, y, z}
            target_pos = { x = target.x, y = target.y, z = target.z }
        elseif target.world_x then
            -- New format from compiler: {world_x, world_y, world_z, map}. Guides supply no Z, so
            -- world_z is 0 and must be lifted onto the terrain before any distance check.
            target_pos = {
                x = target.world_x,
                y = target.world_y,
                z = RuntimeAction.resolve_ground_z(target.world_x, target.world_y, target.world_z),
            }
        end
    elseif type(dest) == "string" then
        target_pos = ctx:get_zone_waypoint(dest)
    end

    if not target_pos then
        return "blocked" -- No known position to navigate to
    end

    -- Already there?
    if ctx:is_at_destination(target_pos, tol) then
        return "success"
    end

    -- Arrived HORIZONTALLY, with a bad inferred Z.
    --
    -- Guides carry no Z, so world_z is inferred and can be many yards off: measured live at player
    -- (-8825.6,-166.1,79.9) against destination Z 88.3 — 0.9 yards away on the ground, nav
    -- reporting "arrived" with 0 waypoints left, yet the 3D check stayed false. Because nav goes
    -- INACTIVE on arrival, the poll branch below was skipped entirely and this fell through to
    -- re-issuing move_to, producing an endless arrive → "navigated, retry" → re-navigate loop that
    -- never advanced to the Kill behind it.
    --
    -- Accept it only when the navigator itself reports arrival: that is the navmesh confirming it
    -- reached the requested point, so the sole disagreement is the height we invented. Requiring
    -- nav's own "arrived" keeps a target directly above or below from being mistaken for reached.
    if ctx.nav and ctx.nav.get_state and not ctx.nav:is_active() then
        local nav_state = ctx.nav:get_state()
        if nav_state == "arrived" then
            local player = UnitHelper.get_local_player()
            local ok_p, ppos = false, nil
            if player and player.get_position then ok_p, ppos = pcall(player.get_position, player) end
            if ok_p and type(ppos) == "table" then
                local dx = (tonumber(ppos.x) or 0) - (tonumber(target_pos.x) or 0)
                local dy = (tonumber(ppos.y) or 0) - (tonumber(target_pos.y) or 0)
                if math.sqrt(dx * dx + dy * dy) <= (tonumber(tol) or 5.0) then
                    ctx.nav:stop("arrived")
                    return "success"
                end
            end
        end
    end

    -- Already navigating? Poll for arrival.
    if ctx.nav and ctx.nav:is_active() then
        local state, progress = ctx.nav:poll()
        if state == "arrived" or state == "idle" then
            -- Arrived: verify position
            -- Trust the navigator's own arrival. Re-verifying with a 3D distance check fails
            -- whenever the inferred Z is wrong: measured live at (-8835.6,-51.9,88.3) against a
            -- destination Z of 79.9 — 0.9 yards away horizontally, nav reporting "arrived" with 0
            -- waypoints left, yet an 8.4-yard vertical error kept the check false and the travel
            -- looped "navigated, retry" forever. The navmesh owns elevation; if it says it arrived,
            -- it arrived.
            if state == "arrived" then
                ctx.nav:stop("arrived")
                return "success"
            end
            if ctx:is_at_destination(target_pos, tol) then
                ctx.nav:stop("arrived")
                return "success"
            end
            -- Not close enough; allow re-navigation below
        elseif state == "requesting_path" or state == "moving" then
            return "blocked" -- Still navigating
        elseif state == "stuck" then
            return "retry" -- Pathfinding issue; outer loop can try recovery
        else
            -- failed / unknown → fall through to retry
        end
    end

    -- Start navigation via NavAdapter
    if ctx.nav then
        local ok, err = ctx.nav:move_to(target_pos, { tolerance = tol })
        if ok then
            return "blocked" -- Will be polled on subsequent tick
        end
        return "retry" -- Dispatch failed; outer loop can retry
    end

    -- No NavAdapter available: return blocked (movement requires proper navigation)
    return "blocked" -- Navigation unavailable
end

--- Distance from the local player to a unit, or nil if it cannot be measured.
--- Declared after UnitHelper so it captures the local, not a nil global.
local function distance_to_unit(unit)
    if not unit or type(unit.get_position) ~= "function" or not Geometry then
        return nil
    end
    local ok_t, tpos = pcall(unit.get_position, unit)
    if not (ok_t and tpos) then
        return nil
    end
    local player = UnitHelper.get_local_player()
    if not player or type(player.get_position) ~= "function" then
        return nil
    end
    local ok_p, ppos = pcall(player.get_position, player)
    if not (ok_p and ppos) then
        return nil
    end
    return Geometry.distance(ppos, tpos)
end

--- F4: real implementation of Kill, wrapped below by RuntimeAction.execute_kill in an object
--- snapshot. Extracted to its own local function so the wrapper can guarantee the snapshot is
--- always closed (even on error) without touching every early `return` in the body.
local function _execute_kill_impl(payload, ctx)
    local entries = payload.creature_entries or {}
    local quantity = payload.quantity or 1
    -- A4: RuntimeKill carries loot/ignore_elites (SentinelQuesting/shared/src/runtime/action.rs
    -- :227-233); neither was read before. `loot` defaults true for back-compat with profiles
    -- compiled before this field existed.
    local should_loot = payload.loot
    if should_loot == nil then should_loot = true end
    local ignore_elites = payload.ignore_elites == true

    -- Branch trace. Inferring kill behaviour from state snapshots proved unreliable, so record the
    -- decision each tick and let the caller read it back. Cheap: one table write per execution.
    local P = ctx.persist or ctx
    P._kill_trace = { entries = #entries, quantity = quantity }
    -- Records WHICH branch ran, and returns the real status unchanged. The trace must never
    -- influence behaviour.
    local function trace(branch, status)
        P._kill_trace.branch = branch
        return status
    end

    -- Initialize kill tracking
    P.kill_counts = P.kill_counts or {}
    local key = table.concat(entries, ",")
    P.kill_counts[key] = P.kill_counts[key] or 0

    -- Already satisfied?
    if P.kill_counts[key] >= quantity then
        return trace("success_count", "success")
    end

    -- Find the nearest creature, SKIPPING corpses that are already looted and
    -- counted. Without this the loop wedges: a finished corpse two yards away
    -- stays "nearest" forever, so every tick returned next_target while a live
    -- wolf nine yards out was ignored -- and next_target used to return "blocked",
    -- which burned the retry budget until the Kill action was skipped entirely.
    P._counted_corpses = P._counted_corpses or {}
    P._loot_attempts = P._loot_attempts or {}
    local function is_unfinished(obj)
        local ok_dead, dead = pcall(obj.is_dead, obj)
        if not (ok_dead and dead == true) then
            return true -- alive: always a candidate
        end
        local id = corpse_key(obj)
        if not id then
            return true
        end
        -- A corpse is still interesting while it has loot attempts left or has
        -- not been tallied yet.
        return (P._loot_attempts[id] or 0) < LOOT_ATTEMPTS or not P._counted_corpses[id]
    end

    -- A4(ignore_elites): with ignore_elites=true, an elite must never be picked as a fresh
    -- target — the old code committed to whichever creature was nearest regardless, chased,
    -- engaged, and typically died and re-committed to the same elite on respawn.
    local function is_elite(obj)
        if not obj or type(obj.is_elite) ~= "function" then
            return false
        end
        local ok, elite = pcall(obj.is_elite, obj)
        return ok and elite == true
    end
    local function is_acquirable(obj)
        if not is_unfinished(obj) then return false end
        if ignore_elites and is_elite(obj) then return false end
        return true
    end

    -- STICKY TARGET.
    --
    -- Re-picking "nearest" every tick makes the bot thrash: two wolves at similar
    -- range keep swapping places as the player moves, so it targets one, issues
    -- move_to toward the other, and oscillates between them without ever arriving.
    -- Commit to a target and keep it until it is finished, gone, or has run beyond
    -- ABANDON_RANGE.
    local target = nil
    if P._target_key then
        target = UnitHelper.get_nearest_creature(entries, function(obj)
            return corpse_key(obj) == P._target_key
        end)
        if target then
            local dist_to_sticky = distance_to_unit(target)
            local ok_d, is_dead_now = pcall(target.is_dead, target)
            local finished = ok_d and is_dead_now == true
                and (P._loot_attempts[P._target_key] or 0) >= LOOT_ATTEMPTS
                and P._counted_corpses[P._target_key] == true
            if finished or (dist_to_sticky and dist_to_sticky > ABANDON_RANGE) then
                target = nil
            end
        end
        if not target then
            P._target_key = nil
            P._chase_dest = nil -- drop the stale destination with the target
        end
    end

    if not target then
        target = UnitHelper.get_nearest_creature(entries, is_acquirable)
        local new_key = target and corpse_key(target) or nil
        if new_key ~= P._target_key then
            P._chase_dest = nil -- new target, so the old chase destination is stale
        end
        P._target_key = new_key
    end

    if target and target.get_position then
        -- Check if target is dead — loot the corpse, then count it toward quantity.
        if target:is_dead() then
            local corpse_id = corpse_key(target)

            -- Count each corpse ONCE. This used to increment on every tick the same
            -- corpse was still the nearest creature, inflating kill_counts far past
            -- the number of mobs actually killed and satisfying `quantity` early.
            P._counted_corpses = P._counted_corpses or {}

            -- Loot before counting. Kill objectives are frequently item drops
            -- ("Tough Wolf Meat: 0/8"), and walking off without looting can never
            -- satisfy them. Bounded by LOOT_ATTEMPTS so an unlootable corpse
            -- (already skinned, no drops, tap-denied) cannot wedge the run.
            P._loot_attempts = P._loot_attempts or {}
            local attempts = P._loot_attempts[corpse_id] or 0
            -- A4(loot): payload.loot=false means this objective is not item-gated — skip
            -- looting entirely and count the corpse immediately instead of spending
            -- LOOT_ATTEMPTS ticks approaching/looting something the objective never needed.
            if should_loot and corpse_id and attempts < LOOT_ATTEMPTS then
                local dist_to_corpse = nil
                local ok_cpos, cpos = pcall(target.get_position, target)
                local looter = UnitHelper.get_local_player()
                if ok_cpos and cpos and looter and looter.get_position then
                    local ok_lp, lpos = pcall(looter.get_position, looter)
                    if ok_lp and lpos and Geometry and Geometry.distance then
                        dist_to_corpse = Geometry.distance(lpos, cpos)
                    end
                end

                if dist_to_corpse and dist_to_corpse > CORPSE_LOOT_RANGE then
                    -- Walk onto the corpse before looting.
                    if ctx.nav and cpos then
                        local last = P._chase_dest
                        local drifted = (not last)
                            or (Geometry and Geometry.distance
                                and Geometry.distance(last, cpos) > 2.0)
                            or false
                        if drifted or not ctx.nav:is_active() then
                            ctx.nav:move_to(cpos, { tolerance = 2.0 })
                            P._chase_dest = { x = cpos.x, y = cpos.y, z = cpos.z }
                        end
                    end
                    return trace("looting_approach", "waiting")
                end

                P._loot_attempts[corpse_id] = attempts + 1
                if core and core.input and type(core.input.loot_object) == "function" then
                    pcall(core.input.loot_object, target)
                end
                -- Give the loot window a tick to open and auto-loot to run.
                return trace("looting", "waiting")
            end

            if corpse_id and P._counted_corpses[corpse_id] then
                -- Already tallied; the filter above will stop offering this corpse.
                return trace("next_target", "waiting")
            end
            if corpse_id then
                P._counted_corpses[corpse_id] = true
            end

            P.kill_counts[key] = P.kill_counts[key] + 1
            if P.kill_counts[key] >= quantity then
                return trace("success_killed", "success")
            end
            -- "waiting", NOT "blocked": there are 39 more wolves to kill and this
            -- action must keep running. "blocked" burns the retry budget and gets
            -- the whole Kill skipped after a handful of corpses.
            return trace("next_target", "waiting")
        end

        -- Range is measured against the TARGET WE FOUND, not entries[1].
        --
        -- This previously asked `is_at_npc(entries[1], 30)`. With a multi-entry kill such as
        -- [299, 69, 704, 705], the nearest creature can be a Timber Wolf (69) while no Young Wolf
        -- (299) is within 30 yards — so the check failed and the bot navigated forever while
        -- standing next to a perfectly valid target.
        -- Pursue until the target is inside the range the COMBAT module will
        -- actually act at, not merely "nearby".
        --
        -- This used to be a flat 30 yards, which opened a dead band: the Kill
        -- action called 18 yd "in range" and stopped chasing, while combat's own
        -- guard skips the rotation beyond `combat_range + 10` (15 yd for a melee
        -- Paladin). Between 15 and 30 yards nobody moved and nobody swung — the
        -- bot stood and watched wolves wander off. Measured live 2026-07-23:
        -- target drifted 11.6 -> 14.6 -> 18.1 yd with the player stationary.
        --
        -- combat_range is published by the class profile (5 melee, ~28 ranged),
        -- so this closes the gap for casters without dragging them into melee.
        -- 4.5 matches the fallback in SentinelCombat:update and ChaseController,
        -- so all three agree when no class profile has published a range yet.
        local combat_range = 4.5
        if ctx.blackboard and ctx.blackboard.get then
            combat_range = tonumber(ctx.blackboard:get("module.combat.combat_range")) or 4.5
        end
        -- Close to well INSIDE the class's range, not merely to its edge. Stopping
        -- at the boundary leaves a melee character hovering ~5-7 yd out, where a
        -- wandering mob steps out of swing range constantly and the corpse is out
        -- of loot range. `combat_range - 2` puts a Paladin at ~3 yd and still lets
        -- a 28 yd caster fire from ~26 without being dragged into melee.
        local engage_range = math.max(2.5, combat_range - 2.0)

        local in_range = false
        local dist = nil
        local ok_pos, tpos = pcall(target.get_position, target)
        local player = UnitHelper.get_local_player()
        if ok_pos and tpos and player and player.get_position then
            local ok_p, ppos = pcall(player.get_position, player)
            if ok_p and ppos and Geometry and Geometry.distance then
                dist = Geometry.distance(ppos, tpos)
                in_range = dist <= engage_range
            end
        end
        if dist == nil then
            -- Could not measure; fall back to the old per-entry proximity check.
            in_range = ctx:is_at_npc(entries[1], engage_range)
        end
        P._kill_trace.dist = dist

        if not in_range then
            -- Chase: mobs wander, so the destination must track the target rather than being
            -- captured once. The old guard only issued move_to when nav was IDLE, which locked
            -- onto a stale position — the bot walked to where the mob used to be and stopped.
            local ok_pos, npc_pos = pcall(target.get_position, target)
            if ok_pos and npc_pos then
                local last = P._chase_dest
                -- Re-issue on 2 yd of drift, not 3, and arrive within 2 yd, not 5.
                -- A 5 yd tolerance is wider than a melee engage range, so nav
                -- reported "arrived" while still out of swing range and the chase
                -- never closed the last few yards on a wandering mob.
                local drifted = (not last)
                    or (Geometry and Geometry.distance
                        and Geometry.distance(last, npc_pos) > 2.0)
                    or false
                if ctx.nav and (drifted or not ctx.nav:is_active()) then
                    ctx.nav:move_to(npc_pos, { tolerance = 2.0 })
                    P._chase_dest = { x = npc_pos.x, y = npc_pos.y, z = npc_pos.z }
                end
            end
            -- "waiting", NOT "blocked". Blocked hands control to the profile's NAVIGATING state,
            -- where this action stops running — so the chase above could never re-issue and the bot
            -- walked to a stale position and stopped. Waiting keeps the Kill action in control of
            -- its own pursuit every tick, still bounded by MAX_CONDITION_WAIT.
            return trace("chasing", "waiting")
        end
        P._chase_dest = nil
        -- Inside engage range: hand movement back. Leaving the chase nav running
        -- makes it fight the fight — the character keeps sliding toward a stale
        -- destination while the rotation is trying to swing.
        if ctx.nav and ctx.nav.is_active and ctx.nav:is_active() then
            pcall(function() ctx.nav:stop() end)
        end

        -- In range. Nothing here previously did anything at all — it returned "blocked" and
        -- assumed "the combat loop" would notice, but the combat module's world auto-engage is off
        -- by default, so the bot walked up to the mob and stood there. Target it and REQUEST
        -- engagement explicitly on the shared event bus.
        if core and core.input and core.input.set_target then
            pcall(core.input.set_target, target)
        end
        -- B3: publish engage_requested only on a TRANSITION (a new sticky target), not every
        -- tick while in range. Re-requesting every tick fed combat's `engage()`, which
        -- unconditionally re-set `leash_center` to the player's current position each time —
        -- leash_dist stayed ~0 and disengage("leash_exceeded") was unreachable for the entire
        -- questing path. Gating on P._target_key makes engage_requested fire once per commit.
        if ctx.event_bus and ctx.event_bus.publish and P._target_key ~= P._last_engage_key then
            pcall(ctx.event_bus.publish, ctx.event_bus, "combat:engage_requested", {
                target = target,
                source = "questing",
                leash_radius = 40.0,
            })
            P._last_engage_key = P._target_key
        end
        -- "waiting", NOT "blocked": blocked drives the profile into its NAVIGATING state, which
        -- then polls the nav adapter forever while the kill action never runs again. "waiting"
        -- holds this action and re-polls each tick without burning the retry budget, which is what
        -- a fight needs — and it is still bounded by MAX_CONDITION_WAIT so a hopeless kill cannot
        -- wedge the run.
        return trace("engaging", "waiting")
    end

    -- No targets found.
    -- A9: RuntimeKill has no `destination` field (SentinelQuesting/shared/src/runtime/action.rs)
    -- — the compiler never emits one for Kill payloads, so the previous navigate-to-spawn-area
    -- branch here was permanently dead code (payload.destination always nil). Removed rather
    -- than left as misleading unreachable navigation logic.
    return "blocked" -- No targets nearby or no API
end

--- F4: public entry point. Wraps _execute_kill_impl in an object snapshot window so its
--- multiple UnitHelper lookups (sticky-target re-check, fresh reacquire) share ONE
--- get_all_objects() scan instead of one each. The snapshot is always closed, even if the
--- implementation errors, so a thrown error can never leave a stale snapshot active for a
--- later, unrelated action.
function RuntimeAction.execute_kill(payload, ctx)
    UnitHelper._begin_snapshot()
    local ok, a, b = pcall(_execute_kill_impl, payload, ctx)
    UnitHelper._end_snapshot()
    if not ok then
        error(a, 0)
    end
    return a, b
end

function RuntimeAction.execute_vendor(payload, ctx)
    local npc_entry = payload.npc_entry
    local sell_grey = payload.sell_grey
    local repair = payload.repair

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    -- Interact with NPC first
    if core and core.input and core.input.interact_with_object then
        local npc = UnitHelper.get_nearest_creature({ npc_entry })
        if npc then
            core.input.interact_with_object(npc)
        end
    end

    local attempted = false

    -- Sell greys. VERIFIED LIVE 2026-07-23: the SDK has NO bulk sell API (no sell_greys,
    -- no sell_item) — selling is use_container_item(bag, slot) while the merchant window
    -- is open, exactly like a player right-clicking bag items. Grey detection needs item
    -- quality, which no live API exposes either; it comes from the QueryServer item
    -- endpoint, cached per item id (compile-before-execute spirit: DB knowledge stays
    -- outside the client). Unknown quality (QueryServer down, item missing) fails SAFE:
    -- the item is never sold.
    if sell_grey and core and core.inventory and core.inventory.get_items_in_bag
        and core.input and core.input.use_container_item then
        local P = ctx.persist or ctx
        P._item_quality = P._item_quality or {}
        local any_pending = false
        for bag = 0, 4 do
            local ok_items, items = pcall(core.inventory.get_items_in_bag, bag)
            if ok_items and type(items) == "table" then
                for _, slot_info in ipairs(items) do
                    local obj = slot_info and slot_info.object
                    if obj and obj.get_item_id then
                        local ok_id, item_id = pcall(obj.get_item_id, obj)
                        if ok_id and item_id then
                            local quality = P._item_quality[item_id]
                            if quality == nil then
                                -- QueryClient is async request-and-cache: (value, pending).
                                -- A PENDING lookup must NOT be cached as unsellable — hold
                                -- the vendor stop and re-check once the response lands.
                                local info, pending
                                if ctx.query and ctx.query.get_item then
                                    local ok_q, res, pend = pcall(ctx.query.get_item, ctx.query, item_id)
                                    if ok_q then info, pending = res, pend end
                                end
                                if type(info) == "table" then
                                    quality = tonumber(info.quality) or -1
                                    P._item_quality[item_id] = quality
                                elseif pending then
                                    any_pending = true
                                else
                                    quality = -1
                                    P._item_quality[item_id] = quality
                                end
                            end
                            if quality == 0 and slot_info.slot_id ~= nil then
                                pcall(core.input.use_container_item, bag, slot_info.slot_id)
                            end
                        end
                    end
                end
            end
        end
        if any_pending then
            -- Qualities still resolving: try again next tick rather than walking away
            -- from the vendor having sold nothing.
            return "retry"
        end
        -- Verify the sale actually landed before declaring the stop done. interact_with_object
        -- opens the merchant window ASYNCHRONOUSLY, so the first tick's use_container_item calls
        -- are no-ops (no window yet) — and the old code still returned "success", clearing
        -- bags_full with the bags untouched (live-caught: detoured to the vendor, sold nothing,
        -- bags stayed 16/16 full). Re-scan for known-grey items; while any remain, retry so the
        -- sale lands once the window is open. Bounded so a genuinely unsellable grey can't wedge
        -- the detour (the maintenance timeout also bounds it).
        local greys_remaining = false
        for bag = 0, 4 do
            local ok_items, items = pcall(core.inventory.get_items_in_bag, bag)
            if ok_items and type(items) == "table" then
                for _, si in ipairs(items) do
                    local o = si and si.object
                    if o and o.get_item_id then
                        local ok_id, iid = pcall(o.get_item_id, o)
                        if ok_id and iid and P._item_quality[iid] == 0 then
                            greys_remaining = true
                        end
                    end
                end
            end
        end
        if greys_remaining then
            P._vendor_sell_ticks = (P._vendor_sell_ticks or 0) + 1
            if P._vendor_sell_ticks < 12 then
                return "retry"
            end
        end
        P._vendor_sell_ticks = nil
        attempted = true
    end

    -- Repair using core.input.repair_all_items
    if repair then
        if core and core.input and core.input.repair_all_items then
            core.input.repair_all_items(false) -- use_guild_bank = false
            attempted = true
        elseif core and core.inventory and core.inventory.repair_all_items then
            core.inventory.repair_all_items()
            attempted = true
        end
    end

    -- Buy items from vendor
    if payload.buy_items then
        if core and core.input and core.input.buy_item then
            for _, item in ipairs(payload.buy_items) do
                local index = item.index or item.slot
                local quantity = item.quantity or 1
                core.input.buy_item(index, quantity)
            end
            attempted = true
        end
    end

    if not attempted then
        return "retry"
    end
    return "success"
end

--- Total known spells via core.spell_book.get_spells (spell_id -> name map).
--- nil when the API is unavailable or unreadable — the caller must then not
--- pretend to verify.
local function spell_book_count()
    local sb = core and core.spell_book
    if not (sb and type(sb.get_spells) == "function") then return nil end
    local ok, spells = pcall(sb.get_spells)
    if not ok or type(spells) ~= "table" then return nil end
    local n = 0
    for _ in pairs(spells) do n = n + 1 end
    return n
end

local function train_interact(npc_entry)
    if core and core.input and core.input.interact_with_object then
        local npc = UnitHelper.get_nearest_creature({ npc_entry })
        if npc then
            core.input.interact_with_object(npc)
        end
    end
end

function RuntimeAction.execute_train(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    local P = ctx.persist or ctx
    local count = spell_book_count()
    if count ~= nil then
        -- Verifiable path: success only on an observed spell-book change; otherwise the
        -- interaction retries within the executor's normal per-action budget.
        P._train_baseline = P._train_baseline or {}
        local key = tostring(npc_entry)
        local baseline = P._train_baseline[key]
        if baseline ~= nil and count > baseline then
            P._train_baseline[key] = nil
            gossip_pace_clear(ctx, "train:" .. key)
            return "success"
        end
        if baseline == nil then
            P._train_baseline[key] = count
        end
        -- The trainer window opens asynchronously; pace attempts on real time like the
        -- other gossip interactions instead of burning the retry budget in frames.
        if not gossip_attempt_due(ctx, "train:" .. key) then
            return "waiting"
        end
        train_interact(npc_entry)
        return "retry"
    end

    -- No verifiable signal: keep the historical success, but say so in the log once.
    train_interact(npc_entry)
    if not P._train_unverified_logged then
        P._train_unverified_logged = true
        publish_action_note(ctx, "train_unverified", { npc_entry = npc_entry })
    end
    return "success"
end

function RuntimeAction.execute_flight(payload, ctx)
    local npc_entry = payload.npc_entry
    local destination = payload.destination

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    -- Flight path taking requires interacting with flight master
    -- then using taxi frame - this is complex and may need UI interaction
    --
    -- VERIFY-IN-GAME: core.input.take_taxi is not a documented Sylvannas API
    -- (docs/SylvannasAPI/dev/api/input.md has no taxi/flight entry); if the injector does not
    -- expose it this guard stays false and the action correctly falls through to "retry" (A7a).
    -- A7b: RuntimeFlight.destination (action.rs:245) is a STRING flight-node name, not a table —
    -- `destination.index or destination.id or 1` indexed a string, which is a silent nil in Lua
    -- (no error), so dest_idx always fell through to the WRONG hardcoded node 1. There is no
    -- documented name->node lookup API, so only accept an already-numeric destination and fail
    -- loudly rather than guess a node.
    if core and core.input and core.input.take_taxi then
        local dest_idx = tonumber(destination)
        if not dest_idx then
            return "failed" -- Cannot resolve a flight-node name to a taxi index; do not guess
        end
        core.input.take_taxi(dest_idx)
        return "success"
    end
    return "retry"
end

--- Hearth is a 10s cast followed by a teleport: using the item is not arriving.
--- Verify by position — the teleport is a jump far beyond anything a cast-length
--- walk could cover. No jump within HEARTH_TIMEOUT means the cast failed
--- (interrupted, on cooldown, no stone): "retry" re-casts under the action budget.
function RuntimeAction.execute_hearth(payload, ctx)
    local P = ctx.persist or ctx
    local now = (core and core.time and core.time()) or 0

    local player = UnitHelper.get_local_player()
    local pos = nil
    if player and player.get_position then
        local ok, p = pcall(player.get_position, player)
        if ok and type(p) == "table" then
            pos = { x = p.x, y = p.y, z = p.z }
        end
    end

    local h = P._hearth
    if h then
        if pos and h.origin and distance_sq(pos, h.origin) > HEARTH_JUMP_SQ then
            P._hearth = nil
            return "success"
        end
        if now - h.started_at >= HEARTH_TIMEOUT then
            P._hearth = nil
            return "retry"
        end
        return "waiting"
    end

    if core and core.input and core.input.use_item then
        local hearthstone_id = 6948 -- Default Hearthstone ID
        core.input.use_item(hearthstone_id)
        P._hearth = { started_at = now, origin = pos }
        return "waiting"
    end
    return "retry"
end

function RuntimeAction.execute_wait(payload, ctx)
    local duration = payload.duration or 0
    -- "blocked" routed a plain timer into nav recovery: it burned the retry budget,
    -- counted spurious failures, and ignored the duration. "waiting" holds the action
    -- in place; the executor's per-action wait timeout still bounds a bogus duration.
    if not ctx.wait_start then
        ctx.wait_start = (core and core.time and core.time()) or 0
        return "waiting" -- Start waiting
    end

    if ((core and core.time and core.time()) or 0) - ctx.wait_start >= duration then
        ctx.wait_start = nil
        return "success"
    end
    return "waiting" -- Still waiting
end

function RuntimeAction.execute_use_item(payload, ctx)
    local item_id = payload.item
    if core and core.input and core.input.use_item then
        core.input.use_item(item_id)
        return "success"
    end
    return "blocked"
end

--- Evaluate a single RuntimeCondition against game state.
--- Returns true/false.
--- Each condition type maps to a handler in the lookup table.
function RuntimeAction.evaluate_condition(ctx, cond)
    -- Unit variant (AlwaysTrue, AlwaysFalse — serialised as bare string)
    if type(cond) == "string" then
        local handler = RuntimeAction._condition_handlers[cond]
        if handler then
            return handler(ctx, nil)
        end
        -- Unknown conditions fail open: the runtime should never silently block
        -- a questing action because it doesn't recognise a condition type that
        -- a newer compiler may have emitted.
        return true
    end

    -- Struct variant — { type = "VariantName", payload = <value> }
    if type(cond) == "table" and cond.type then
        local handler = RuntimeAction._condition_handlers[cond.type]
        if handler then
            return handler(ctx, cond.payload)
        end
        return true  -- Fail open — same reasoning as above
    end

    return true  -- Fail open — unrecognized condition format
end

--- Execute a Condition action (gate).
--- `payload.role` (PR5a, compiler-tagged) selects the gating semantics; absent role defaults
--- to "Completion" for back-compat with pre-PR5a profiles.
---   Completion (wait-until-true): met -> "success"; unmet -> "waiting" (hold this action and
---     re-poll — the caller, RuntimeProfile:_execute_running, must not advance on "waiting").
---   Applicability (best-effort gate): met -> "success"; unmet -> "skipped" (advance past it).
function RuntimeAction.execute_condition(payload, ctx)
    local cond = payload.condition
    local ok = RuntimeAction.evaluate_condition(ctx, cond)
    if ok then
        return "success"
    end

    local role = payload.role or "Completion"
    if role == "Applicability" then
        return "skipped"
    end
    return "waiting"
end

-- ============================================================================
-- Condition handler lookup table
-- Each handler receives (ctx, payload) and returns true/false.
-- ============================================================================
RuntimeAction._condition_handlers = {}

-- Always true — always passes
RuntimeAction._condition_handlers["AlwaysTrue"] = function(ctx, _)
    return true
end

--- Quest conditions ---
RuntimeAction._condition_handlers["QuestAccepted"] = function(ctx, quest_entry)
    return ctx:is_quest_active(quest_entry)
end

RuntimeAction._condition_handlers["QuestCompleted"] = function(ctx, quest_entry)
    return ctx:is_quest_completed(quest_entry)
end

RuntimeAction._condition_handlers["QuestRewarded"] = function(ctx, quest_entry)
    return ctx:is_quest_completed(quest_entry)
end

RuntimeAction._condition_handlers["ObjectiveComplete"] = function(ctx, payload)
    local quest_entry = payload[1]
    local objective_idx = payload[2]
    return ctx:is_objective_complete(quest_entry, objective_idx)
end

--- Level conditions ---
RuntimeAction._condition_handlers["LevelAtLeast"] = function(ctx, level)
    return ctx:get_player_level() >= level
end

RuntimeAction._condition_handlers["LevelBelow"] = function(ctx, level)
    return ctx:get_player_level() < level
end

--- Item conditions ---
RuntimeAction._condition_handlers["HasItem"] = function(ctx, item_entry)
    local count = ctx:get_item_count(item_entry)
    return count ~= nil and count > 0
end

RuntimeAction._condition_handlers["ItemCountAtLeast"] = function(ctx, payload)
    local item_entry = payload[1]
    local count = payload[2]
    return (ctx:get_item_count(item_entry) or 0) >= count
end

--- Gold condition ---
RuntimeAction._condition_handlers["GoldAtLeast"] = function(ctx, copper)
    return (ctx:get_money() or 0) >= copper
end

--- Profession condition ---
RuntimeAction._condition_handlers["ProfessionSkillAtLeast"] = function(ctx, payload)
    local skill_name = payload[1]
    local skill_level = payload[2]
    return (ctx:get_skill_level(skill_name) or 0) >= skill_level
end

--- Item cooldown ---
RuntimeAction._condition_handlers["ItemCooldownReady"] = function(ctx, item_entry)
    return ctx:is_item_ready(item_entry)
end

--- Reputation condition ---
RuntimeAction._condition_handlers["ReputationAtLeast"] = function(ctx, payload)
    local faction = payload[1]
    local standing = payload[2]
    return (ctx:get_reputation(faction) or -42000) >= standing
end

--- Player conditions ---
RuntimeAction._condition_handlers["RaceIs"] = function(ctx, race_name)
    return ctx:get_player_race() == race_name
end

RuntimeAction._condition_handlers["ClassIs"] = function(ctx, class_name)
    return ctx:get_player_class() == class_name
end

RuntimeAction._condition_handlers["FactionIs"] = function(ctx, faction_name)
    return ctx:get_player_faction() == faction_name
end

--- Logical operators ---
RuntimeAction._condition_handlers["Not"] = function(ctx, inner)
    return not RuntimeAction.evaluate_condition(ctx, inner)
end

RuntimeAction._condition_handlers["All"] = function(ctx, conditions)
    for _, subcond in ipairs(conditions) do
        if not RuntimeAction.evaluate_condition(ctx, subcond) then
            return false
        end
    end
    return true
end

RuntimeAction._condition_handlers["Any"] = function(ctx, conditions)
    for _, subcond in ipairs(conditions) do
        if RuntimeAction.evaluate_condition(ctx, subcond) then
            return true
        end
    end
    return false
end

function RuntimeAction.execute_set_variable(payload, ctx)
    ctx.variables = ctx.variables or {}
    ctx.variables[payload.name] = payload.value
    return "success"
end

function RuntimeAction.execute_repair(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    -- Interact with repair NPC (blacksmith, vendor, etc.)
    if core and core.input and core.input.interact_with_object then
        local npc = UnitHelper.get_nearest_creature({ npc_entry })
        if npc then
            core.input.interact_with_object(npc)
        end
    end

    -- Repair using Sylvannas API
    if core and core.input and core.input.repair_all_items then
        core.input.repair_all_items(false) -- use_guild_bank = false
        return "success"
    end
    return "retry"
end

function RuntimeAction.execute_learn_flight_path(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    -- Interact with flight master - flight paths are learned automatically
    -- when taking a taxi flight for the first time
    if core and core.input and core.input.interact_with_object then
        local npc = UnitHelper.get_nearest_creature({ npc_entry })
        if npc then
            core.input.interact_with_object(npc)
        end
    end
    return "success"
end

function RuntimeAction.execute_mailbox(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    -- Open mailbox via core.input.interact_with_object
    if core and core.input and core.input.interact_with_object then
        local npc = UnitHelper.get_nearest_creature({ npc_entry })
        if npc then
            core.input.interact_with_object(npc)
            return "success"
        end
    end
    return "retry"
end

function RuntimeAction.execute_bank(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    -- Open bank via core.input.interact_with_object
    if core and core.input and core.input.interact_with_object then
        local npc = UnitHelper.get_nearest_creature({ npc_entry })
        if npc then
            core.input.interact_with_object(npc)
            return "success"
        end
    end
    return "retry"
end

function RuntimeAction.execute_interact_npc(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    if core and core.input and core.input.interact_with_object then
        local npc = UnitHelper.get_nearest_creature({ npc_entry })
        if npc then
            -- Handle gossip if specified
            if payload.gossip and core.quests and core.quests.select_gossip_option then
                core.quests.select_gossip_option(payload.gossip)
            end
            core.input.interact_with_object(npc)
            return "success"
        end
    end
    return "blocked"
end

function RuntimeAction.execute_loot(payload, ctx)
    local object_entry = payload.object_entry
    -- RuntimeLoot carries only object_entry today; an item id, when present, makes the
    -- loot verifiable against the bags.
    local item_id = payload.item_id or payload.item or payload.item_entry
    local P = ctx.persist or ctx
    local now = (core and core.time and core.time()) or 0

    -- A loot issued on a previous tick is still settling: verify, don't re-interact.
    local L = P._loot_verify
    if L then
        -- Full bags can never receive the item; yield so the vendor-maintenance
        -- detour (which consumes player.bags_full) gets the tick.
        if ctx.blackboard and ctx.blackboard.get
            and ctx.blackboard:get("player.bags_full") == true then
            P._loot_verify = nil
            return "retry"
        end
        local count = ctx:get_item_count(L.item_id)
        if count ~= nil and count > L.baseline then
            P._loot_verify = nil
            return "success"
        end
        if now - L.started_at >= LOOT_VERIFY_TIMEOUT then
            P._loot_verify = nil
            return "retry"
        end
        return "waiting"
    end

    -- Proximity check (W3.6) — if object not in range, navigate first
    if not ctx:is_at_object(object_entry) then
        if ctx.nav and not ctx.nav:is_active() then
            -- Try to get nearest object's position for navigation using UnitHelper
            local nearest_obj = UnitHelper.get_nearest_game_object({ object_entry })
            if nearest_obj and nearest_obj.get_position then
                local ok, obj_pos = pcall(nearest_obj.get_position, nearest_obj)
                if ok and obj_pos then
                    ctx.nav:move_to(obj_pos, { tolerance = 5.0 })
                end
            end
        end
        return "blocked" -- Not in loot range
    end

    -- A3: core.input.loot_object(target) expects the resolved game object
    -- (docs/SylvannasAPI/dev/api/input.md:200), not the raw entry id — passing the entry id
    -- fails silently (no error), so nothing was ever looted while this returned "success" and
    -- the executor advanced past the objective. execute_kill's own corpse-loot path (above)
    -- already resolves and passes the object correctly; this callsite disagreed with it.
    local target_obj = UnitHelper.get_nearest_game_object({ object_entry })
    if not target_obj then
        -- Was in range a moment ago (the is_at_object gate above passed) but not resolvable
        -- this tick — retry rather than faking success on a no-op.
        return "retry"
    end

    if item_id then
        -- Snapshot BEFORE the interaction; the increase is the observable loot.
        local baseline = ctx:get_item_count(item_id) or 0
        if core and core.input and core.input.loot_object then
            core.input.loot_object(target_obj)
        end
        P._loot_verify = { item_id = item_id, baseline = baseline, started_at = now }
        return "waiting"
    end

    if core and core.input and core.input.loot_object then
        core.input.loot_object(target_obj)
    end
    -- No item id to check against: historical success, honestly logged once.
    if not P._loot_unverified_logged then
        P._loot_unverified_logged = true
        publish_action_note(ctx, "loot_unverified", { object_entry = object_entry })
    end
    return "success"
end

-- ============================================================================
-- PR2b: real Grind/Escort/Patrol implementations (A5)
--
-- All three were `return "success" -- Placeholder`, instantly advancing past real compiler
-- output (RuntimeGrind/Escort/Patrol — action.rs:34,35,39) having done nothing. None may ever
-- return "success" for a no-op: each holds ("waiting"/"blocked") until its own observable
-- objective is met, or reports "failed" when it cannot make progress.
-- ============================================================================

--- Grind: kill mobs in an area (by explicit target list or bounding polygon) until
--- minimum_kills is reached. Delegates target acquisition/engagement to execute_kill so both
--- paths share the same sticky-target, loot, chase, and engage-request logic (A3/A4/B3 fixes
--- above apply here too).
--- Drop a quest from the log via the documented three-step Sylvannas flow:
--- select_quest_log_entry(index) → set_abandon_quest() → abandon_quest().
--- Idempotent: not being on the quest (never accepted, or a previous attempt landed)
--- reports success. "retry" (not "waiting") bounds a silently-failing abandon at
--- MAX_RETRIES_PER_ACTION ticks instead of a 300s condition wait.
function RuntimeAction.execute_abandon_quest(payload, ctx)
    local quest_id = payload and payload.quest_id
    if quest_id == nil then
        return "failed", "AbandonQuest without quest_id"
    end
    if not (core and core.quests) then
        return "retry"
    end
    if not is_on_quest(quest_id) then
        return "success"
    end
    local q = core.quests
    if not (q.get_num_quest_log_entries and q.get_quest_log_title
        and q.select_quest_log_entry and q.set_abandon_quest and q.abandon_quest) then
        return "retry"
    end
    local num = q.get_num_quest_log_entries() or 0
    for i = 1, num do
        local ok_t, info = pcall(q.get_quest_log_title, i)
        if ok_t and info and not info.is_header and info.quest_id == quest_id then
            pcall(q.select_quest_log_entry, i)
            pcall(q.set_abandon_quest)
            pcall(q.abandon_quest)
            -- The client processes the abandon asynchronously; the retry path
            -- re-enters here next tick and the is_on_quest check above confirms.
            return "retry"
        end
    end
    -- On the quest per is_on_quest but not found in the log listing — refresh race;
    -- try again next tick.
    return "retry"
end

function RuntimeAction.execute_grind(payload, ctx)
    local targets = payload.targets or payload.creature_entries
    local minimum_kills = payload.minimum_kills or payload.quantity or 1

    if not (type(targets) == "table" and #targets > 0) then
        -- No creature list to grind against — cannot make progress.
        return "failed"
    end

    -- VERIFY-IN-GAME: RuntimeGrind.polygon (a bounded area) is not enforced here — there is no
    -- Sylvannas API to query "am I inside this polygon" cheaply, and get_all_objects already
    -- scans the full visible range (F4). Kills are still counted correctly; only the area
    -- restriction is unenforced pending a polygon-aware target filter.
    local kill_payload = {
        creature_entries = targets,
        quantity = minimum_kills,
        loot = payload.loot,
        ignore_elites = payload.ignore_elites,
    }
    return RuntimeAction.execute_kill(kill_payload, ctx)
end

--- Escort: stay near an NPC being escorted until it reaches its destination.
--- Holds ("waiting") while the escorted NPC is alive and not yet at the destination; only a
--- confirmed arrival (or the escortee's death, if observable) ends the action.
function RuntimeAction.execute_escort(payload, ctx)
    local npc_entry = payload.npc_entry or payload.creature_entry
    local destination = payload.destination or payload.position

    if not npc_entry then
        return "failed" -- No NPC to escort
    end

    local escortee = UnitHelper.get_nearest_creature({ npc_entry })
    if not escortee then
        -- Not spawned/visible yet (or already despawned after completing); cannot confirm
        -- either way, so hold rather than silently declaring victory.
        return "waiting"
    end

    local ok_dead, dead = pcall(escortee.is_dead, escortee)
    if ok_dead and dead == true then
        -- The escortee died: the escort cannot complete as intended.
        return "failed"
    end

    local target_pos = nil
    if type(destination) == "table" and destination.x then
        target_pos = destination
    elseif type(destination) == "string" then
        target_pos = ctx:get_zone_waypoint(destination)
    end

    if target_pos and ctx.is_at_destination and ctx:is_at_destination(target_pos, 5.0) then
        return "success"
    end

    -- Stay near the escortee; nav ownership/chase logic mirrors execute_kill's approach.
    if ctx.nav and escortee.get_position then
        local ok_pos, epos = pcall(escortee.get_position, escortee)
        if ok_pos and epos and not ctx.nav:is_active() then
            ctx.nav:move_to(epos, { tolerance = 5.0 })
        end
    end
    return "waiting"
end

--- Patrol: visit an ordered list of waypoints. Advances its own internal waypoint index in
--- ctx.persist as each point is reached; only reports "success" once every waypoint has been
--- visited.
function RuntimeAction.execute_patrol(payload, ctx)
    local waypoints = payload.waypoints or payload.points
    if not (type(waypoints) == "table" and #waypoints > 0) then
        return "failed" -- Nothing to patrol
    end

    local P = ctx.persist or ctx
    P._patrol_idx = P._patrol_idx or 1

    if P._patrol_idx > #waypoints then
        P._patrol_idx = nil -- Done; reset so a re-run starts from the top
        return "success"
    end

    local wp = waypoints[P._patrol_idx]
    local target_pos = nil
    if type(wp) == "table" and wp.x then
        target_pos = wp
    elseif type(wp) == "string" then
        target_pos = ctx:get_zone_waypoint(wp)
    end

    if not target_pos then
        return "failed" -- Unresolvable waypoint; do not silently skip it
    end

    if ctx.is_at_destination and ctx:is_at_destination(target_pos, 5.0) then
        P._patrol_idx = P._patrol_idx + 1
        if P._patrol_idx > #waypoints then
            P._patrol_idx = nil
            return "success"
        end
        return "waiting" -- Advance to the next waypoint on a later tick
    end

    if ctx.nav and not ctx.nav:is_active() then
        ctx.nav:move_to(target_pos, { tolerance = 5.0 })
    end
    return "waiting"
end

return RuntimeAction