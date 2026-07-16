local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local Compat = require("shared/compat")

local Loot = {}

-- Configuration (will be overridden by settings)
local LOOT_BLACKLIST_DURATION_MS = 30000
local LOOT_SCAN_THROTTLE_MS = 1000
local MIN_LOOT_QUALITY = 1  -- 0=Poor, 1=Common, 2=Uncommon, 3=Rare, 4=Epic, 5=Legendary, 6=Artifact
local DESTROY_GREY_WHEN_FULL = true
local VENDOR_WHEN_FULL = true
local AUTO_LOOT_ALL = false
local KEEP_LIST = {}      -- Item IDs to always loot regardless of quality
local DENY_LIST = {}      -- Item IDs to never loot

-- Quality names for logging/display
local QUALITY_NAMES = {
    [0] = "Poor",
    [1] = "Common", 
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Artifact"
}

---Get a stable string key for blacklist lookups (GUID preferred over userdata).
---Userdata keys become invalid when the game object is garbage collected.
---@param userdata Game object
---@return string
local function blacklist_key(unit)
    local ok_guid, guid = pcall(unit.get_guid, unit)
    if ok_guid and guid then return tostring(guid) end
    return tostring(unit)
end

---Get item quality from an item link or ID
---@param item_link_or_id string|number Item link or item ID
---@return number|nil Quality (0-6) or nil if unable to determine
local function get_item_quality(item_link_or_id)
    if not item_link_or_id then return nil end
    
    -- Try to get item info via quest API (works for items in quest log)
    local ok, quest_quests = pcall(require, "common/quests")
    if ok and quest_quests and type(quest_quests.get_item_info) == "function" then
        local ok_info, info = pcall(quest_quests.get_item_info, item_link_or_id)
        if ok_info and info and info.quality ~= nil then
            return info.quality
        end
    end
    
    -- Fallback: try to get quality from item link if it's a link
    if type(item_link_or_id) == "string" and item_link_or_id:find("item:") then
        -- Extract quality from item link format: |cffFFFFFF|Hitem:12345:0:0:0:0:0:0:0|h[item name]|h|r
        local quality_str = item_link_or_id:match("|cff%x%x%x%x%x%x|Hitem:%d+:(%d+):")
        if quality_str then
            return tonumber(quality_str)
        end
    end
    
    return nil
end

---Check if an item is a quest item
---@param item_link_or_id string|number Item link or item ID
---@return boolean True if item is a quest item
local function is_quest_item(item_link_or_id)
    if not item_link_or_id then return false end
    
    -- Check via quest API
    local ok, quest_quests = pcall(require, "common/quests")
    if ok and quest_quests and type(quest_quests.get_item_info) == "function" then
        local ok_info, info = pcall(quest_quests.get_item_info, item_link_or_id)
        if ok_info and info then
            -- Check if item has a quest ID associated with it
            if info.quest_id and info.quest_id ~= 0 then
                return true
            end
        end
        -- Check if it's in any quest log entry as a required item
        local num_entries = quest_quests.get_num_quest_log_entries and quest_quests.get_num_quest_log_entries() or 0
        if num_entries and type(num_entries) == "number" then
            for i = 1, num_entries do
                local title, level, questId, isHeader, isComplete = quest_quests.get_quest_log_title(i)
                if not isHeader then
                    local numObjectives = quest_quests.get_num_quest_leader_boards and quest_quests.get_num_quest_leader_boards(i) or 0
                    if numObjectives and type(numObjectives) == "number" then
                        for j = 1, numObjectives do
                            local objectiveText, itemType, finished = quest_quests.get_quest_log_leader_board and quest_quests.get_quest_log_leader_board(j, i) or nil
                            if objectiveText and objectiveText:match(tostring(item_link_or_id)) then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    
    return false
end

