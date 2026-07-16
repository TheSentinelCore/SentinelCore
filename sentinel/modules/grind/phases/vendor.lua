local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local JSON = require("lib/JSON")
local bag_scanner = require("modules/grind/bag_scanner")
local ConsumableIds = require("modules/grind/consumable_ids")

local Vendor = {}

local QUERY_SERVER_URL = "http://127.0.0.1:47120/api/v1/items?ids="

-- Quality constants (matches item_template.Quality)
local QUALITY_GREEN = 2

-- Default: sell grey(0) and white(1), keep green(2)+
local DEFAULT_MIN_KEEP_QUALITY = QUALITY_GREEN

-- Module-level cache for async HTTP response
local _quality_cache = nil    -- table<item_id, quality> or nil
local _quality_pending = false
local _quality_request_ms = 0
local QUALITY_TIMEOUT_MS = 5000

-- Items that should never be sold regardless of settings
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
    [5349] = true, [1113] = true, [1114] = true, [1487] = true, [8075] = true, [8076] = true, [22895] = true, -- conjured water
    [5350] = true, [1445] = true, [1708] = true, [8074] = true, [8077] = true, [22019] = true, [22893] = true, -- conjured food
    [22044] = true, -- Mana Emerald (conjured mana gem)
    [22018] = true, -- conjured mana biscuit
    -- Health potions
    [118] = true, [858] = true, [929] = true, [1710] = true, [3928] = true, [13446] = true, [22829] = true,
    -- Mana potions
    [2455] = true, [3385] = true, [3827] = true, [6149] = true, [13443] = true, [13444] = true, [22832] = true,
}

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function find_npc_by_id(npc_id)
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

local function find_vendor_slot_for_item(target_item_id)
    if not core or not core.game_ui then return nil end
    local ok_count, count = pcall(core.game_ui.get_vendor_item_count)
    if not ok_count or type(count) ~= "number" then return nil end
    for i = 1, count do
        local ok_info, info = pcall(core.game_ui.get_vendor_item_info, i)
        if ok_info and type(info) == "table" and info.item_id == target_item_id then
            return i
        end
    end
    return nil
end

local function vendor_has_service(bb, service_name)
    local vendor = bb:get("module.grind.vendor_data")
    if not vendor or not vendor.services then return false end
    for _, svc in ipairs(vendor.services) do
        if svc == service_name then return true end
    end
    return false
end

---Build the keep-set from the hardcoded NEVER_SELL plus profile vendor_settings.keep_items.
---@param bb table Blackboard
---@return table<number, boolean> Set of item_ids to never sell
local function build_keep_set(bb)
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

---Collect all unique item IDs currently in bags (excluding NEVER_SELL).
local function collect_bag_item_ids()
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

---Fire async HTTP request to query server for item quality data.
local function fetch_item_qualities(item_ids)
    if #item_ids == 0 then
        _quality_cache = {}
        _quality_pending = false
        return
    end
    local parts = {}
    for _, id in ipairs(item_ids) do
        parts[#parts + 1] = tostring(id)
    end
    local url = QUERY_SERVER_URL .. table.concat(parts, ",")
    _quality_pending = true
    _quality_cache = nil

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
                _quality_cache = cache
            else
                _quality_cache = {}
            end
        else
            _quality_cache = {}
        end
        _quality_pending = false
    end)
end

---Get min_keep_quality from blackboard (UI setting) or profile fallback.
local function get_min_keep_quality(bb)
    local ui_quality = bb:get("module.grind.vendor_sell_quality")
    if type(ui_quality) == "number" then
        return ui_quality
    end
    return DEFAULT_MIN_KEEP_QUALITY
end

-- Max items to sell per tick to avoid overwhelming the server
local SELL_BATCH_SIZE = 4

---Sell up to SELL_BATCH_SIZE bag items filtered by keep_set and quality threshold.
---Returns (sold_count, has_more) — caller should re-invoke if has_more is true.
local function sell_filtered_bag_items(keep_set, min_keep_quality)
    if not core or not core.input then return 0, false end
    local sold = 0
    local has_more = false
    bag_scanner.for_each_item(function(obj, bag, bag_slot)
        if sold >= SELL_BATCH_SIZE then
            has_more = true
            return -- skip remaining this tick
        end
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if ok_id and raw_id then
            local item_id = tonumber(raw_id) or raw_id
            if not keep_set[item_id] then
                -- Check quality from cache; if unknown, keep the item (safe default)
                local quality = _quality_cache and _quality_cache[item_id]
                if quality and quality < min_keep_quality then
                    pcall(core.input.use_container_item, bag, bag_slot)
                    sold = sold + 1
                end
            end
        end
    end)
    return sold, has_more
end

