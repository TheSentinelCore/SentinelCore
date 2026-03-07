local Strategies = {}

local defs = {
    balanced = { id = "balanced", label = "Balanced" },
    node_rotation = { id = "node_rotation", label = "Node Rotation" },
    turtle_defense = { id = "turtle_defense", label = "Turtle Defense" },
    aggressive_push = { id = "aggressive_push", label = "Aggressive Push" },
}

local function num(v)
    return tonumber(v) or 0
end

local function strategy_settings(ctx)
    if type(ctx) ~= "table" then return {} end
    if type(ctx.strategy_settings) == "table" then return ctx.strategy_settings end
    if type(ctx.settings) == "table" and type(ctx.settings.strategy) == "table" then return ctx.settings.strategy end
    return {}
end

local function priority_type_bonus(ctx, objective_type)
    local settings = strategy_settings(ctx)
    local list = settings and settings.objective_priority
    if type(list) ~= "table" then return 0 end
    for i, t in ipairs(list) do
        if t == objective_type then
            return math.max(0, (#list - i + 1) * 2)
        end
    end
    return 0
end

local function common(ctx, c)
    local s = 0
    s = s - (num(c.distance) * 0.05)
    s = s + (num(c.allies_near) * 0.9)
    s = s - (num(c.enemies_near) * 0.7)

    if c.owner == "CONTESTED" then
        s = s + 18
    end

    s = s + priority_type_bonus(ctx, c.type)
    return s
end

local function node_rotation(ctx, c)
    local s = common(ctx, c)
    if c.owner == "CONTESTED" then
        s = s + 25
    elseif c.owner == "ENEMY" then
        s = s + 18
    elseif c.owner == "NEUTRAL" then
        s = s + 12
    elseif c.owner == "FRIENDLY" then
        s = s - 5
    end
    return s
end

local function turtle_defense(ctx, c)
    local s = common(ctx, c)
    if c.owner == "FRIENDLY" then
        s = s + 22
    end
    if c.owner == "CONTESTED" then
        s = s + 10
    end
    if c.owner == "ENEMY" then
        s = s - 8
    end
    return s
end

local function aggressive_push(ctx, c)
    local s = common(ctx, c)
    if c.owner == "ENEMY" then
        s = s + 26
    end
    if c.owner == "CONTESTED" then
        s = s + 16
    end
    if c.owner == "FRIENDLY" then
        s = s - 12
    end
    return s
end

local function balanced(ctx, c)
    local s = common(ctx, c)
    if c.owner == "CONTESTED" then
        s = s + 20
    elseif c.owner == "ENEMY" then
        s = s + 14
    elseif c.owner == "NEUTRAL" then
        s = s + 10
    else
        s = s + 6
    end
    return s
end

local score_dispatch = {
    balanced = balanced,
    node_rotation = node_rotation,
    turtle_defense = turtle_defense,
    aggressive_push = aggressive_push,
}

function Strategies:list()
    local out = {}
    for _, v in pairs(defs) do
        out[#out + 1] = { id = v.id, label = v.label }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function Strategies:get(name)
    local key = tostring(name or "balanced")
    local d = defs[key] or defs.balanced
    local fn = score_dispatch[d.id] or balanced

    return {
        id = d.id,
        label = d.label,
        score = function(ctx, c)
            return fn(ctx, c)
        end,
    }
end

return Strategies