---Check if an item should be looted based on quality filters and lists
---@param item_link_or_id string|number Item link or item ID
---@param item_count number Current count of this item in inventory
---@param max_count number Maximum allowed count before considering vendor/destroy
---@return boolean, string Should loot, reason
local function should_loot_item(item_link_or_id, item_count, max_count)
    -- Never block quest items
    if is_quest_item(item_link_or_id) then
        return true, "quest_item"
    end
    
    -- Check deny list
    local item_id = type(item_link_or_id) == "number" and item_link_or_id or 
                   tonumber(item_link_or_id:match("item:(%d+)"))
    if item_id and DENY_LIST[item_id] then
        return false, "deny_listed"
    end
    
    -- Always allow items in keep list
    if item_id and KEEP_LIST[item_id] then
        return true, "keep_listed"
    end
    
    -- Check inventory limits for vendoring/destroying
    if item_count >= max_count then
        if DESTROY_GREY_WHEN_FULL then
            local quality = get_item_quality(item_link_or_id)
            if quality == 0 then  -- Poor quality
                return true, "destroy_grey_full"
            end
        end
        
        if VENDOR_WHEN_FULL then
            local quality = get_item_quality(item_link_or_id)
            if quality == 1 then  -- Common quality
                return true, "vendor_white_full"
            end
        end
        
        return false, "inventory_full"
    end
    
    -- Get item quality
    local quality = get_item_quality(item_link_or_id)
    if quality ~= nil then
        if quality < MIN_LOOT_QUALITY then
            return false, "quality_too_low"
        end
        return true, "quality_acceptable"
    end
    
    -- If we can't determine quality, err on the side of looting
    return true, "quality_unknown"
end

---Scan nearby dead units for a lootable corpse, returning the first found.
---Now includes quality-based filtering.
---@param player_pos table { x, y, z }
---@param blacklist table<string, number> guid_string→expiry_ms blacklist
---@param now_ms number current time
---@return table|nil result { unit, dist } or nil
local function find_first_lootable(player_pos, blacklist, now_ms)
    if not core or not core.object_manager then return nil end
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return nil end

    local px, py, pz = player_pos.x or 0, player_pos.y or 0, player_pos.z or 0
    for _, obj in ipairs(objects) do
        local key = blacklist_key(obj)
        local bl_expiry = blacklist[key]
        if bl_expiry and now_ms < bl_expiry then
            -- still blacklisted, skip
        else
            if bl_expiry then blacklist[key] = nil end

            local ok_dead, is_dead = pcall(obj.is_dead, obj)
            local ok_loot, can_loot = pcall(obj.can_be_looted, obj)
            if (ok_dead and is_dead) and (ok_loot and can_loot) then
                local ok_pos, pos = pcall(obj.get_position, obj)
                if ok_pos and type(pos) == "table" then
                    local dx = (pos.x or 0) - px
                    local dy = (pos.y or 0) - py
                    local dz = (pos.z or 0) - pz
                    local dist_sq = dx * dx + dy * dy + dz * dz
                    if dist_sq <= 2500 then -- 50^2 = 2500
                        -- Additional check: see if we can get item info for loot filtering
                        -- For now, we'll allow the loot and apply filtering when actually looting
                        -- This avoids complexity of checking every item on every corpse during scan
                        return { unit = obj, dist = math.sqrt(dist_sq) }
                    end
                end
            end
        end
    end
    return nil
end

