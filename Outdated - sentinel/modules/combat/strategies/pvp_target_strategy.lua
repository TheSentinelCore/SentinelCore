local PvPTargetStrategy = {}
PvPTargetStrategy.__index = PvPTargetStrategy

function PvPTargetStrategy:new(event_bus, blackboard)
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _last_score = 0,
    }, self)
end

function PvPTargetStrategy:select(player, opts)
    -- PvP target selection logic
    -- This is a simplified version - the full implementation would be in a separate file
    return nil
end

return PvPTargetStrategy