-- runtime/sensors/world_observer.lua
-- Recording Mode's observation surface — ADR 09a work unit W7.
--
-- recorder.lua subscribes to nine event-bus topics. One had a producer (`player:profile_refreshed`,
-- from sensor_hub.lua); the eight `game:*` quest and service topics had none, so Recording Mode —
-- the entire replacement for the retired RestedXP corpus — was inert in game while every recorder
-- unit test passed. This module is the missing producer.
--
-- WHY THIS IS A DIFFER AND NOT A CALLBACK BRIDGE: the Sylvannas SDK exposes no quest-lifecycle
-- callback. `core.register_on_game_event_callback` forwards QUEST_LOG_UPDATE, but that event carries
-- no arguments (see docs/SylvannasAPI/dev/api/events.md) — it says "something in the log changed",
-- never which quest or in which direction. Identity therefore has to be recovered by comparing the
-- quest log against the previous observation of it. The client event is still valuable, just as a
-- CLOCK rather than as data: it is the only signal that fires AT the transition, so it is used to
-- schedule an immediate walk instead of waiting out the pacing interval.
--
-- Purity: every SDK reader is injected, so the whole derivation is exercisable offline against a
-- scripted client — the same discipline runner_state.lua follows.

local Compat = require("shared/compat")
local safe_call = Compat.safe_call

local WorldObserver = {}
WorldObserver.__index = WorldObserver

--- The topics this module produces. Also the subscriber gate: with none of these subscribed there is
--- no recording in progress, and the observer must cost the client nothing.
WorldObserver.TOPICS = {
    "game:quest_accepted",
    "game:quest_turned_in",
    "game:quest_abandoned",
    "game:quest_objective_progress",
    "game:vendor_used",
    "game:trainer_used",
    "game:taxi_taken",
    "game:hearthstone_used",
}

-- Pacing. Two cadences, because the two kinds of reads cost wildly different amounts.
--
-- The quest-log walk is the expensive one: get_num_quest_log_entries, then a get_quest_log_title per
-- entry, then get_num_quest_leader_boards + a get_quest_log_leader_board per objective — around 85
-- SDK calls for a full log. At frame rate that is ~5000 calls/second, which is the same class of
-- waste F6 removed from callback_bridge's engine payloads. 5 seconds matches the interval
-- modules/questing/module.lua already settled on for its own quest sync (QUEST_SYNC_INTERVAL), so
-- the two pollers cost the same and there is one number to reason about. The interval is only a
-- SAFETY NET: QUEST_LOG_UPDATE forces a walk on the very next frame, so in practice a transition is
-- observed within one frame of the client noticing it, not up to five seconds later. That latency
-- is what makes npc attribution work at all — five seconds is long enough for a human to close the
-- gossip frame and target something else, which would attribute the quest to the wrong npc.
WorldObserver.QUEST_POLL_INTERVAL = 5.0

-- The frame/position reads are three calls (gossip shown, trainer service count, vendor item count)
-- plus arithmetic on a position the sensor hub already fetched. 1 Hz is cheap and no merchant,
-- trainer or flight-master frame a human interacts with is open for less than a second.
WorldObserver.POLL_INTERVAL = 1.0

-- `is_quest_flagged_completed` can answer a COLD FALSE: the client has not received the completed-
-- quest bitmask for that id yet and reports "not completed" for a quest that was just handed in. A
-- naive diff turns that into an abandon, and an abandon makes the recorder RETRACT every task the
-- quest contributed — a silent hole in the recording. So a departure is never classified at the
-- moment it is observed. It becomes pending, and only an independently repeated read may conclude.
WorldObserver.DEPARTURE_SETTLE = 3.0
WorldObserver.MIN_FLAG_SAMPLES = 2

-- How long an observed interaction may still be credited with a quest transition. A quest accept
-- lands in the log a fraction of a second after the click, so this window only has to cover the gap
-- between the interaction and the next walk. Beyond it the observer publishes a nil npc: an
-- AcceptQuest pinned to an npc that never gave the quest is worse than one with no npc at all,
-- because the resolver will happily route a human to it.
WorldObserver.NPC_ATTRIBUTION_TTL = 15.0

