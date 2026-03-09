local MountController = {}
MountController.__index = MountController

-- ---------------------------------------------------------------------------
-- constants
-- ---------------------------------------------------------------------------
local MOUNT_THRESHOLD      = 40   -- min distance (yd) to destination before mounting
local DISMOUNT_DISTANCE    = 30   -- distance (yd) to destination that triggers dismount
local THREAT_SCAN_RADIUS   = 35   -- radius (yd) for smart combat dismount scan

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function distance_3d(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return 99999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function safe_call(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

local function safe_method(owner, method, ...)
    if not owner or type(owner[method]) ~= "function" then return false, nil end
    return pcall(owner[method], owner, ...)
end

-- ---------------------------------------------------------------------------
-- constructor
-- ---------------------------------------------------------------------------

---Create a new MountController.
---@return table
function MountController:new()
    local o = setmetatable({}, self)
    o._mounting     = false
    o._destination  = nil
    return o
end

-- ---------------------------------------------------------------------------
-- queries
-- ---------------------------------------------------------------------------

---Check all mount conditions.
---@param bb table  blackboard
---@param destination table  {x,y,z}
---@return boolean
function MountController:should_mount(bb, destination)
    -- Must have a player object
    local player = bb:get("player.object")
    if not player then return false end

    -- Not dead or ghost
    if bb:get("player.is_dead", false) == true then return false end
    if bb:get("player.is_ghost", false) == true then return false end

    -- No combat
    if bb:get("combat.source") ~= nil then return false end

    -- Must be outdoors
    if bb:get("player.is_outdoors", true) ~= true then return false end

    -- Not already mounted
    local ok, mounted = safe_method(player, "is_mounted")
    if ok and mounted == true then return false end

    -- Distance check
    local ok_pos, pos = safe_method(player, "get_position")
    if not ok_pos or type(pos) ~= "table" then return false end
    if distance_3d(pos, destination) < MOUNT_THRESHOLD then return false end

    return true
end

---Check dismount triggers (ANY fires).
---@param bb table  blackboard
---@return boolean
function MountController:should_dismount(bb)
    -- Combat engaged
    if bb:get("combat.source") ~= nil then return true end

    -- Near destination
    if self._destination then
        local player = bb:get("player.object")
        if player then
            local ok_pos, pos = safe_method(player, "get_position")
            if ok_pos and type(pos) == "table" then
                if distance_3d(pos, self._destination) < DISMOUNT_DISTANCE then
                    return true
                end
            end
        end
    end

    return false
end

---Scan nearby hostiles for smart combat dismount.
---Returns true if a hostile NPC within THREAT_SCAN_RADIUS is targeting the player.
---@param bb table  blackboard
---@param hostiles table|nil  array of hostile game_objects (caller provides)
---@return boolean
function MountController:should_smart_dismount(bb, hostiles)
    local player = bb:get("player.object")
    if not player then return false end

    -- Must be mounted
    local ok_m, mounted = safe_method(player, "is_mounted")
    if not ok_m or mounted ~= true then return false end

    if type(hostiles) ~= "table" then return false end

    local ok_pos, player_pos = safe_method(player, "get_position")
    if not ok_pos or type(player_pos) ~= "table" then return false end

    for _, hostile in ipairs(hostiles) do
        local ok_hp, hpos = safe_method(hostile, "get_position")
        if ok_hp and type(hpos) == "table" and distance_3d(player_pos, hpos) <= THREAT_SCAN_RADIUS then
            local ok_t, target = safe_method(hostile, "get_target")
            if ok_t and target == player then
                return true
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- actions
-- ---------------------------------------------------------------------------

---Attempt to find and use a usable mount from the spell book.
---@return boolean  true if mount command was dispatched
local function dispatch_mount()
    if not core or not core.spell_book or not core.input then return false end

    local ok_count, count = safe_call(core.spell_book.get_mount_count)
    if not ok_count or type(count) ~= "number" or count <= 0 then return false end

    for i = 1, count do
        local ok_info, info = safe_call(core.spell_book.get_mount_info, i)
        if ok_info and type(info) == "table" and info.is_usable then
            local ok_mount = safe_call(core.input.mount, i)
            return ok_mount
        end
    end

    return false
end

---Mount if conditions are met, store destination.
---@param bb table  blackboard
---@param destination table  {x,y,z}
function MountController:begin_travel(bb, destination)
    self._destination = destination
    if not self:should_mount(bb, destination) then
        self._mounting = false
        return
    end
    local ok = dispatch_mount()
    self._mounting = ok
end

---Tick every frame: check dismount triggers and clear state when needed.
---@param bb table  blackboard
function MountController:update(bb)
    if not self._mounting then return end

    if self:should_dismount(bb) then
        if core and core.input and type(core.input.dismount) == "function" then
            pcall(core.input.dismount)
        end
        self:clear()
    end
end

---Query whether a mount attempt is in progress.
---@return boolean
function MountController:is_mounting()
    return self._mounting == true
end

---Reset all state.
function MountController:clear()
    self._mounting    = false
    self._destination = nil
end

return MountController
