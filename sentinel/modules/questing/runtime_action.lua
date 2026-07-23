--- Sentinel Runtime Action Executor
--- Executes RuntimeAction types defined in RuntimeProfile
--- Returns: "success", "retry", "blocked", "failed", "skipped"

-- ============================================================================
-- Named constants for navigation and proximity (W3.1, W3.6)
-- ============================================================================
local NAV_RETRY_DELAY = 1.0    -- Seconds between navigation retries

-- Nil-safe distance (returns infinity on bad input) — used to notice a chased target drifting.
local Geometry = (function()
    local ok, mod = pcall(require, "core/geometry")
    if ok and type(mod) == "table" and mod.distance then return mod end
    return nil
end)()

local RuntimeAction = {}

-- ============================================================================
-- Unit Helper: Optimized object retrieval with Sylvannas API compliance
-- Replaces fabricated core.object_manager.GetNearest* APIs
-- ============================================================================
local UnitHelper = {}

--- Get all objects from object manager (Sylvannas API)
--- @return table|nil Array of game_object items
function UnitHelper._get_all_objects()
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
--- @return game_object|nil Nearest matching creature
function UnitHelper.get_nearest_creature(entries)
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
    local nearest_obj = nil
    local nearest_dist_sq = math.hfov and math.huge or 999999999

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

            if npc_id and entry_set[npc_id] then
                -- Check distance if we have player position
                local dist_sq = nearest_dist_sq
                if player_pos and obj.get_position then
                    local ok, pos = pcall(obj.get_position, obj)
                    if ok and pos then
                        local dx = pos.x - player_pos.x
                        local dy = pos.y - player_pos.y
                        local dz = pos.z - player_pos.z
                        dist_sq = dx*dx + dy*dy + dz*dz
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

    local nearest_obj = nil
    local nearest_dist_sq = 999999999

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
                        local dx = pos.x - player_pos.x
                        local dy = pos.y - player_pos.y
                        local dz = pos.z - player_pos.z
                        dist_sq = dx*dx + dy*dy + dz*dz
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

function RuntimeAction.execute_accept_quest(payload, ctx)
    local quest_id = payload.quest_id
    local npc_entry = payload.npc_entry

    -- Already done? Nothing to do — treat as satisfied rather than retrying forever.
    if is_on_quest(quest_id) or is_quest_rewarded(quest_id) then
        return "success"
    end

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end
    if not ensure_gossip_open(npc_entry) then
        return "retry" -- dialog not up yet; interact was issued, poll next tick
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
        return "success"
    end
    return "retry"
end

function RuntimeAction.execute_turnin_quest(payload, ctx)
    local quest_id = payload.quest_id
    local npc_entry = payload.npc_entry

    -- Already handed in — satisfied, not a failure to retry.
    if is_quest_rewarded(quest_id) then
        return "success"
    end
    -- Not in the log and not rewarded: there is nothing to turn in here.
    if not is_on_quest(quest_id) then
        return "skipped"
    end

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
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
    local choice = payload.choose_reward or payload.reward_choice
    if choice and core.quests.get_quest_reward then
        pcall(core.quests.get_quest_reward, choice)
    end

    -- Verify: the quest must have left the log (or be flagged complete).
    if is_quest_rewarded(quest_id) or not is_on_quest(quest_id) then
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
    if type(z) == "number" and z ~= 0 then
        return z
    end
    if core and core.get_height_for_position then
        local ok, h = pcall(core.get_height_for_position, { x = x, y = y, z = 0 })
        if ok and type(h) == "number" and h ~= 0 then
            return h
        end
    end
    local player = UnitHelper.get_local_player()
    if player and player.get_position then
        local ok_p, pos = pcall(player.get_position, player)
        if ok_p and type(pos) == "table" and type(pos.z) == "number" then
            return pos.z
        end
    end
    return z or 0
end

