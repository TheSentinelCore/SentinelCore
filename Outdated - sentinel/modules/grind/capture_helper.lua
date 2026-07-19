local CaptureHelper = {}

---Capture the local player's current position.
---@return table|nil { x = number, y = number, z = number }
function CaptureHelper.capture_position()
    local ok, player = pcall(function()
        return core.object_manager.get_local_player()
    end)
    if not ok or not player then
        return nil
    end

    local ok2, pos = pcall(function()
        return player:get_position()
    end)
    if not ok2 or not pos then
        return nil
    end

    return { x = pos.x, y = pos.y, z = pos.z }
end

---Capture the player's position as a hotspot.
---@param radius number|nil Hotspot radius (default 40)
---@param label string|nil Human-readable label
---@return table|nil { id = string, label = string, x = number, y = number, z = number, radius = number, target_overrides = nil }
function CaptureHelper.capture_hotspot(radius, label)
    local pos = CaptureHelper.capture_position()
    if not pos then
        return nil
    end

    local id
    if label and label ~= "" then
        id = label:lower():gsub("%s+", "_"):gsub("[^%w_]", "")
    else
        id = "hotspot_" .. tostring(math.floor(core.time()))
    end

    return {
        id = id,
        label = label or id,
        x = pos.x,
        y = pos.y,
        z = pos.z,
        radius = radius or 40,
        target_overrides = nil,
    }
end

---Capture the player's current target as an NPC reference.
---@return table|nil { npc_id = number, name = string }
function CaptureHelper.capture_mob_ref()
    local ok, player = pcall(function()
        return core.object_manager.get_local_player()
    end)
    if not ok or not player then
        return nil
    end

    local ok2, target = pcall(function()
        return player:get_target()
    end)
    if not ok2 or not target then
        return nil
    end

    local ok3, is_unit = pcall(function()
        return target:is_unit()
    end)
    if not ok3 or not is_unit then
        return nil
    end

    local ok4, is_player = pcall(function()
        return target:is_player()
    end)
    if not ok4 or is_player then
        return nil
    end

    local ok5, npc_id = pcall(function()
        return target:get_npc_id()
    end)
    if not ok5 then
        npc_id = 0
    end

    local ok6, name = pcall(function()
        return target:get_name()
    end)
    if not ok6 then
        name = "unknown"
    end

    return { npc_id = npc_id, name = name }
end

---Capture the player's current target NPC as a vendor reference with position.
---@param services string[] List of services (e.g. {"repair", "food"})
---@return table|nil { npc_id = number, name = string, x = number, y = number, z = number, services = string[] }
function CaptureHelper.capture_vendor(services)
    local ok, player = pcall(function()
        return core.object_manager.get_local_player()
    end)
    if not ok or not player then
        return nil
    end

    local ok2, target = pcall(function()
        return player:get_target()
    end)
    if not ok2 or not target then
        return nil
    end

    local ok3, is_unit = pcall(function()
        return target:is_unit()
    end)
    if not ok3 or not is_unit then
        return nil
    end

    local ok4, is_player = pcall(function()
        return target:is_player()
    end)
    if not ok4 or is_player then
        return nil
    end

    local ok5, npc_id = pcall(function()
        return target:get_npc_id()
    end)
    if not ok5 then
        npc_id = 0
    end

    local ok6, name = pcall(function()
        return target:get_name()
    end)
    if not ok6 then
        name = "unknown"
    end

    local ok7, pos = pcall(function()
        return target:get_position()
    end)
    if not ok7 or not pos then
        return nil
    end

    return {
        npc_id = npc_id,
        name = name,
        x = pos.x,
        y = pos.y,
        z = pos.z,
        services = services or {},
    }
end

---Capture the player's position as a blackspot.
---@param radius number|nil Blackspot radius (default 20)
---@param reason string|nil Reason for the blackspot
---@return table|nil { x = number, y = number, z = number, radius = number, reason = string }
function CaptureHelper.capture_blackspot(radius, reason)
    local pos = CaptureHelper.capture_position()
    if not pos then
        return nil
    end

    return {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        radius = radius or 20,
        reason = reason or "",
    }
end

---Capture basic requirements from the current game state.
---@return table|nil { map_id = number, min_level = number, max_level = number }
function CaptureHelper.capture_requirements()
    local ok, map_id = pcall(function()
        return core.get_map_id()
    end)
    if not ok or not map_id then
        return nil
    end

    local ok2, player = pcall(function()
        return core.object_manager.get_local_player()
    end)
    if not ok2 or not player then
        return nil
    end

    local ok3, player_level = pcall(function()
        return player:get_level()
    end)
    if not ok3 or not player_level then
        return nil
    end

    return {
        map_id = map_id,
        min_level = player_level,
        max_level = player_level + 5,
    }
end

return CaptureHelper
