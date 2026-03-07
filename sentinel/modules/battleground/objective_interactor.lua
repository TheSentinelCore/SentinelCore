local Events = require("modules/battleground/events")

local ObjectiveInteractor = {}
ObjectiveInteractor.__index = ObjectiveInteractor

local INTERACTABLE_TYPES = {
    NODE = true,
    TOWER = true,
    GRAVEYARD = true,
    FLAG = true,
}

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
    for _, method in ipairs({ "get_entry", "get_entry_id", "get_object_id", "get_npc_id" }) do
        if type(obj[method]) == "function" then
            local ok, id = pcall(obj[method], obj)
            if ok and tonumber(id) and tonumber(id) > 0 then
                return tonumber(id)
            end
        end
    end
    return 0
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

local function can_be_used(obj)
    if not obj or type(obj.can_be_used) ~= "function" then
        return true
    end
    local ok, result = pcall(obj.can_be_used, obj)
    return ok and result ~= false
end

local function use_object(obj)
    if not core or not core.input or type(core.input.use_object) ~= "function" then
        return false
    end
    local ok = pcall(core.input.use_object, obj)
    return ok
end

local function get_visible_objects()
    if not core or not core.object_manager or type(core.object_manager.get_visible_objects) ~= "function" then
        return {}
    end
    local ok, objects = pcall(core.object_manager.get_visible_objects)
    if ok and type(objects) == "table" then
        return objects
    end
    return {}
end

function ObjectiveInteractor:new(event_bus, blackboard, humanization)
    local o = setmetatable({}, ObjectiveInteractor)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._humanization = humanization
    o._last_interact_ms = 0
    o._interact_cooldown_ms = 1500
    o._interact_range = 6.0
    o._current_objective_id = nil
    return o
end

function ObjectiveInteractor:reset()
    self._last_interact_ms = 0
    self._current_objective_id = nil
end

function ObjectiveInteractor:_is_eots_node(objective)
    local bg_key = tostring(self._blackboard:get("bg.key", ""))
    return bg_key == "EOTS" and tostring(objective.type) == "NODE"
end

function ObjectiveInteractor:_build_entry_set(objective)
    local entries = {}
    if type(objective.owner_map) == "table" then
        for entry_id, _ in pairs(objective.owner_map) do
            if tonumber(entry_id) and tonumber(entry_id) > 0 then
                entries[tonumber(entry_id)] = true
            end
        end
    end
    return entries
end

function ObjectiveInteractor:_find_interactable(objective, player_pos)
    local entry_set = self:_build_entry_set(objective)
    local obj_center = { x = num(objective.x), y = num(objective.y), z = num(objective.z) }
    local best_obj = nil
    local best_dist = 99999

    for _, obj in ipairs(get_visible_objects()) do
        if is_possible_gameobject(obj) and type(obj.get_position) == "function" then
            local ok_pos, pos = pcall(obj.get_position, obj)
            if ok_pos and type(pos) == "table" then
                local entry = object_entry_id(obj)
                local matched = entry_set[entry] or distance(pos, obj_center) < 5
                if matched and can_be_used(obj) then
                    local d = distance(pos, player_pos)
                    if d < best_dist then
                        best_obj = obj
                        best_dist = d
                    end
                end
            end
        end
    end

    return best_obj, best_dist
end

function ObjectiveInteractor:update(objective, player_pos, now_ms)
    if not objective or type(objective) ~= "table" then
        return "idle"
    end

    local obj_type = tostring(objective.type or "")
    if not INTERACTABLE_TYPES[obj_type] then
        return "idle"
    end

    if self:_is_eots_node(objective) then
        return "proximity"
    end

    local obj_center = { x = num(objective.x), y = num(objective.y), z = num(objective.z) }
    local dist = distance(player_pos, obj_center)

    if dist > self._interact_range then
        return "approaching"
    end

    if (now_ms - self._last_interact_ms) < self._interact_cooldown_ms then
        return "cooldown"
    end

    if self._humanization and not self._humanization:is_ready("obj_interact", 0.3, 0.8) then
        return "waiting"
    end

    local target_obj, _ = self:_find_interactable(objective, player_pos)
    if not target_obj then
        return "no_object"
    end

    local ok = use_object(target_obj)
    if ok then
        self._last_interact_ms = now_ms
        self._current_objective_id = objective.id
        if self._event_bus then
            self._event_bus:publish(Events.OBJECTIVE_INTERACTED, {
                objective_id = objective.id,
                objective_type = obj_type,
                entry_id = object_entry_id(target_obj),
            })
        end
        return "interacted"
    end

    return "failed"
end

return ObjectiveInteractor
