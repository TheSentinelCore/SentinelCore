local JSON = require("lib/JSON")
local Status = require("core/bt/status")
local Geometry = require("core/geometry")
local bag_scanner = require("modules/grind/bag_scanner")
local ConsumableIds = require("modules/grind/consumable_ids")

local VendorStateMachine = {}
VendorStateMachine.__index = VendorStateMachine

local QUERY_SERVER_URL = "http://127.0.0.1:47120/api/v1/items?ids="

-- Quality constants (matches item_template.Quality)
local QUALITY_GREEN = 2
local DEFAULT_MIN_KEEP_QUALITY = QUALITY_GREEN
local SELL_BATCH_SIZE = 4
local QUALITY_TIMEOUT_MS = 5000

-- Items that should never be sold
local NEVER_SELL = {
    [6948] = true,  -- Hearthstone
    [6265] = true,  -- Soul Shard
    [5060] = true,  -- Thieves' Tools
    [15138] = true, -- Onyxia Scale Cloak
    [17031] = true, -- Rune of Teleportation
    [17032] = true, -- Rune of Portals
    [17020] = true, -- Arcane Powder
    [17021] = true, -- Symbol of Divinity
    [17028] = true, -- Holy Candle
    [17029] = true, -- Sacred Candle
    [17033] = true, -- Symbol of Kings
    [21177] = true, -- Symbol of Kings
    [5565] = true,  -- Infernal Stone
    [16583] = true, -- Demonic Figurine
    -- Mage conjured food/water (all ranks)
    [5349] = true, [1113] = true, [1114] = true, [1487] = true, [8075] = true, [8076] = true, [22895] = true,
    [5350] = true, [1445] = true, [1708] = true, [8074] = true, [8077] = true, [22019] = true, [22893] = true,
    [22044] = true, -- Mana Emerald
    [22018] = true, -- conjured mana biscuit
    -- Health potions
    [118] = true, [858] = true, [929] = true, [1710] = true, [3928] = true, [13446] = true, [22829] = true,
    -- Mana potions
    [2455] = true, [3385] = true, [3827] = true, [6149] = true, [13443] = true, [13444] = true, [22832] = true,
}

function VendorStateMachine:new(event_bus, nav_adapter)
    return setmetatable({
        _event_bus = event_bus,
        _nav_adapter = nav_adapter,
        _state = nil,
        _vendor_data = nil,
        _retries = 0,
        _interact_at_ms = 0,
        _quality_cache = nil,
        _quality_pending = false,
        _quality_request_ms = 0,
    }, self)
end

function VendorStateMachine:reset()
    self._state = nil
    self._vendor_data = nil
    self._retries = 0
    self._interact_at_ms = 0
    self._quality_cache = nil
    self._quality_pending = false
    self._quality_request_ms = 0
end

function VendorStateMachine:is_running()
    return self._state ~= nil
end

function VendorStateMachine:tick(bb)
    -- Abort if combat module engaged
    if bb:get("combat.source") ~= nil then
        self:reset()
        self._nav_adapter:stop("vendor_abort_combat")
        return Status.FAILURE
    end

    if not self._state then
        return self:_state_init(bb)
    elseif self._state == "traveling" then
        return self:_state_traveling(bb)
    elseif self._state == "interacting" then
        return self:_state_interacting(bb)
    elseif self._state == "waiting_window" then
        return self:_state_waiting_window(bb)
    elseif self._state == "repairing" then
        return self:_state_repairing(bb)
    elseif self._state == "selling" then
        return self:_state_selling(bb)
    elseif self._state == "selling_wait" then
        return self:_state_selling_wait(bb)
    elseif self._state == "buying_food" then
        return self:_state_buying_food(bb)
    elseif self._state == "buying_water" then
        return self:_state_buying_water(bb)
    elseif self._state == "done" then
        return self:_state_done(bb)
    end

    self:reset()
    return Status.FAILURE
end

-- ---------------------------------------------------------------------------
-- State implementations
-- ---------------------------------------------------------------------------

function VendorStateMachine:_state_init(bb)
    local player_pos = bb:get("player.position")
    local pm = bb:get("module.grind.profile_manager")
    if not pm or not player_pos then
        return Status.FAILURE
    end

    local sell_vendor = pm:get_nearest_vendor(player_pos, "sell")
    local repair_vendor = bb:get("module.grind.needs_repair") and pm:get_nearest_vendor(player_pos, "repair")
    local food_vendor = (bb:get("module.grind.needs_food") or bb:get("module.grind.needs_water"))
        and pm:get_nearest_vendor(player_pos, "food")

    local vendor = sell_vendor or repair_vendor or food_vendor
    if not vendor then
        return Status.FAILURE
    end

    self._vendor_data = vendor
    self._state = "traveling"
    return Status.RUNNING
end

