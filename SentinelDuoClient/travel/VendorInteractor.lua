-- VendorInteractor.lua — Navigate to vendor, sell all non-protected items, repair.

local helpers = require("lib/helpers")

---@class VendorInteractor
local VendorInteractor = {}
VendorInteractor.__index = VendorInteractor

-- Items to never sell
local PROTECTED_ITEMS = { [12382] = true, [6948] = true }

local SELL_DELAY_BASE = 200
local SELL_DELAY_VAR  = 300

---@param duo_nav   table  DuoNav
---@param blackboard table Blackboard
---@param profile   table
---@return VendorInteractor
function VendorInteractor:new(duo_nav, blackboard, profile)
    return setmetatable({
        _nav          = duo_nav,
        _bb           = blackboard,
        _profile      = profile,
        _state        = "idle",  -- idle | traveling | interacting | selling | done | failed
        _start_ms     = 0,
        _last_sell_ms = 0,
        _sell_delay   = 0,  -- jittered delay computed once when entering selling state
    }, VendorInteractor)
end

local function find_vendor_npc(vendor_npc_id)
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return nil end
    for _, obj in ipairs(objects) do
        local ok_id, npc_id = pcall(obj.get_npc_id, obj)
        if ok_id and npc_id == vendor_npc_id then
            return obj
        end
    end
    return nil
end

--- Start vendor interaction process. Call poll() each frame.
function VendorInteractor:start()
    if self._state ~= "idle" then return end
    self._state    = "traveling"
    self._start_ms = helpers.game_time_ms()

    local route = self._profile and self._profile.vendor_route
    if route and route.vendor_position then
        self._nav:move_to(route.vendor_position)
        helpers.log("[Vendor] navigating to vendor")
    else
        helpers.log_warn("[Vendor] no vendor_position in profile")
        self._state = "failed"
    end
end

--- Poll state. Returns current state string.
function VendorInteractor:poll()
    local gt    = helpers.game_time_ms()
    local route = self._profile and self._profile.vendor_route

    if self._state == "traveling" then
        if self._nav:is_arrived(5.0) then
            self._state = "interacting"
            self._nav:stop("at_vendor")
            helpers.log("[Vendor] arrived at vendor")
        end
        -- Timeout
        if gt - self._start_ms > 60000 then
            self._state = "failed"
            helpers.log_err("[Vendor] travel timeout")
        end
    end

    if self._state == "interacting" then
        local npc_id = route and route.vendor_npc_id
        if npc_id and npc_id ~= 0 then
            local npc = find_vendor_npc(npc_id)
            if npc then
                pcall(core.input.interact_with_object, npc)
                self._state        = "selling"
                self._last_sell_ms = gt
                -- Compute jitter delay once here — not per-frame (per-frame jitter
                -- produces a threshold that changes every tick, making the check unreliable).
                self._sell_delay   = helpers.jitter(SELL_DELAY_BASE, 0.5)
                helpers.log("[Vendor] vendor window opened")
            else
                helpers.log_warn("[Vendor] vendor NPC not found")
                -- Try again next frame
            end
        else
            self._state      = "selling"  -- skip if no NPC ID configured
            self._sell_delay = helpers.jitter(SELL_DELAY_BASE, 0.5)
        end
    end

    if self._state == "selling" then
        if gt - self._last_sell_ms < self._sell_delay then
            return self._state
        end
        self._last_sell_ms = gt

        -- Sell all non-protected items (use_container_item while vendor window is open = sell)
        local sold_any = false
        for bag_id = 0, 4 do
            local ok, items = pcall(core.inventory.get_items_in_bag, bag_id)
            if ok and type(items) == "table" then
                for _, item in ipairs(items) do
                    if item and item.object then
                        local ok_id, iid = pcall(item.object.get_item_id, item.object)
                        if ok_id and iid and not PROTECTED_ITEMS[iid] then
                            pcall(core.input.use_container_item, bag_id, item.slot_id)
                            sold_any = true
                        end
                    end
                end
            end
        end

        -- Repair if configured
        if route and route.repair_at_vendor then
            pcall(core.input.repair_all_items, false)
            helpers.log("[Vendor] repair requested")
        end

        self._state = "done"
        helpers.log("[Vendor] selling complete")
    end

    return self._state
end

---@return boolean
function VendorInteractor:is_done()
    return self._state == "done"
end

function VendorInteractor:reset()
    self._state      = "idle"
    self._start_ms   = 0
    self._sell_delay = 0
end

return VendorInteractor
