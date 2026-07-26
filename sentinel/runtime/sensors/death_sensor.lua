local Compat = require("shared/compat")
local safe_call = Compat.safe_call
local safe_call0 = Compat.safe_call0
local num = Compat.num

local DeathSensor = {}
DeathSensor.__index = DeathSensor

function DeathSensor:new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _was_dead = false,
    }, DeathSensor)
end

local PlainPosition = require("shared/plain_position")

function DeathSensor:refresh(player, now_ms)
    local bb = self._blackboard
    local is_dead = safe_call(player, "is_dead") == true
    local is_ghost = safe_call(player, "is_ghost") == true
    local position = bb:get("player.position")

    -- Track death position on transition (for corpse run)
    if is_dead and not self._was_dead and position then
        bb:set("player.death_position", { x = position.x, y = position.y, z = position.z })
    elseif not is_dead and not is_ghost and self._was_dead then
        bb:clear("player.death_position")
    end
    self._was_dead = is_dead or is_ghost

    -- Corpse position from game UI
    local corpse_position = nil
    local resurrect_delay_s = 0
    local game_ui = core and core.game_ui or nil
    if game_ui then
        corpse_position = safe_call0(game_ui.get_corpse_position, game_ui)
        resurrect_delay_s = num(safe_call0(game_ui.get_resurrect_corpse_delay, game_ui))
    end
    -- MEASURED LIVE (run two): get_corpse_position() is a vec3 class instance, exactly like
    -- get_position() on run one — copy it plain or the purity guard refuses the write.
    bb:set("player.corpse_position", PlainPosition.copy(corpse_position))
    bb:set("player.resurrect_delay_s", resurrect_delay_s)
end

return DeathSensor