function VendorStateMachine:_state_traveling(bb)
    if not self._vendor_data then
        self:reset()
        return Status.FAILURE
    end

    local vendor_pos = { x = self._vendor_data.x, y = self._vendor_data.y, z = self._vendor_data.z }
    local player_pos = bb:get("player.position")
    local dist = Geometry.distance(player_pos, vendor_pos)

    if dist <= 5 then
        self._nav_adapter:stop("vendor_arrived")
        self._state = "interacting"
        return Status.RUNNING
    end

    -- Stuck detection
    local stuck = bb:get("module.grind.stuck_detector")
    if stuck and player_pos then
        local now = bb:get("system.now_ms", 0)
        stuck:sample(now, player_pos, "vendor_travel")
        if stuck:is_stuck() then
            self._nav_adapter:stop("vendor_travel_stuck")
            stuck:reset()
            self:reset()
            return Status.FAILURE
        end
    end

    if not self._nav_adapter:is_active() then
        self._nav_adapter:move_to(vendor_pos)
    end
    return Status.RUNNING
end

function VendorStateMachine:_state_interacting(bb)
    if not self._vendor_data then
        self:reset()
        return Status.FAILURE
    end

    -- Check if vendor window is already open
    if self:_vendor_window_open() then
        self._state = "repairing"
        return Status.RUNNING
    end

    local npc = self:_find_npc(self._vendor_data.npc_id)
    if not npc then
        self:reset()
        return Status.FAILURE
    end

    if core and core.input then
        if core.input.set_target then
            pcall(core.input.set_target, npc)
        end
        if core.input.interact_with_object then
            pcall(core.input.interact_with_object, npc)
        end
    end

    self._interact_at_ms = bb:get("system.now_ms", 0)
    self._state = "waiting_window"
    return Status.RUNNING
end

function VendorStateMachine:_state_waiting_window(bb)
    if self:_vendor_window_open() then
        self._retries = 0
        self._state = "repairing"
        return Status.RUNNING
    end

    local now = bb:get("system.now_ms", 0)
    if now - self._interact_at_ms > 2000 then
        self._retries = self._retries + 1
        if self._retries >= 3 then
            self:reset()
            return Status.FAILURE
        end
        self._state = "interacting"
    end
    return Status.RUNNING
end

function VendorStateMachine:_state_repairing(bb)
    if self:_has_service("repair") and bb:get("module.grind.needs_repair") == true then
        if core and core.input and type(core.input.repair_all_items) == "function" then
            pcall(core.input.repair_all_items, false)
        end
        local dt = bb:get("module.grind.durability_tracker")
        if dt then dt:reset() end
    end

    local free = bb:get("module.grind.bag_free_slots", 999)
    self._state = (free <= 2) and "selling" or "buying_food"
    return Status.RUNNING
end

function VendorStateMachine:_state_selling(bb)
    self._quality_cache = nil
    self._quality_pending = false
    local item_ids = self:_collect_bag_item_ids()
    self._quality_request_ms = bb:get("system.now_ms", 0)
    self:_fetch_item_qualities(item_ids)
    self._state = "selling_wait"
    return Status.RUNNING
end

function VendorStateMachine:_state_selling_wait(bb)
    if self._quality_pending then
        local now = bb:get("system.now_ms", 0)
        if now - self._quality_request_ms > QUALITY_TIMEOUT_MS then
            self._quality_pending = false
            self._quality_cache = {}
        end
        return Status.RUNNING
    end

    local keep_set = self:_build_keep_set(bb)
    local min_quality = self:_get_min_keep_quality(bb)
    local _, has_more = self:_sell_filtered_items(keep_set, min_quality)
    if has_more then
        return Status.RUNNING
    end

    self._state = "buying_food"
    return Status.RUNNING
end

function VendorStateMachine:_state_buying_food(bb)
    if not self:_has_service("food") or not bb:get("module.grind.needs_food") then
        self._state = "buying_water"
        return Status.RUNNING
    end

    local player_level = self:_get_player_level(bb)
    local food_id = ConsumableIds.resolve_for_level(ConsumableIds.VENDOR_FOOD, player_level)
    if food_id then
        local buy_count = 40 - (bb:get("module.grind.food_count", 0))
        if buy_count > 0 then
            local slot = self:_find_vendor_slot(food_id)
            if slot and core and core.input then
                pcall(core.input.buy_item, slot, buy_count)
            end
        end
    end
    self._state = "buying_water"
    return Status.RUNNING
end

function VendorStateMachine:_state_buying_water(bb)
    if not self:_has_service("food") or not bb:get("module.grind.needs_water") then
        self._state = "done"
        return Status.RUNNING
    end

    local player_level = self:_get_player_level(bb)
    local water_id = ConsumableIds.resolve_for_level(ConsumableIds.VENDOR_WATER, player_level)
    if water_id then
        local buy_count = 40 - (bb:get("module.grind.water_count", 0))
        if buy_count > 0 then
            local slot = self:_find_vendor_slot(water_id)
            if slot and core and core.input then
                pcall(core.input.buy_item, slot, buy_count)
            end
        end
    end
    self._state = "done"
    return Status.RUNNING
