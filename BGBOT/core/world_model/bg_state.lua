---@module BGBOT.core.world_model.bg_state
-- BgState constructor.
-- Creates a blank BG state with default values.

local bg_state = {}

----------------------------------------------------------------------
-- Default BG State
----------------------------------------------------------------------

---@return BgState
function bg_state.new_state()
    return {
        phase              = 0,
        phase_source       = "init",
        run_time           = 0,
        winner             = nil,
        map_id             = 0,
        ui_map_id          = 0,
        has_preparation    = false,
        preparation_aura_id = 0,
        preparation_aura_name = "",
        bg_type            = "unknown",

        -- WSG extensions
        our_flag_state     = "unknown",
        their_flag_state   = "unknown",
        our_flag_carrier   = nil,   -- game_object | nil
        their_flag_carrier = nil,   -- game_object | nil
        our_score          = nil,   -- number | nil  (DEC-013: inferred/optional)
        their_score        = nil,   -- number | nil  (DEC-013: inferred/optional)
    }
end

return bg_state