---Build the vendor phase sub-tree.
---@param blackboard table Blackboard instance
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Vendor.build(blackboard, event_bus, nav_adapter)
    return BT.sequence("vendor_run", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: combat module must not be actively engaged
        BT.condition("not_engaged", function(bb)
            return bb:get("combat.source") == nil
        end),

        -- Gate: needs vendor visit (bags full, needs repair, needs food/water)
        BT.condition("needs_vendor", function(bb)
            local free = bb:get("module.grind.bag_free_slots", 99)
            if free <= 2 then return true end
            if bb:get("module.grind.needs_repair") == true then return true end
            -- Check if food/water vendor exists in profile before triggering
            local pm = bb:get("module.grind.profile_manager")
            if pm then
                local player_pos = bb:get("player.position")
                if player_pos then
                    if bb:get("module.grind.needs_food") and pm:get_nearest_vendor(player_pos, "food") then
                        return true
                    end
                    if bb:get("module.grind.needs_water") and pm:get_nearest_vendor(player_pos, "water") then
                        return true
                    end
                end
            end
            return false
        end),

        -- Stateful vendor action: navigate → interact → sell → done
        BT.action("vendor_action", function(bb)
            local state = bb:get("module.grind.vendor_state") or "init"

            -- Abort if combat module engaged
            if bb:get("combat.source") ~= nil then
                bb:set("module.grind.vendor_state", nil)
                bb:set("module.grind.vendor_retries", nil)
                _quality_cache = nil
                _quality_pending = false
                nav_adapter:stop("vendor_abort_combat")
                return Status.FAILURE
            end

            if state == "init" then
                local player_pos = bb:get("player.position")
                local pm = bb:get("module.grind.profile_manager")
                if not pm or not player_pos then
                    return Status.FAILURE
                end

                -- Find best vendor: prefer one that covers the most needed services
                local sell_vendor = pm:get_nearest_vendor(player_pos, "sell")
                local repair_vendor = bb:get("module.grind.needs_repair") and pm:get_nearest_vendor(player_pos, "repair")
                local food_vendor = (bb:get("module.grind.needs_food") or bb:get("module.grind.needs_water")) and pm:get_nearest_vendor(player_pos, "food")

                -- Use sell vendor as primary (frees bag space first), fall back to repair or food
                local vendor = sell_vendor or repair_vendor or food_vendor
                if not vendor then
                    return Status.FAILURE
                end
                bb:set("module.grind.vendor_data", vendor)
                bb:set("module.grind.vendor_state", "traveling")
                return Status.RUNNING
            end

            if state == "traveling" then
                local vendor = bb:get("module.grind.vendor_data")
                if not vendor then
                    bb:set("module.grind.vendor_state", nil)
                    return Status.FAILURE
                end
                local vendor_pos = { x = vendor.x, y = vendor.y, z = vendor.z }
                local player_pos = bb:get("player.position")
                local dist = distance_3d(player_pos, vendor_pos)

                if dist <= 5 then
                    nav_adapter:stop("vendor_arrived")
                    bb:set("module.grind.vendor_state", "interacting")
                    return Status.RUNNING
                end

                -- Stuck detection during vendor travel
                local stuck = bb:get("module.grind.stuck_detector")
                if stuck and player_pos then
                    local now = bb:get("system.now_ms", 0)
                    stuck:sample(now, player_pos, "vendor_travel")
                    if stuck:is_stuck() then
                        nav_adapter:stop("vendor_travel_stuck")
                        stuck:reset()
                        bb:set("module.grind.vendor_state", nil)
                        bb:set("module.grind.vendor_data", nil)
                        return Status.FAILURE
                    end
                end

                if not nav_adapter:is_active() then
                    nav_adapter:move_to(vendor_pos)
                end
                return Status.RUNNING
            end

            if state == "interacting" then
                local vendor = bb:get("module.grind.vendor_data")
                if not vendor then
                    bb:set("module.grind.vendor_state", nil)
                    return Status.FAILURE
                end

                -- Check if vendor window is already open
                local ok_count, v_count = pcall(core.game_ui.get_vendor_item_count)
                if ok_count and (v_count or 0) > 0 then
                    bb:set("module.grind.vendor_state", "repairing")
                    return Status.RUNNING
                end

                -- Find the vendor NPC and interact
                local npc = find_npc_by_id(vendor.npc_id)
                if not npc then
                    bb:set("module.grind.vendor_state", nil)
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

                -- Give time for vendor window to open
                local now = bb:get("system.now_ms", 0)
                bb:set("module.grind.vendor_interact_at", now)
                bb:set("module.grind.vendor_state", "waiting_window")
                return Status.RUNNING
            end

            if state == "waiting_window" then
                local ok_count, v_count = pcall(core.game_ui.get_vendor_item_count)
                if ok_count and (v_count or 0) > 0 then
                    bb:set("module.grind.vendor_retries", nil)
                    bb:set("module.grind.vendor_state", "repairing")
                    return Status.RUNNING
                end

                -- Timeout: retry interact after 2 seconds, abort after 3 failed attempts
                local now = bb:get("system.now_ms", 0)
                local interact_at = bb:get("module.grind.vendor_interact_at", 0)
                if now - interact_at > 2000 then
                    local retries = bb:get("module.grind.vendor_retries", 0)
                    if retries >= 3 then
                        bb:set("module.grind.vendor_state", nil)
                        bb:set("module.grind.vendor_retries", nil)
                        bb:set("module.grind.vendor_data", nil)
                        bb:set("module.grind.vendor_interact_at", nil)
                        return Status.FAILURE
                    end
                    bb:set("module.grind.vendor_retries", retries + 1)
                    bb:set("module.grind.vendor_state", "interacting")
                end
                return Status.RUNNING
            end

            if state == "repairing" then
                if not vendor_has_service(bb, "repair") or bb:get("module.grind.needs_repair") ~= true then
                    -- Skip selling if bags aren't full (repair-only visit)
                    local free = bb:get("module.grind.bag_free_slots", 999)
                    local next_state = free <= 2 and "selling" or "buying_food"
                    bb:set("module.grind.vendor_state", next_state)
                    return Status.RUNNING
                end
                if core and core.input and type(core.input.repair_all_items) == "function" then
                    pcall(core.input.repair_all_items, false) -- false = don't use guild bank
                end
                -- Reset durability tracker so it re-samples immediately after repair
                local dt = bb:get("module.grind.durability_tracker")
                if dt then dt:reset() end
                -- Skip selling if bags aren't full (repair-only visit)
                local free = bb:get("module.grind.bag_free_slots", 999)
                local next_state = free <= 2 and "selling" or "buying_food"
                bb:set("module.grind.vendor_state", next_state)
                return Status.RUNNING
            end

            if state == "selling" then
                -- Reset stale cache from any previous interrupted vendor visit
                _quality_cache = nil
                _quality_pending = false
                -- Collect bag item IDs and fetch quality data from query server
                local item_ids = collect_bag_item_ids()
                _quality_request_ms = bb:get("system.now_ms", 0)
                fetch_item_qualities(item_ids)
                bb:set("module.grind.vendor_state", "selling_wait")
                return Status.RUNNING
            end

            if state == "selling_wait" then
                -- Wait for async HTTP response (with timeout)
                if _quality_pending then
                    local now = bb:get("system.now_ms", 0)
                    if now - _quality_request_ms > QUALITY_TIMEOUT_MS then
                        _quality_pending = false
                        _quality_cache = {}
                    end
                    return Status.RUNNING
                end
                -- Quality data arrived (or failed — sell_filtered handles nil cache safely)
                local keep_set = build_keep_set(bb)
                local min_quality = get_min_keep_quality(bb)
                local _, has_more = sell_filtered_bag_items(keep_set, min_quality)
                if has_more then
                    return Status.RUNNING -- continue selling next tick
                end
                bb:set("module.grind.vendor_state", "buying_food")
                bb:set("module.grind.current_target", nil)
                return Status.RUNNING
            end

            if state == "buying_food" then
                if not vendor_has_service(bb, "food") or not bb:get("module.grind.needs_food") then
                    bb:set("module.grind.vendor_state", "buying_water")
                    return Status.RUNNING
                end
                local player = bb:get("player.object")
                local player_level = 1
                if player and type(player.get_level) == "function" then
                    local ok, lv = pcall(player.get_level, player)
                    if ok and type(lv) == "number" then player_level = lv end
                end
                local food_id = ConsumableIds.resolve_for_level(ConsumableIds.VENDOR_FOOD, player_level)
                if food_id then
                    local buy_count = 40 - (bb:get("module.grind.food_count", 0))
                    if buy_count > 0 then
                        local slot = find_vendor_slot_for_item(food_id)
                        if slot and core and core.input then
                            pcall(core.input.buy_item, slot, buy_count)
                        end
                    end
                end
                bb:set("module.grind.vendor_state", "buying_water")
                return Status.RUNNING
            end

            if state == "buying_water" then
                if not vendor_has_service(bb, "food") or not bb:get("module.grind.needs_water") then
                    bb:set("module.grind.vendor_state", "done")
                    return Status.RUNNING
                end
                local player = bb:get("player.object")
                local player_level = 1
                if player and type(player.get_level) == "function" then
                    local ok, lv = pcall(player.get_level, player)
                    if ok and type(lv) == "number" then player_level = lv end
                end
                local water_id = ConsumableIds.resolve_for_level(ConsumableIds.VENDOR_WATER, player_level)
                if water_id then
                    local buy_count = 40 - (bb:get("module.grind.water_count", 0))
                    if buy_count > 0 then
                        local slot = find_vendor_slot_for_item(water_id)
                        if slot and core and core.input then
                            pcall(core.input.buy_item, slot, buy_count)
                        end
                    end
                end
                bb:set("module.grind.vendor_state", "done")
                return Status.RUNNING
            end

            if state == "done" then
                -- Close vendor window before walking away
                if core and core.input and type(core.input.close_vendor) == "function" then
                    pcall(core.input.close_vendor)
                end
                -- Clean up vendor state
                bb:set("module.grind.vendor_state", nil)
                bb:set("module.grind.vendor_data", nil)
                bb:set("module.grind.vendor_interact_at", nil)
                bb:set("module.grind.vendor_retries", nil)
                event_bus:publish("grind:vendor_complete", {})
                return Status.SUCCESS
            end

            -- Unknown state, reset
            bb:set("module.grind.vendor_state", nil)
            return Status.FAILURE
        end),
    })
end

return Vendor