--- Horizontal arrival check, ignoring height (see execute_travel for why Z is untrustworthy).
--- Falls back to the context's 3D check when the player position cannot be read.
function RuntimeAction.is_at_destination_2d(ctx, target_pos, tol)
    if not target_pos then return false end
    -- The 3D check is authoritative when it PASSES: it can only be stricter, never looser. The 2D
    -- test below exists solely to also accept arrivals that a bad inferred Z would reject.
    if ctx.is_at_destination and ctx:is_at_destination(target_pos, tol) then
        return true
    end
    local player = UnitHelper.get_local_player()
    if not (player and player.get_position) then
        return false
    end
    local ok, pos = pcall(player.get_position, player)
    if not ok or type(pos) ~= "table" then
        return false
    end
    local dx = (tonumber(pos.x) or 0) - (tonumber(target_pos.x) or 0)
    local dy = (tonumber(pos.y) or 0) - (tonumber(target_pos.y) or 0)
    return math.sqrt(dx * dx + dy * dy) <= (tonumber(tol) or 5.0)
end

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

function RuntimeAction.execute_kill(payload, ctx)
    local entries = payload.creature_entries or {}
    local quantity = payload.quantity or 1

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

    -- Find and target nearest creature using UnitHelper (Sylvannas API compliant)
    local target = UnitHelper.get_nearest_creature(entries)
    if target and target.get_position then
        -- Check if target is dead — count it toward quantity
        if target:is_dead() then
            P.kill_counts[key] = P.kill_counts[key] + 1
            if P.kill_counts[key] >= quantity then
                return trace("success_killed", "success")
            end
            return trace("next_target", "blocked")
        end

        -- Range is measured against the TARGET WE FOUND, not entries[1].
        --
        -- This previously asked `is_at_npc(entries[1], 30)`. With a multi-entry kill such as
        -- [299, 69, 704, 705], the nearest creature can be a Timber Wolf (69) while no Young Wolf
        -- (299) is within 30 yards — so the check failed and the bot navigated forever while
        -- standing next to a perfectly valid target.
        local in_range = false
        local dist = nil
        local ok_pos, tpos = pcall(target.get_position, target)
        local player = UnitHelper.get_local_player()
        if ok_pos and tpos and player and player.get_position then
            local ok_p, ppos = pcall(player.get_position, player)
            if ok_p and ppos and Geometry and Geometry.distance then
                dist = Geometry.distance(ppos, tpos)
                in_range = dist <= 30.0
            end
        end
        if dist == nil then
            -- Could not measure; fall back to the old per-entry proximity check.
            in_range = ctx:is_at_npc(entries[1], 30.0)
        end
        P._kill_trace.dist = dist

        if not in_range then
            -- Chase: mobs wander, so the destination must track the target rather than being
            -- captured once. The old guard only issued move_to when nav was IDLE, which locked
            -- onto a stale position — the bot walked to where the mob used to be and stopped.
            local ok_pos, npc_pos = pcall(target.get_position, target)
            if ok_pos and npc_pos then
                local last = P._chase_dest
                local drifted = (not last)
                    or (Geometry and Geometry.distance
                        and Geometry.distance(last, npc_pos) > 3.0)
                    or false
                if ctx.nav and (drifted or not ctx.nav:is_active()) then
                    ctx.nav:move_to(npc_pos, { tolerance = 5.0 })
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

        -- In range. Nothing here previously did anything at all — it returned "blocked" and
        -- assumed "the combat loop" would notice, but the combat module's world auto-engage is off
        -- by default, so the bot walked up to the mob and stood there. Target it and REQUEST
        -- engagement explicitly on the shared event bus.
        if core and core.input and core.input.set_target then
            pcall(core.input.set_target, target)
        end
        if ctx.event_bus and ctx.event_bus.publish then
            pcall(ctx.event_bus.publish, ctx.event_bus, "combat:engage_requested", {
                target = target,
                source = "questing",
                leash_radius = 40.0,
            })
        end
        -- "waiting", NOT "blocked": blocked drives the profile into its NAVIGATING state, which
        -- then polls the nav adapter forever while the kill action never runs again. "waiting"
        -- holds this action and re-polls each tick without burning the retry budget, which is what
        -- a fight needs — and it is still bounded by MAX_CONDITION_WAIT so a hopeless kill cannot
        -- wedge the run.
        return trace("engaging", "waiting")
    end

    -- No targets found — check if we should navigate to a known spawn area
    local dest = payload.destination
    if dest and ctx.nav and not ctx.nav:is_active() then
        local target_pos = nil
        if type(dest) == "table" and dest.x then
            target_pos = dest
        elseif type(dest) == "string" then
            target_pos = ctx:get_zone_waypoint(dest)
        end
        if target_pos then
            ctx.nav:move_to(target_pos)
            return "blocked" -- Navigating to spawn area
        end
    end
    return "blocked" -- No targets nearby or no API
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

    -- Sell greys using core.input.sell_item or vendor API
    if sell_grey then
        if core and core.input and core.input.sell_greys then
            core.input.sell_greys()
        elseif core and core.inventory and core.inventory.sell_greys then
            core.inventory.sell_greys()
        end
        attempted = true
    end

    -- Repair using core.input.repair_all_items
    if repair then
        if core and core.input and core.input.repair_all_items then
            core.input.repair_all_items(false) -- use_guild_bank = false
        elseif core and core.inventory and core.inventory.repair_all_items then
            core.inventory.repair_all_items()
        end
        attempted = true
    end

    -- Buy items from vendor
    if payload.buy_items then
        if core and core.input and core.input.buy_item then
            for _, item in ipairs(payload.buy_items) do
                local index = item.index or item.slot
                local quantity = item.quantity or 1
                core.input.buy_item(index, quantity)
            end
        end
        attempted = true
    end

    if not attempted then
        return "retry"
    end
    return "success"
