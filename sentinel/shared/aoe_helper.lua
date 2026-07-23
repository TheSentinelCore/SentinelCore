local AoeHelper = {}

-- Import required modules
local function safe_require(module_name)
    local ok, module = pcall(require, module_name)
    if not ok then
        return nil
    end
    return module
end

local spell_prediction = safe_require("common/modules/spell_prediction")
-- `core` is the Sylvannas-injected global (see docs/SylvannasAPI/dev/api/core.md);
-- it is never a requireable module. `safe_require("core")` always failed here
-- (no `core.lua` anywhere on package.path, in-game or offline), which shadowed
-- the real global `core` with a permanent `nil` local and made every
-- `core.input.*` call below dead code — `cast_ground_optimal` silently
-- returned `false, 0` unconditionally. Every other owned file in this lane
-- (chase_controller.lua, context_builder.lua, etc.) references the bare
-- global `core` directly; do the same here instead of shadowing it.
local izi = safe_require("common/izi_sdk")

-- Cache frequently accessed values
local function get_player_position()
    local player = izi and izi.get_player()
    if player and player.get_position then
        return player:get_position()
    end
    return {x = 0, y = 0, z = 0}
end

local function get_target_position()
    local target = izi and izi.target()
    if target and target.get_position then
        return target:get_position()
    end
    return get_player_position()  -- Fallback to player position
end

--- Find the optimal position to cast a spell to hit the maximum number of targets
-- @param spell_id number The spell ID to cast
-- @param range number Maximum range to consider for targeting
-- @param min_targets number Minimum number of targets required to consider casting
-- @param radius number Optional radius of the spell's area of effect (defaults to 8 yards)
-- @return table|nil, number Position vector and number of targets that would be hit, or nil if no suitable position found
function AoeHelper.find_optimal_position(spell_id, range, min_targets, radius)
    if not spell_prediction then
        return nil, 0
    end
    
    radius = radius or 8  -- Default AoE radius
    
    -- Create spell data for prediction
    local spell_data = spell_prediction:new_spell_data(
        spell_id,                    -- spell_id
        range,                       -- max_range
        radius,                      -- radius
        0,                           -- cast_time (instant cast assumed, will be overridden if needed)
        0,                           -- projectile_speed
        spell_prediction.prediction_type.MOST_HITS,
        spell_prediction.geometry_type.CIRCLE,
        get_player_position()        -- source_position
    )
    
    if not spell_data then
        return nil, 0
    end
    
    -- Get the position that hits the most targets
    local result = spell_prediction:get_most_hits_position(get_target_position(), spell_data)
    
    if result and result.amount_of_hits and result.amount_of_hits >= min_targets then
        return result.cast_position, result.amount_of_hits
    end
    
    return nil, result and result.amount_of_hits or 0
end

--- Cast a spell at the optimal ground position to hit multiple targets
-- @param spell_id number The spell ID to cast
-- @param range number Maximum range to consider for targeting
-- @param min_targets number Minimum number of targets required to consider casting
-- @param radius number Optional radius of the spell's area of effect
-- @return boolean, number True if spell_was_cast, number_of_targets_hit
function AoeHelper.cast_ground_optimal(spell_id, range, min_targets, radius)
    if not core or not core.input or not core.input.cast_position_spell then
        return false, 0
    end
    
    local position, hits = AoeHelper.find_optimal_position(spell_id, range, min_targets, radius)
    
    if position and hits >= min_targets then
        -- Attempt to cast the spell at the calculated position.
        -- C9: guard the call the same way every other core.input.* call site in
        -- this file does — the outer `not core.input.cast_position_spell` check
        -- above only ran once at function entry and can go stale/nil between
        -- that check and this call in a hot-reload; re-check + pcall here.
        if type(core.input.cast_position_spell) ~= "function" then
            return false, hits
        end
        local ok, success = pcall(core.input.cast_position_spell, spell_id, position)
        return ok and success or false, hits
    end
    
    return false, 0
end

--- Check if we can cast a ground-targeted spell at optimal position without actually casting
-- @param spell_id number The spell ID to check
-- @param range number Maximum range to consider for targeting
-- @param min_targets number Minimum number of targets required to consider casting
-- @param radius number Optional radius of the spell's area of effect
-- @return boolean, number Can cast, number of targets that would be hit
function AoeHelper.can_cast_ground_optimal(spell_id, range, min_targets, radius)
    local _, hits = AoeHelper.find_optimal_position(spell_id, range, min_targets, radius)
    return hits >= min_targets, hits
end

return AoeHelper
