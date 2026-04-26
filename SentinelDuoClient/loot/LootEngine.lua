-- LootEngine.lua — Scan for and loot corpses in an area.

local helpers = require("lib/helpers")

---@class LootEngine
local LootEngine = {}
LootEngine.__index = LootEngine

local NAV_ARRIVE_RANGE = 4.0
local CORPSE_TIMEOUT_MS = 5000
local LOOT_SLOT_DELAY_BASE = 150
local LOOT_SLOT_DELAY_VAR  = 200

-- Protected item IDs — never sell/skip interaction
local PROTECTED = { [12382] = true, [6948] = true }

---@param duo_nav   table  DuoNav
---@param blackboard table  Blackboard
---@return LootEngine
function LootEngine:new(duo_nav, blackboard)
    return setmetatable({
        _nav          = duo_nav,
        _bb           = blackboard,
        _queue        = {},   -- corpses to loot
        _current      = nil,  -- current corpse being looted
        _corpse_start = 0,
        _complete     = false,
        _slot_timer   = 0,
    }, LootEngine)
end

local function get_lootable_corpses(center, radius)
    local result = {}
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return result end

    for _, obj in ipairs(objects) do
        -- Filter: dead, can be looted
        local ok_dead, is_dead = pcall(obj.is_dead, obj)
        if ok_dead and is_dead then
            local ok_loot, can_loot = pcall(obj.can_be_looted, obj)
            if not ok_loot then
                local ok2, cl2 = pcall(obj.is_glow, obj)
                can_loot = ok2 and cl2
            end
            if can_loot then
                local ok_pos, pos = pcall(obj.get_position, obj)
                if ok_pos and pos then
                    local dx = (pos.x or 0) - (center.x or 0)
                    local dy = (pos.y or 0) - (center.y or 0)
                    local dz = (pos.z or 0) - (center.z or 0)
                    if math.sqrt(dx*dx + dy*dy + dz*dz) <= radius then
                        table.insert(result, obj)
                    end
                end
            end
        end
    end
    return result
end

--- Start looting all corpses in area. Non-blocking — call is_complete() each frame.
---@param center table  vec3
---@param radius number
function LootEngine:loot_all_in_area(center, radius)
    self._queue    = get_lootable_corpses(center, radius)
    self._current  = nil
    self._complete = #self._queue == 0
    helpers.log("[Loot] found " .. #self._queue .. " lootable corpses")
end

--- Poll loot progress. Must be called every frame while looting.
function LootEngine:poll()
    if self._complete then return end

    local gt = helpers.game_time_ms()

    -- If no current corpse, grab next from queue
    if not self._current then
        if #self._queue == 0 then
            self._complete = true
            return
        end
        self._current = table.remove(self._queue, 1)
        self._corpse_start = gt

        -- Navigate to corpse
        local ok_pos, pos = pcall(self._current.get_position, self._current)
        if ok_pos and pos then
            self._nav:move_to(pos)
        end
        return
    end

    -- Timeout this corpse
    if gt - self._corpse_start > CORPSE_TIMEOUT_MS then
        helpers.log_warn("[Loot] corpse timeout — skipping")
        self._current = nil
        return
    end

    -- Wait until arrived
    if not self._nav:is_arrived(NAV_ARRIVE_RANGE) then return end

    -- Interact with corpse
    if gt - self._slot_timer < LOOT_SLOT_DELAY_BASE then return end

    local ok_interact, err = pcall(core.input.interact_with_object, self._current)
    if not ok_interact then
        helpers.log_warn("[Loot] interact error: " .. tostring(err))
        self._current = nil
        return
    end

    -- Loot all slots (assume 4 slots max)
    self._slot_timer = gt
    for slot = 1, 4 do
        local delay = helpers.jitter(LOOT_SLOT_DELAY_BASE, 0.5) * (slot - 1)
        -- Jitter-delayed loot calls — fire serially with pcall
        local ok_loot = select(1, pcall(core.input.loot_item, slot))
        if not ok_loot then break end
    end

    self._current = nil  -- done with this corpse
end

---@return boolean
function LootEngine:is_complete()
    return self._complete
end

return LootEngine
