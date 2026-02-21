---@class RotationActionBuilder
local ActionBuilder = {}

---@private
---@param action_type string
---@param spell_id number
---@param priority number
---@param opts? table
---@return table
local function build_action(action_type, spell_id, priority, opts)
    opts = opts or {}
    return {
        action_type = action_type,
        spell_id = spell_id,
        priority = priority,
        allow_movement = opts.allow_movement == true,
        target = action_type == "cast_spell_self" and "self" or "target",
        requires_castable_check = opts.requires_castable_check ~= false,
        skip_facing = opts.skip_facing == true,
        skip_range = opts.skip_range == true,
        min_target_health_pct = opts.min_target_health_pct,
        max_target_health_pct = opts.max_target_health_pct,
        min_player_health_pct = opts.min_player_health_pct,
        max_player_health_pct = opts.max_player_health_pct,
        min_player_mana_pct = opts.min_player_mana_pct,
        min_target_distance = opts.min_target_distance,
        max_target_distance = opts.max_target_distance,
        target_must_be_casting = opts.target_must_be_casting == true,
        condition = opts.condition,
    }
end

---@param spell_id number
---@param priority number
---@param opts? table
---@return table
function ActionBuilder.target_spell(spell_id, priority, opts)
    return build_action("cast_spell_target", spell_id, priority, opts)
end

---@param spell_id number
---@param priority number
---@param opts? table
---@return table
function ActionBuilder.self_spell(spell_id, priority, opts)
    opts = opts or {}
    opts.skip_facing = true
    opts.skip_range = true
    opts.allow_movement = true
    return build_action("cast_spell_self", spell_id, priority, opts)
end

return ActionBuilder