end

function RuntimeAction.execute_train(payload, ctx)
    local npc_entry = payload.npc_entry

    if not ctx:is_at_npc(npc_entry) then
        return "blocked"
    end

    -- Interact with trainer NPC, then use core.quests.buy_trainer_service
    if core and core.input and core.input.interact_with_object then
        local npc = UnitHelper.get_nearest_creature({ npc_entry })
        if npc then
            core.input.interact_with_object(npc)
        end
    end

    -- Train spells are typically handled by selecting from trainer window
    -- For now, we just need to be at the NPC and have interacted
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
    if core and core.input and core.input.take_taxi then
        local dest_idx = destination.index or destination.id or 1
        core.input.take_taxi(dest_idx)
        return "success"
    end
    return "retry"
end

function RuntimeAction.execute_hearth(payload, ctx)
    -- Use hearthstone via core.input.use_item with hearthstone item ID
    if core and core.input and core.input.use_item then
        local hearthstone_id = 6948 -- Default Hearthstone ID
        core.input.use_item(hearthstone_id)
        return "success"
    end
    return "retry"
end

function RuntimeAction.execute_wait(payload, ctx)
    local duration = payload.duration
    if not ctx.wait_start then
        ctx.wait_start = (core and core.time and core.time()) or 0
        return "blocked" -- Start waiting
    end

    if (core and core.time and core.time()) - ctx.wait_start >= duration then
        ctx.wait_start = nil
        return "success"
    end
    return "blocked" -- Still waiting
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

    if core and core.input and core.input.loot_object then
        core.input.loot_object(object_entry)
    end
    return "success"
end

function RuntimeAction.execute_grind(payload, ctx)
    -- Navigate to grind area and kill mobs
    return "success" -- Placeholder - needs area navigation
end

function RuntimeAction.execute_escort(payload, ctx)
    -- Escort NPC behavior
    return "success" -- Placeholder
end

function RuntimeAction.execute_patrol(payload, ctx)
    -- Patrol waypoints
    return "success" -- Placeholder
end

return RuntimeAction