---Build the loot phase sub-tree.
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Loot.build(event_bus, nav_adapter)
    local loot_blacklist = {}

    return BT.sequence("loot_nearby", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Don't loot while combat module is actively engaged (prevents nav
        -- conflict with chase controller). Looting is still allowed during
        -- post-kill combat linger because combat.source is cleared on disengage.
        BT.condition("not_engaged", function(bb)
            return bb:get("combat.source") == nil
        end),

        -- Scan for lootable corpses nearby (throttled to 1000ms, short-circuits on first find)
        BT.condition("has_lootable_nearby", function(bb)
            local now = bb:get("system.now_ms", 0)
            local last_scan = bb:get("module.grind.last_loot_scan_ms", 0)

            -- Use cached result if within throttle window
            if now - last_scan < LOOT_SCAN_THROTTLE_MS then
                return bb:get("module.grind.has_lootable", false)
            end

            bb:set("module.grind.last_loot_scan_ms", now)
            local player_pos = bb:get("player.position")
            local result = find_first_lootable(player_pos, loot_blacklist, now)

            if result then
                local new_target = result.unit
                local old_target = bb:get("module.grind.loot_target")
                if new_target ~= old_target then
                    bb:set("module.grind.loot_attempt", nil)
                    bb:set("module.grind.loot_until", nil)
                end
                bb:set("module.grind.loot_target", new_target)
                bb:set("module.grind.has_lootable", true)
                if core and core.log then
                    pcall(core.log, string.format("[Loot] found lootable, dist=%.1f", result.dist))
                end
                return true
            end

            bb:set("module.grind.has_lootable", false)
            return false
        end),

        -- Move to the lootable corpse
        BT.action("move_to_corpse", function(bb)
            -- Re-check engagement (Sequence _running_index skips the gate condition)
            if bb:get("combat.source") ~= nil then
                return Status.FAILURE
            end
            if bb:get("module.grind.is_resting") == true then
                return Status.FAILURE
            end

            local target = bb:get("module.grind.loot_target")
            if not target then return Status.FAILURE end

            local ok_pos, target_pos = pcall(target.get_position, target)
            if not ok_pos or type(target_pos) ~= "table" then
                return Status.FAILURE
            end

            local player_pos = bb:get("player.position")
            if player_pos and Compat.dist(player_pos, target_pos) <= 5 then
                return Status.SUCCESS
            end

            -- Stuck detection while moving to corpse
            local stuck = bb:get("module.grind.stuck_detector")
            if stuck and player_pos then
                local now = bb:get("system.now_ms", 0)
                stuck:sample(now, player_pos, "loot")
                if stuck:is_stuck() then
                    nav_adapter:stop("loot_stuck")
                    stuck:reset()
                    event_bus:publish("grind:stuck_recovery", { phase = "loot" })
                    -- Blacklist this corpse so we try the next one
                    loot_blacklist[blacklist_key(target)] = (bb:get("system.now_ms", 0)) + LOOT_BLACKLIST_DURATION_MS
                    bb:set("module.grind.loot_target", nil)
                    return Status.FAILURE
                end
            end

            if not nav_adapter:is_active() then
                nav_adapter:move_to(target_pos)
            end
            return Status.RUNNING
        end),

        -- Loot the corpse with retry pattern (up to 3 attempts, 500ms between)
        -- Now includes quality-based filtering
        BT.action("loot_corpse", function(bb)
            local target = bb:get("module.grind.loot_target")
            if not target then
                bb:set("module.grind.is_looting", false)
                return Status.FAILURE
            end

            -- Re-check engagement (Sequence _running_index skips gate conditions).
            -- Only abort when the combat module is actively fighting (combat.source).
            -- player.in_combat is NOT checked here because WoW's combat timer
            -- lingers 5-6s after a kill and would block all looting.
            -- The combat module's is_looting gate (modified to allow when in_combat)
            -- handles defensive engagement if a mob attacks during loot.
            if bb:get("combat.source") ~= nil then
                bb:set("module.grind.is_looting", false)
                return Status.FAILURE
            end
            if bb:get("module.grind.is_resting") == true then
                bb:set("module.grind.is_looting", false)
                return Status.FAILURE
            end

            -- Check if target is still lootable
            local ok_loot, can_loot = pcall(target.can_be_looted, target)
            if not ok_loot or not can_loot then
                -- Loot finished or corpse despawned — check for more lootables
                bb:set("module.grind.is_looting", false)
                bb:set("module.grind.loot_target", nil)
                bb:set("module.grind.current_target", nil)
                bb:set("module.grind.loot_attempt", nil)
                bb:set("module.grind.loot_until", nil)
                event_bus:publish("grind:loot", {})
                return Status.SUCCESS
            end

            local now = bb:get("system.now_ms", 0)
            local loot_until = bb:get("module.grind.loot_until", 0)

            -- Still in loot wait period
            if loot_until > 0 and now < loot_until then
                return Status.RUNNING
            end

            local attempt = bb:get("module.grind.loot_attempt", 0)
            if attempt >= 3 then
                -- Max retries, blacklist and move on (FAILURE skips publish_loot
                -- so telemetry doesn't count a failed loot as successful)
                bb:set("module.grind.is_looting", false)
                loot_blacklist[blacklist_key(target)] = now + LOOT_BLACKLIST_DURATION_MS
                bb:set("module.grind.loot_target", nil)
                bb:set("module.grind.loot_attempt", nil)
                bb:set("module.grind.loot_until", nil)
                return Status.FAILURE
            end

            -- Stop movement, flag looting, send loot command
            nav_adapter:stop("looting")
            bb:set("module.grind.is_looting", true)

-- Enhanced loot logic with quality filtering
             if core and core.input and core.input.loot_object then
                 -- Note: Using core.input.loot_object (Sylvannas API)
                 -- Quality-based filtering via loot preview is not available in Sylvannas,
                 -- so we loot everything and rely on post-loot inventory management
                 pcall(core.input.loot_object, target)
             end

            bb:set("module.grind.loot_attempt", attempt + 1)
            bb:set("module.grind.loot_until", now + 500)
            return Status.RUNNING
        end),

        -- Cleanup and publish
        BT.action("publish_loot", function(bb)
            bb:set("module.grind.is_looting", false)
            bb:set("module.grind.loot_attempt", nil)
            bb:set("module.grind.loot_until", nil)
            event_bus:publish("grind:loot_complete", {})
            return Status.SUCCESS
        end),
    })
end

return Loot