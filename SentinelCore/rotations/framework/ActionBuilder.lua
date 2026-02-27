---@class RotationActionBuilder
local ActionBuilder = {}

---@private
---@param action_type string
---@param priority number
---@param opts? table
---@return table
local function build_action(action_type, priority, opts)
    opts = opts or {}
    local target = "target"
    if action_type == "cast_spell_self" then
        target = "self"
    elseif action_type == "cast_spell_position" then
        target = "position"
    end

    return {
        action_type = action_type,
        priority = priority,
        allow_movement = opts.allow_movement == true,
        target = target,
        intent = opts.intent,
        combat_modes = opts.combat_modes,
        intent_bonus = opts.intent_bonus,
        scheduler_group = opts.scheduler_group,
        scheduler_bias = opts.scheduler_bias,
        relative_deadline_sec = opts.relative_deadline_sec,
        relative_deadline_by_mode = opts.relative_deadline_by_mode,
        release_delay_sec = opts.release_delay_sec,
        item_kind = opts.item_kind,
        rest_lock_secs = opts.rest_lock_secs,
        requires_castable_check = opts.requires_castable_check ~= false and action_type ~= "use_item_self" and
            action_type ~= "use_best_health_potion" and action_type ~= "use_best_mana_potion",
        skip_facing = opts.skip_facing == true,
        skip_range = opts.skip_range == true,
        min_target_health_pct = opts.min_target_health_pct,
        max_target_health_pct = opts.max_target_health_pct,
        min_player_health_pct = opts.min_player_health_pct,
        max_player_health_pct = opts.max_player_health_pct,
        min_player_mana_pct = opts.min_player_mana_pct,
        max_player_mana_pct = opts.max_player_mana_pct,
        min_target_distance = opts.min_target_distance,
        max_target_distance = opts.max_target_distance,
        target_must_be_casting = opts.target_must_be_casting == true,
        condition = opts.condition,
    }
end

---@param spell_id number|fun(ctx: table, action: table): number|nil
---@param priority number
---@param opts? table
---@return table
function ActionBuilder.target_spell(spell_id, priority, opts)
    local action = build_action("cast_spell_target", priority, opts)
    action.spell_id = spell_id
    return action
end

---@param spell_id number|fun(ctx: table, action: table): number|nil
---@param priority number
---@param opts? table
---@return table
function ActionBuilder.self_spell(spell_id, priority, opts)
    opts = opts or {}
    opts.skip_facing = true
    opts.skip_range = true
    if opts.allow_movement == nil then
        opts.allow_movement = true
    end
    local action = build_action("cast_spell_self", priority, opts)
    action.spell_id = spell_id
    return action
end

---@param spell_id number|fun(ctx: table, action: table): number|nil
---@param priority number
---@param opts? table
---@return table
function ActionBuilder.position_spell(spell_id, priority, opts)
    opts = opts or {}
    opts.skip_facing = true
    opts.skip_range = true
    local action = build_action("cast_spell_position", priority, opts)
    action.spell_id = spell_id
    action.position = opts.resolve_position or opts.position
    return action
end

---@param item_id number|number[]
---@param priority number
---@param opts? table
---@return table
function ActionBuilder.item_self(item_id, priority, opts)
    opts = opts or {}
    opts.skip_facing = true
    opts.skip_range = true
    opts.allow_movement = true
    local action = build_action("use_item_self", priority, opts)
    action.item_id = item_id
    return action
end

---@param priority number
---@param opts? table
---@return table
function ActionBuilder.best_health_potion(priority, opts)
    opts = opts or {}
    opts.skip_facing = true
    opts.skip_range = true
    opts.allow_movement = true
    return build_action("use_best_health_potion", priority, opts)
end

---@param priority number
---@param opts? table
---@return table
function ActionBuilder.best_mana_potion(priority, opts)
    opts = opts or {}
    opts.skip_facing = true
    opts.skip_range = true
    opts.allow_movement = true
    return build_action("use_best_mana_potion", priority, opts)
end

---@param spell_id number|fun(ctx: table, action: table): number|nil
---@param priority number
---@param opts? table
---@return table
function ActionBuilder.channel_spell(spell_id, priority, opts)
    opts = opts or {}
    local action = build_action("channel_spell", priority, opts)
    action.spell_id = spell_id
    action.channel_duration = opts.channel_duration or 3.0
    return action
end

return ActionBuilder
