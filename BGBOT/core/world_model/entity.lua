---@module BGBOT.core.world_model.entity
-- EntityRecord constructor.
-- Creates a blank entity record with default values.

local entity = {}

----------------------------------------------------------------------
-- Default Entity Record
----------------------------------------------------------------------

---@return EntityRecord
function entity.new_record()
    return {
        handle           = nil,    -- game_object
        name             = "",
        position         = { x = 0, y = 0, z = 0 },
        health_pct       = 100,
        power_pct        = 100,
        class_id         = 0,
        spec_id          = 0,
        is_player        = false,
        is_enemy         = false,
        is_ally          = false,
        is_dead          = false,
        is_in_combat     = false,
        is_mounted       = false,
        is_moving        = false,
        movement_speed   = 0,
        target_handle    = nil,
        has_flag          = false,
        is_casting       = false,
        cast_spell_id    = 0,
        is_interruptable = false,
        buffs            = {},
        debuffs          = {},
        loss_of_control  = nil,
        group_role       = -1,
        distance         = 9999,
        last_seen        = 0,
        confidence       = 0,
        ring             = "far",
    }
end

return entity
