local ObjectiveTracker = {}
ObjectiveTracker.__index = ObjectiveTracker

local function num(value)
    return tonumber(value) or 0
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function object_entry_id(obj)
    if not obj then
        return 0
    end
    if type(obj.get_entry) == "function" then
        local ok, id = pcall(obj.get_entry, obj)
        if ok and tonumber(id) and tonumber(id) > 0 then
            return tonumber(id)
        end
    end
    if type(obj.get_entry_id) == "function" then
        local ok, id = pcall(obj.get_entry_id, obj)
        if ok and tonumber(id) and tonumber(id) > 0 then
            return tonumber(id)
        end
    end
    if type(obj.get_object_id) == "function" then
        local ok, id = pcall(obj.get_object_id, obj)
        if ok and tonumber(id) and tonumber(id) > 0 then
            return tonumber(id)
        end
    end
    if type(obj.get_npc_id) == "function" then
        local ok, id = pcall(obj.get_npc_id, obj)
        if ok and tonumber(id) and tonumber(id) > 0 then
            return tonumber(id)
        end
    end
    if type(obj.get_item_id) == "function" then
        local ok, id = pcall(obj.get_item_id, obj)
        if ok and tonumber(id) and tonumber(id) > 0 then
            return tonumber(id)
        end
    end
    return 0
end

local function object_name(obj)
    if not obj or type(obj.get_name) ~= "function" then
        return nil
    end
    local ok, name = pcall(obj.get_name, obj)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function is_possible_gameobject(obj)
    if not obj then
        return false
    end
    if type(obj.get_type) ~= "function" then
        return true
    end
    local ok, value = pcall(obj.get_type, obj)
    if not ok then
        return true
    end
    if type(value) == "string" then
        local lowered = value:lower()
        return lowered:find("gameobject", 1, true) ~= nil
            or lowered:find("object", 1, true) ~= nil
            or lowered == "go"
    end
    return true
end

local function owner_from_team_hint(objective)
    local hint = tostring(objective and objective.team_hint or "")
    if hint:find("ALLIANCE", 1, true) then
        return "ALLIANCE"
    end
    if hint:find("HORDE", 1, true) then
        return "HORDE"
    end
    return nil
end

local function normalize_owner(raw_owner, player_side)
    if raw_owner == nil then
        return "UNKNOWN"
    end
    if raw_owner == "CONTESTED" then
        return "CONTESTED"
    end
    if raw_owner == "NEUTRAL" then
        return "NEUTRAL"
    end
    if raw_owner == "ALLIANCE" then
        return player_side == "ALLIANCE" and "FRIENDLY" or "ENEMY"
    end
    if raw_owner == "HORDE" then
        return player_side == "HORDE" and "FRIENDLY" or "ENEMY"
    end
    return "UNKNOWN"
end

function ObjectiveTracker:new(blackboard)
    local o = setmetatable({}, ObjectiveTracker)
    o._blackboard = blackboard
    o._states = {}
    o._owner_ttl_ms = 2500
    o._eots_barriers = {
        ALLIANCE = {
            entry = 184719,
            name = "Forcefield 000",
            anchor = { x = 2527.60, y = 1596.91, z = 1262.13 },
        },
        HORDE = {
            entry = 184720,
            name = "Forcefield 001",
            anchor = { x = 1803.21, y = 1539.49, z = 1261.09 },
        },
    }
    return o
end

function ObjectiveTracker:reset()
    self._states = {}
end

function ObjectiveTracker:_visible_objects()
    if not core or not core.object_manager or type(core.object_manager.get_visible_objects) ~= "function" then
        return {}, false
    end
    local ok, objects = pcall(core.object_manager.get_visible_objects)
    if ok and type(objects) == "table" then
        return objects, true
    end
    return {}, false
end

