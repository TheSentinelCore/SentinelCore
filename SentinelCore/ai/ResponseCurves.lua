local RC = {}

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

local function linear(x, p)
    local min, max = p.min or 0, p.max or 1
    if max == min then return x >= min and 1 or 0 end
    return clamp((x - min) / (max - min), 0, 1)
end

local curves = {
    linear = linear,

    inverse_linear = function(x, p)
        return 1 - linear(x, p)
    end,

    quadratic = function(x, p)
        local t = linear(x, p)
        return t * t
    end,

    inverse_quadratic = function(x, p)
        local t = 1 - linear(x, p)
        return 1 - t * t
    end,

    logistic = function(x, p)
        local k = p.steepness or 10
        local m = p.midpoint or 0.5
        return 1 / (1 + math.exp(-k * (x - m)))
    end,

    step_above = function(x, p)
        return x >= (p.threshold or 0.5) and 1 or 0
    end,

    step_below = function(x, p)
        return x < (p.threshold or 0.5) and 1 or 0
    end,

    bell = function(x, p)
        local center = p.center or 0.5
        local width = p.width or 0.2
        if width < 0.001 then width = 0.001 end
        local d = x - center
        return math.exp(-(d * d) / (2 * width * width))
    end,

    constant = function(_, p)
        return p.value or 1
    end,
}

---Evaluate a named response curve.
---@param curve_name string
---@param input number
---@param params table
---@return number  Score in [0,1]
function RC.evaluate(curve_name, input, params)
    local fn = curves[curve_name]
    if not fn then return 0 end
    return fn(input, params or {})
end

---Check if a curve name is valid.
---@param name string
---@return boolean
function RC.is_valid(name)
    return curves[name] ~= nil
end

return RC
