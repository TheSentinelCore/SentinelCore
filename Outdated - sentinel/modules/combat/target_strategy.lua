local TargetStrategy = {}

-- Required methods for target selection strategies
TargetStrategy.REQUIRED_METHODS = {
    "get_best_target",
    "is_valid_enemy",
}

function TargetStrategy.validate(strategy)
    if not strategy then
        return false, "Strategy is nil"
    end
    for _, method in ipairs(TargetStrategy.REQUIRED_METHODS) do
        if type(strategy[method]) ~= "function" then
            return false, "Missing required method: " .. method
        end
    end
    return true
end

return TargetStrategy