end

function VendorStateMachine:_state_done(bb)
    if core and core.input and type(core.input.close_vendor) == "function" then
        pcall(core.input.close_vendor)
    end
    self:reset()
    self._event_bus:publish("grind:vendor_complete", {})
    return Status.SUCCESS
end

-- ---------------------------------------------------------------------------
-- Private: Helpers
-- ---------------------------------------------------------------------------

function VendorStateMachine:_find_npc(npc_id)
    if not core or not core.object_manager then return nil end
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return nil end
    for _, obj in ipairs(objects) do
        local ok_npc, id = pcall(obj.get_npc_id, obj)
        if ok_npc and id == npc_id then
            local ok_alive, alive = pcall(obj.is_alive, obj)
            if ok_alive and alive then
                return obj
            end
        end
    end
    return nil
end

function VendorStateMachine:_vendor_window_open()
    if not core or not core.game_ui then return false end
    local ok, count = pcall(core.game_ui.get_vendor_item_count)
    return ok and (count or 0) > 0
end

function VendorStateMachine:_find_vendor_slot(item_id)
    if not core or not core.game_ui then return nil end
    local ok, count = pcall(core.game_ui.get_vendor_item_count)
    if not ok or type(count) ~= "number" then return nil end
    for i = 1, count do
        local ok_info, info = pcall(core.game_ui.get_vendor_item_info, i)
        if ok_info and type(info) == "table" and info.item_id == item_id then
            return i
        end
    end
    return nil
end

function VendorStateMachine:_has_service(service_name)
    if not self._vendor_data or not self._vendor_data.services then return false end
    for _, svc in ipairs(self._vendor_data.services) do
        if svc == service_name then return true end
    end
    return false
end

function VendorStateMachine:_get_player_level(bb)
    local player = bb:get("player.object")
    if player and type(player.get_level) == "function" then
        local ok, lv = pcall(player.get_level, player)
        if ok and type(lv) == "number" then return lv end
    end
    return 1
end

function VendorStateMachine:_build_keep_set(bb)
    local keep = {}
    for id in pairs(NEVER_SELL) do
        keep[id] = true
    end
    local pm = bb:get("module.grind.profile_manager")
    if pm then
        local profile = pm:get_active_profile()
        if profile and profile.vendor_settings and profile.vendor_settings.keep_items then
            for _, entry in ipairs(profile.vendor_settings.keep_items) do
                local item_id = type(entry) == "table" and entry.item_id or entry
                if type(item_id) == "number" then
                    keep[item_id] = true
                end
            end
        end
    end
    return keep
end

function VendorStateMachine:_get_min_keep_quality(bb)
    local ui_quality = bb:get("module.grind.vendor_sell_quality")
    if type(ui_quality) == "number" then
        return ui_quality
    end
    return DEFAULT_MIN_KEEP_QUALITY
end

function VendorStateMachine:_collect_bag_item_ids()
    local ids = {}
    local seen = {}
    bag_scanner.for_each_item(function(obj)
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if ok_id and raw_id then
            local item_id = tonumber(raw_id) or raw_id
            if not seen[item_id] then
                seen[item_id] = true
                ids[#ids + 1] = item_id
            end
        end
    end)
    return ids
end

function VendorStateMachine:_fetch_item_qualities(item_ids)
    if #item_ids == 0 then
        self._quality_cache = {}
        self._quality_pending = false
        return
    end

    local parts = {}
    for _, id in ipairs(item_ids) do
        parts[#parts + 1] = tostring(id)
    end
    local url = QUERY_SERVER_URL .. table.concat(parts, ",")
    self._quality_pending = true
    self._quality_cache = nil

    local self_ref = self
    core.http_get(url, function(code, _, response)
        if code == 200 and response then
            local ok, data = pcall(JSON.decode, response)
            if ok and data and data.items then
                local cache = {}
                for _, item in ipairs(data.items) do
                    if item.entry and item.quality then
                        cache[item.entry] = item.quality
                    end
                end
                self_ref._quality_cache = cache
            else
                self_ref._quality_cache = {}
            end
        else
            self_ref._quality_cache = {}
        end
        self_ref._quality_pending = false
    end)
end

function VendorStateMachine:_sell_filtered_items(keep_set, min_keep_quality)
    if not core or not core.input then return 0, false end
    local sold = 0
    local has_more = false
    bag_scanner.for_each_item(function(obj, bag, bag_slot)
        if sold >= SELL_BATCH_SIZE then
            has_more = true
            return
        end
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if ok_id and raw_id then
            local item_id = tonumber(raw_id) or raw_id
            if not keep_set[item_id] then
                local quality = self._quality_cache and self._quality_cache[item_id]
                if quality and quality < min_keep_quality then
                    pcall(core.input.use_container_item, bag, bag_slot)
                    sold = sold + 1
                end
            end
        end
    end)
    return sold, has_more
end

return VendorStateMachine