-- Taxi. There is no taxi API in the SDK at all, so a flight is inferred geometrically against the
-- flight-node table the client itself shipped (kernel/catalogs/taxi_nodes.lua, generated from
-- TaxiNodes.dbc). Arm at a flight master, confirm on arrival at a DIFFERENT node.
WorldObserver.TAXI_NODE_RADIUS = 30.0
WorldObserver.TAXI_MIN_DISPLACEMENT = 300.0
-- The discriminator against a human who opened the flight map, declined, and ran there instead.
-- TBC ground speeds top out at 14 yd/s (100% epic mount); taxi flights average around 28 yd/s
-- including the ascent. 15 sits above every ground option and below every flight.
WorldObserver.TAXI_MIN_AVG_SPEED = 15.0
WorldObserver.TAXI_ARM_TTL = 900.0

-- Hearthstone. Using the item is not arriving — the cast is a 10 second channel that a single hit
-- breaks, which is exactly the distinction runtime_action.lua's hearth handler had to learn. So the
-- cast only ARMS; the teleport itself is the evidence, and it is the same 500 yard jump threshold
-- runtime_action.lua uses (HEARTH_JUMP_SQ), for the same reason: no walk covers that in one poll.
WorldObserver.HEARTHSTONE_SPELL_ID = 8690
WorldObserver.ASTRAL_RECALL_SPELL_ID = 556
WorldObserver.HEARTH_JUMP = 500.0
WorldObserver.HEARTH_TIMEOUT = 20.0

-- ---------------------------------------------------------------------------
-- SDK access
-- ---------------------------------------------------------------------------

--- Every reader is resolved through this so a missing SDK surface degrades to "no observation"
--- rather than an error inside the tick. The offline harness mocks only part of `core`, and a
--- sensor that throws takes the whole sensor hub refresh with it.
local function sdk_call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if not ok then
        return nil
    end
    return value
end

local function default_quests()
    return (core and core.quests) or {}
end

local function default_vendor_item_count()
    return function()
        return core and core.game_ui and sdk_call(core.game_ui.get_vendor_item_count) or 0
    end
end

--- The CONTINENT map id, which is what taxi_nodes.lua's `map` column holds.
local function default_map_id()
    return function()
        return core and core.get_map_id and sdk_call(core.get_map_id) or nil
    end
end

--- The ZONE the player is standing in — a different id space from the continent above, and the one
--- a Hearth destination is expressed in. Falls back to the continent when the UI map is unreadable,
--- because a coarse destination still resolves and a nil one is dropped by the recorder outright.
local function default_zone()
    return function()
        local id = core and core.game_ui and sdk_call(core.game_ui.get_current_map_id)
        if id == nil then
            id = core and core.get_map_id and sdk_call(core.get_map_id) or nil
        end
        local name = core and core.get_map_name and sdk_call(core.get_map_name) or nil
        return {
            id = tonumber(id),
            name = (type(name) == "string" and name ~= "") and name or nil,
        }
    end
end

local function default_taxi_nodes()
    local ok, catalog = pcall(require, "kernel/catalogs/taxi_nodes")
    if ok and type(catalog) == "table" and type(catalog.nodes) == "table" then
        return catalog.nodes
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

--- Identify a unit as an npc. Returns nil unless a positive entry id is readable: a nil npc is an
--- honest "not attributable", whereas an id of 0 or a player guid would fabricate one.
local function npc_identity(unit)
    if unit == nil then
        return nil
    end
    local id = tonumber(safe_call(unit, "get_npc_id")) or tonumber(safe_call(unit, "get_entry_id"))
    if not id or id <= 0 then
        return nil
    end
    local name = safe_call(unit, "get_name")
    return { id = id, name = (type(name) == "string" and name ~= "") and name or nil }
end