function ObjectiveTracker:_detect_eots_spawn_barrier(visible, side)
    local signals = {
        visible_objects_supported = true,
        spawn_barrier_seen = false,
        spawn_barrier_entry = nil,
        spawn_barrier_name = nil,
        spawn_barrier_distance = nil,
        spawn_barrier_source = "none",
    }

    local barrier = self._eots_barriers[tostring(side or "")]
    if not barrier then
        return signals
    end

    local nearest_distance = 99999
    for _, obj in ipairs(visible or {}) do
        if is_possible_gameobject(obj) and type(obj.get_position) == "function" then
            local ok_pos, pos = pcall(obj.get_position, obj)
            if ok_pos and type(pos) == "table" then
                local d = distance(barrier.anchor, pos)
                if d <= 18 and d < nearest_distance then
                    local entry_id = object_entry_id(obj)
                    local name = object_name(obj)
                    if entry_id == barrier.entry then
                        nearest_distance = d
                        signals.spawn_barrier_seen = true
                        signals.spawn_barrier_entry = entry_id
                        signals.spawn_barrier_name = name or barrier.name
                        signals.spawn_barrier_distance = d
                        signals.spawn_barrier_source = "entry_id"
                    elseif name == barrier.name then
                        nearest_distance = d
                        signals.spawn_barrier_seen = true
                        signals.spawn_barrier_entry = entry_id > 0 and entry_id or nil
                        signals.spawn_barrier_name = name
                        signals.spawn_barrier_distance = d
                        signals.spawn_barrier_source = "name"
                    end
                end
            end
        end
    end

    return signals
end

function ObjectiveTracker:_owner_for_objective(objective, visible, now_ms)
    local anchor = { x = objective.x, y = objective.y, z = objective.z }
    local detected_owner = nil
    local detected_entry = nil
    local nearest = 99999

    for _, obj in ipairs(visible) do
        if is_possible_gameobject(obj) and type(obj.get_position) == "function" then
            local ok_pos, pos = pcall(obj.get_position, obj)
            if ok_pos and type(pos) == "table" then
                local d = distance(anchor, pos)
                if d < 25 and d < nearest then
                    local entry_id = object_entry_id(obj)
                    local owner = type(objective.owner_map) == "table" and objective.owner_map[entry_id] or nil
                    if owner then
                        nearest = d
                        detected_owner = owner
                        detected_entry = entry_id
                    end
                end
            end
        end
    end

    if not detected_owner and (objective.type == "BOSS" or objective.type == "CAPTAIN" or objective.type == "GATE") then
        detected_owner = owner_from_team_hint(objective)
    end

    local prior = self._states[objective.id]
    if not detected_owner and type(prior) == "table" and prior.raw_owner ~= nil then
        local age_ms = now_ms - num(prior.updated_ms)
        if age_ms >= 0 and age_ms <= self._owner_ttl_ms then
            detected_owner = prior.raw_owner
            detected_entry = prior.entry_id
        end
    end

    return detected_owner, detected_entry, nearest
end

function ObjectiveTracker:update(player_side, objectives, opts)
    opts = type(opts) == "table" and opts or {}
    local visible, visible_supported = self:_visible_objects()
    local now_ms = num(self._blackboard:get("system.now_ms", 0))
    local next_states = {}
    local runtime_signals = {
        visible_objects_supported = visible_supported == true,
        spawn_barrier_seen = false,
        spawn_barrier_entry = nil,
        spawn_barrier_name = nil,
        spawn_barrier_distance = nil,
        spawn_barrier_source = visible_supported == true and "none" or "fallback",
    }

    for _, objective in ipairs(objectives or {}) do
        local raw_owner, entry_id, nearest = self:_owner_for_objective(objective, visible, now_ms)
        next_states[objective.id] = {
            objective_id = objective.id,
            owner = normalize_owner(raw_owner, player_side),
            raw_owner = raw_owner,
            entry_id = entry_id,
            distance = nearest,
            updated_ms = now_ms,
        }
    end

    if tostring(opts.bg_key or "") == "EOTS" then
        if visible_supported == true then
            runtime_signals = self:_detect_eots_spawn_barrier(visible, opts.side or player_side)
            runtime_signals.visible_objects_supported = true
            local barrier = self._eots_barriers[tostring(opts.side or player_side or "")]
            if barrier and type(opts.player_pos) == "table" then
                runtime_signals.spawn_barrier_distance = distance(opts.player_pos, barrier.anchor)
            end
        else
            runtime_signals.spawn_barrier_source = "fallback"
        end
    end

    self._states = next_states
    return next_states, runtime_signals
end

function ObjectiveTracker:get_all_states()
    return self._states
end

function ObjectiveTracker:get_momentum_summary()
    local friendly = 0
    local enemy = 0
    local resolved = 0
    for _, state in pairs(self._states) do
        if state.owner == "FRIENDLY" then
            friendly = friendly + 1
            resolved = resolved + 1
        elseif state.owner == "ENEMY" then
            enemy = enemy + 1
            resolved = resolved + 1
        end
    end
    if resolved == 0 then
        return 0
    end
    return (friendly - enemy) / resolved
end

return ObjectiveTracker
