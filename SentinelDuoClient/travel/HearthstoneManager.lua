-- HearthstoneManager.lua — Use Hearthstone and wait for landing.

local helpers = require("lib/helpers")

---@class HearthstoneManager
local HearthstoneManager = {}
HearthstoneManager.__index = HearthstoneManager

local HS_ITEM_ID           = 6948
local HS_SPELL_ID          = 8690
local HS_CAST_DURATION_MS  = 10000
local HS_LAND_TIMEOUT_MS   = 30000

---@param blackboard table
---@param profile    table
---@return HearthstoneManager
function HearthstoneManager:new(blackboard, profile)
    return setmetatable({
        _bb               = blackboard,
        _profile          = profile,
        _state            = "idle",  -- idle | casting | landing | done | failed
        _start_ms         = 0,
        _landing_enter_ms = 0,
    }, HearthstoneManager)
end

local function find_hearthstone()
    for bag_id = 0, 4 do
        local ok, items = pcall(core.inventory.get_items_in_bag, bag_id)
        if ok and type(items) == "table" then
            for _, item in ipairs(items) do
                if item and item.object then
                    local ok_id, iid = pcall(item.object.get_item_id, item.object)
                    if ok_id and iid == HS_ITEM_ID then
                        return bag_id, item.slot_id
                    end
                end
            end
        end
    end
    return nil, nil
end

--- Begin hearthstone process. Call poll() each frame.
function HearthstoneManager:start()
    if self._state ~= "idle" then return end

    local bag_id, slot = find_hearthstone()
    if not bag_id then
        helpers.log_warn("[HS] Hearthstone not found in bags")
        self._state = "failed"
        return
    end

    local ok = select(1, pcall(core.input.use_container_item, bag_id, slot))
    if ok then
        self._state    = "casting"
        self._start_ms = helpers.game_time_ms()
        helpers.log("[HS] Hearthstone used")
    else
        self._state = "failed"
        helpers.log_err("[HS] use_item failed")
    end
end

--- Poll state. Returns "casting" | "landing" | "done" | "failed".
function HearthstoneManager:poll()
    local gt = helpers.game_time_ms()

    if self._state == "casting" then
        -- Check if cast complete (10s timer or spell no longer casting)
        local ok_pl, player = pcall(core.object_manager.get_local_player)
        local is_casting = false
        if ok_pl and player then
            local ok_c, c = pcall(player.is_casting_spell, player, HS_SPELL_ID)
            is_casting = ok_c and c == true
        end

        -- Require 2s minimum before trusting is_casting==false (game may not have
        -- registered the cast on the first few frames after use_item).
        local elapsed = gt - self._start_ms
        if elapsed >= HS_CAST_DURATION_MS or (elapsed >= 2000 and not is_casting) then
            self._state           = "landing"
            self._landing_enter_ms = gt
            helpers.log("[HS] cast complete — waiting for landing")
        end
    end

    if self._state == "landing" then
        local profile   = self._profile
        local dest_map  = profile and profile.vendor_route and profile.vendor_route.hearthstone_dest_map_id

        -- Require 3s minimum in landing state so a zone transition has time to register.
        -- Without this, a dest_map_id of 0 (Eastern Kingdoms) would match immediately
        -- since the player is already on map 0 before the HS even fires.
        local ok_map, map_id = pcall(core.get_map_id)
        local landing_elapsed = gt - self._landing_enter_ms
        if ok_map and dest_map and map_id == dest_map and landing_elapsed >= 3000 then
            self._state = "done"
            helpers.log("[HS] landed at dest map " .. map_id)
        end

        if gt - self._start_ms >= HS_CAST_DURATION_MS + HS_LAND_TIMEOUT_MS then
            self._state = "done"  -- assume arrived regardless
            helpers.log_warn("[HS] landing timeout — assuming done")
        end
    end

    return self._state
end

---@return boolean
function HearthstoneManager:is_done()
    return self._state == "done"
end

---@return boolean
function HearthstoneManager:is_failed()
    return self._state == "failed"
end

function HearthstoneManager:reset()
    self._state            = "idle"
    self._start_ms         = 0
    self._landing_enter_ms = 0
end

return HearthstoneManager