--- Parse one leader-board line, e.g. `"Wolves slain: 3/10"`.
--- The SDK wrapper returns only the display string — Blizzard's own API also returns the objective
--- TYPE ("item" / "monster" / "object"), but `core.quests.get_quest_log_leader_board` drops it, so
--- the kind cannot be recovered here and is deliberately not guessed.
local function parse_leader_board(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local description, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
    if not have then
        have, need = text:match("(%d+)%s*/%s*(%d+)")
        description = nil
    end
    if not have then
        return nil
    end
    return {
        name = description and description:gsub("%s+$", "") or nil,
        have = tonumber(have),
        need = tonumber(need),
    }
end

local function nearest_taxi_node(nodes, position, map_id, radius)
    if type(nodes) ~= "table" or type(position) ~= "table" then
        return nil
    end
    local best_id, best_name, best_distance = nil, nil, radius
    for id, node in pairs(nodes) do
        if type(node) == "table" and (map_id == nil or node.map == nil or node.map == map_id) then
            local distance = Compat.dist(position, node)
            if distance <= best_distance then
                best_id, best_name, best_distance = id, node.name, distance
            end
        end
    end
    return best_id, best_name
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

--- @param event_bus table the shared EventBus
--- @param deps table|nil injectable SDK readers: `{ quests, vendor_item_count, taxi_nodes }`
function WorldObserver:new(event_bus, deps)
    deps = deps or {}
    local o = setmetatable({}, WorldObserver)
    o._event_bus = event_bus
    o._quests = deps.quests or default_quests()
    o._vendor_item_count = deps.vendor_item_count or default_vendor_item_count()
    o._taxi_nodes = deps.taxi_nodes or default_taxi_nodes()
    -- Map and zone are read through thunks rather than fetched by the caller every frame. They are
    -- only needed while a flight is armed or a hearth has landed, and paying two SDK calls per frame
    -- for state consulted a handful of times per session is the exact waste F6 removed from
    -- callback_bridge's engine payloads.
    o._read_map_id = deps.map_id or default_map_id()
    o._read_zone = deps.zone or default_zone()

    o:_reset()

    if event_bus and type(event_bus.subscribe) == "function" then
        -- The client's own quest signal, used as a clock: it fires at the transition, which is the
        -- only moment at which the interacted npc is still knowable.
        event_bus:subscribe("game:quest_log_update", function()
            o._quest_poll_requested = true
        end)
        local function on_cast(payload)
            o:_note_spell_cast(payload)
        end
        event_bus:subscribe("spell:manual_cast", on_cast)
        event_bus:subscribe("spell:world_cast", on_cast)
    end

    return o
end

--- Drop every derivation state. Called on construction and whenever recording stops, so that the
--- NEXT recording re-baselines the quest log it inherits instead of replaying it as fresh accepts.
function WorldObserver:_reset()
    self._baselined = false
    self._known = {}
    self._objectives = {}
    self._pending = {}
    self._last_npc = nil
    self._last_poll_at = nil
    self._last_quest_poll_at = nil
    self._quest_poll_requested = false
    self._vendor_open = nil
    self._trainer_open = nil
    self._taxi = nil
    self._hearth = nil
end

-- ---------------------------------------------------------------------------
-- Activity gate
-- ---------------------------------------------------------------------------

--- Reaches into EventBus's internal `_subs` the same way callback_bridge.lua does, and just as
--- defensively: if the field is missing or renamed, assume there IS an audience rather than
--- silently swallowing a recording. core/event_bus.lua is not owned by this unit.
function WorldObserver:_is_active()
    local bus = self._event_bus
    if type(bus) ~= "table" then
        return false
    end
    if type(bus._subs) ~= "table" then
        return true
    end
    for _, topic in ipairs(WorldObserver.TOPICS) do
        local list = bus._subs[topic]
        if type(list) == "table" and #list > 0 then
            return true
        end
    end
    return false
end

function WorldObserver:_publish(topic, payload)
    if self._event_bus then
        self._event_bus:publish(topic, payload)
    end
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

--- @param now number seconds (core.time())
--- @param ctx table `{ position, map_id, zone_id, zone_name, target }` — state the sensor hub has
---        already read this frame, passed in rather than re-fetched so one frame yields one read.
function WorldObserver:refresh(now, ctx)
    now = tonumber(now) or 0
    ctx = ctx or {}

    self._now = now
    if type(ctx.position) == "table" and tonumber(ctx.position.x) then
        -- Copy, never alias: the SDK reuses position tables between frames, so a stored reference
        -- would silently rewrite the origin a hearth or flight is being measured against.
        self._position = {
            x = tonumber(ctx.position.x) or 0,
            y = tonumber(ctx.position.y) or 0,
            z = tonumber(ctx.position.z) or 0,
        }
    end
    if ctx.map_id ~= nil then self._map_id = tonumber(ctx.map_id) end
    if ctx.zone_id ~= nil then self._zone_id = tonumber(ctx.zone_id) end
    if ctx.zone_name ~= nil then self._zone_name = ctx.zone_name end

    if not self:_is_active() then
        if self._baselined or self._last_poll_at then
            self:_reset()
        end
        return
    end

    local frame_due = self._last_poll_at == nil or (now - self._last_poll_at) >= WorldObserver.POLL_INTERVAL
    if frame_due then
        self._last_poll_at = now
        self:_observe_services(ctx, now)
        self:_observe_taxi(now)
        self:_observe_hearth(now)
        -- Resolution runs BEFORE the walk on purpose: a departure discovered by this frame's walk
        -- must never be classified by this frame, which is what makes a cold completed-flag read
        -- structurally unable to mint an abandon.
        self:_resolve_departures(now)
    end

    local quest_due = self._quest_poll_requested
        or self._last_quest_poll_at == nil
        or (now - self._last_quest_poll_at) >= WorldObserver.QUEST_POLL_INTERVAL
    if quest_due then
        self._quest_poll_requested = false
        self._last_quest_poll_at = now
        self:_walk_quest_log(now)
    end
end

-- ---------------------------------------------------------------------------
-- Attribution
-- ---------------------------------------------------------------------------

--- Prefer what the sensor hub already read this frame; fall back to the SDK only when a rare path
--- actually needs it.
function WorldObserver:_current_map_id()
    if self._map_id ~= nil then
        return self._map_id
    end
    return tonumber(sdk_call(self._read_map_id))
end

function WorldObserver:_current_zone()
    if self._zone_id ~= nil then
        return self._zone_id, self._zone_name
    end
    local zone = sdk_call(self._read_zone)
    if type(zone) ~= "table" then
        return nil, nil
    end
    return tonumber(zone.id), zone.name
end

function WorldObserver:_attributed_npc(now)
    local last = self._last_npc
    if not last or (now - last.at) > WorldObserver.NPC_ATTRIBUTION_TTL then
        return nil
    end
    return last
end

--- Stamp npc identity onto a payload, or leave it absent. Absent is a real answer.
local function with_npc(payload, npc)
    if npc then
        payload.npc_id = npc.id
        payload.npc_name = npc.name
    end
    return payload
end

-- ---------------------------------------------------------------------------
-- Quest log
-- ---------------------------------------------------------------------------

function WorldObserver:_read_quest_log()
    local quests = self._quests
    local count = tonumber(sdk_call(quests.get_num_quest_log_entries)) or 0
    local seen = {}
    for index = 1, count do
        local info = sdk_call(quests.get_quest_log_title, index)
        if type(info) == "table" and not info.is_header then
            local quest_id = tonumber(info.quest_id)
            if quest_id and quest_id > 0 then
                seen[quest_id] = {
                    log_index = index,
                    title = (type(info.title) == "string" and info.title ~= "") and info.title or nil,
                }
            end
        end
    end
    return seen
end

function WorldObserver:_walk_quest_log(now)
    local seen = self:_read_quest_log()

    if not self._baselined then
        -- Everything already in the log was accepted before this recording began, at npcs nobody
        -- observed. Publishing them would fabricate a route the human never played.
        self._baselined = true
        self._known = seen
        for quest_id, entry in pairs(seen) do
            self._objectives[quest_id] = self:_read_objectives(entry.log_index)
        end
        return
    end

    local npc = self:_attributed_npc(now)

    for quest_id, entry in pairs(seen) do
        if not self._known[quest_id] then
            self._known[quest_id] = entry
            self._objectives[quest_id] = self:_read_objectives(entry.log_index)
            self:_publish("game:quest_accepted", with_npc({
                quest_id = quest_id,
                quest_name = entry.title,
            }, npc))
        else
            self._known[quest_id] = entry
            self:_diff_objectives(quest_id, entry.log_index)
        end
    end

    for quest_id in pairs(self._known) do
        if not seen[quest_id] and not self._pending[quest_id] then
            -- A missing entry is only a SUSPICION here. The walk can transiently report fewer
            -- entries than the character holds while QUEST_LOG_UPDATE churns, so the quest stays in
            -- `_known` (its return must not read as a second accept) and _resolve_departures is the
            -- single authority on what actually happened. Re-asking `is_on_quest` at this point too
            -- would be a second opinion that can only ever agree with the first.
            self._pending[quest_id] = {
                since = now,
                title = self._known[quest_id] and self._known[quest_id].title or nil,
                npc = npc,
                flag_samples = 0,
            }
        end
    end
end

--- Decide, for each departed quest, whether it was handed in or thrown away — but only on evidence
--- gathered across separate polls. See DEPARTURE_SETTLE.
function WorldObserver:_resolve_departures(now)
    for quest_id, pending in pairs(self._pending) do
        if sdk_call(self._quests.is_on_quest, quest_id) == true then
            -- It never actually left. Keep it in `_known` so its return is not a second accept.
            self._pending[quest_id] = nil
        else
            pending.flag_samples = pending.flag_samples + 1
            local completed = sdk_call(self._quests.is_quest_flagged_completed, quest_id) == true
            if completed then
                self._pending[quest_id] = nil
                self._known[quest_id] = nil
                self._objectives[quest_id] = nil
                self:_publish("game:quest_turned_in", with_npc({
                    quest_id = quest_id,
                    quest_name = pending.title,
                }, pending.npc))
            elseif pending.flag_samples >= WorldObserver.MIN_FLAG_SAMPLES
                and (now - pending.since) >= WorldObserver.DEPARTURE_SETTLE then
                self._pending[quest_id] = nil
                self._known[quest_id] = nil
                self._objectives[quest_id] = nil
                self:_publish("game:quest_abandoned", with_npc({
                    quest_id = quest_id,
                    quest_name = pending.title,
                }, pending.npc))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Objectives
-- ---------------------------------------------------------------------------

function WorldObserver:_read_objectives(log_index)
    local quests = self._quests
    local count = tonumber(sdk_call(quests.get_num_quest_leader_boards, log_index)) or 0
    local objectives = {}
    for obj_index = 1, count do
        local parsed = parse_leader_board(sdk_call(quests.get_quest_log_leader_board, obj_index, log_index))
        if parsed then
            objectives[obj_index] = parsed
        end
    end
    return objectives
end

function WorldObserver:_diff_objectives(quest_id, log_index)
    local current = self:_read_objectives(log_index)
    local previous = self._objectives[quest_id] or {}
    self._objectives[quest_id] = current

    for obj_index, objective in pairs(current) do
        local before = previous[obj_index]
        -- A counter that has not moved is not something the human just did — an objective ticking
        -- 1/10 to 10/10 is ONE "kill ten of these" task, and republishing it per poll would emit a
        -- node per poll. A first sighting at zero is likewise not progress: the quest was accepted,
        -- nothing was done yet.
        local rose = objective.have > ((before and before.have) or 0)
        if rose and objective.have > 0 then
            self:_publish("game:quest_objective_progress", {
                quest_id = quest_id,
                quest_name = self._known[quest_id] and self._known[quest_id].title or nil,
                objective_index = obj_index,
                objective_name = objective.name,
                have = objective.have,
                need = objective.need,
            })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Services: vendor, trainer, and the interaction that attributes quests
-- ---------------------------------------------------------------------------

function WorldObserver:_observe_services(ctx, now)
    local quests = self._quests
    local gossip = sdk_call(quests.is_gossip_frame_shown) == true
    local trainer = tonumber(sdk_call(quests.get_num_trainer_services)) or 0
    local vendor = tonumber(sdk_call(self._vendor_item_count)) or 0

    local interacting = gossip or trainer > 0 or vendor > 0
    if interacting then
        -- An open interaction frame is the one moment the SDK lets us say WHICH npc the human is
        -- dealing with: the frame belongs to the current target. Outside a frame the target is just
        -- whatever the player last clicked, which is not evidence of anything.
        local npc = npc_identity(ctx.target)
        if npc then
            self._last_npc = { id = npc.id, name = npc.name, at = now }
        end
    end

    local npc = self:_attributed_npc(now)

    if self._vendor_open == nil then
        self._vendor_open = vendor > 0
    elseif vendor > 0 and not self._vendor_open then
        self._vendor_open = true
        if npc then
            self:_publish("game:vendor_used", { npc_id = npc.id, npc_name = npc.name })
        end
    elseif vendor <= 0 then
        self._vendor_open = false
    end

    if self._trainer_open == nil then
        self._trainer_open = trainer > 0
    elseif trainer > 0 and not self._trainer_open then
        self._trainer_open = true
        if npc then
            self:_publish("game:trainer_used", { npc_id = npc.id, npc_name = npc.name })
        end
    elseif trainer <= 0 then
        self._trainer_open = false
    end

    if gossip then
        self:_arm_taxi(now)
    end
end

-- ---------------------------------------------------------------------------
-- Taxi
-- ---------------------------------------------------------------------------

function WorldObserver:_arm_taxi(now)
    if self._taxi or not self._position then
        return
    end
    local node_id, node_name = nearest_taxi_node(
        self._taxi_nodes, self._position, self:_current_map_id(), WorldObserver.TAXI_NODE_RADIUS)
    if not node_id then
        return
    end
    self._taxi = {
        from_node = node_id,
        from_name = node_name,
        npc = self:_attributed_npc(now),
        origin = self._position,
        at = now,
    }
end

function WorldObserver:_observe_taxi(now)
    local armed = self._taxi
    if not armed then
        return
    end
    if (now - armed.at) > WorldObserver.TAXI_ARM_TTL then
        self._taxi = nil
        return
    end
    if not self._position then
        return
    end

    local displacement = Compat.dist(armed.origin, self._position)
    local elapsed = now - armed.at
    if displacement < WorldObserver.TAXI_MIN_DISPLACEMENT or elapsed <= 0 then
        return
    end
    if (displacement / elapsed) < WorldObserver.TAXI_MIN_AVG_SPEED then
        -- Slow enough that the human could have walked it, and plenty of them do after opening the
        -- flight map and changing their mind. Recording that as a Flight sends the resolver to a
        -- flight master for a trip that never happened.
        return
    end

    local node_id, node_name = nearest_taxi_node(
        self._taxi_nodes, self._position, self:_current_map_id(), WorldObserver.TAXI_NODE_RADIUS)
    if not node_id or node_id == armed.from_node then
        return
    end

    local payload = {
        from_node = armed.from_node,
        from_name = armed.from_name,
        to_node = node_id,
        to_name = node_name,
    }
    self._taxi = nil
    self:_publish("game:taxi_taken", with_npc(payload, armed.npc))
end

-- ---------------------------------------------------------------------------
-- Hearthstone
-- ---------------------------------------------------------------------------

function WorldObserver:_note_spell_cast(payload)
    local spell_id = tonumber(payload and payload.spell_id)
    if spell_id ~= WorldObserver.HEARTHSTONE_SPELL_ID
        and spell_id ~= WorldObserver.ASTRAL_RECALL_SPELL_ID then
        return
    end
    self._hearth = {
        at = self._now or 0,
        origin = self._position,
    }
end

function WorldObserver:_observe_hearth(now)
    local armed = self._hearth
    if not armed then
        return
    end
    if (now - armed.at) > WorldObserver.HEARTH_TIMEOUT then
        self._hearth = nil
        return
    end
    if not armed.origin or not self._position then
        return
    end
    if Compat.dist(armed.origin, self._position) < WorldObserver.HEARTH_JUMP then
        return
    end

    self._hearth = nil
    -- The destination is where the player LANDED. Reading it at cast time would name the zone they
    -- were escaping, which is the opposite of the task.
    local zone_id, zone_name = self:_current_zone()
    self:_publish("game:hearthstone_used", {
        zone_id = zone_id,
        zone_name = zone_name,
    })
end

return WorldObserver
