local Strategies = {}

local defs = {
    balanced = { id = "balanced", label = "Balanced" },
    flag_run = { id = "flag_run", label = "Flag Run" },
    turtle_defense = { id = "turtle_defense", label = "Turtle Defense" },
    midfield_control = { id = "midfield_control", label = "Midfield Control" },
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

local function common(ctx, candidate)
    local s = 0
    s = s - (num(candidate.distance) * 0.04)
    s = s + (num(candidate.allies_near) * 0.8)
    s = s - (num(candidate.enemies_near) * 0.6)

    if candidate.owner == "CONTESTED" then
        s = s + 12
    end

    s = s + priority_type_bonus(ctx, candidate.type)
    return s
end

local function flag_run(ctx, c)
    local s = common(ctx, c)
    if c.type == "FLAG" and c.side ~= ctx.player_side then
        s = s + 40
    end
    if c.type == "FLAG" and c.side == ctx.player_side then
        s = s - 10
    end
    if c.type == "MID" then
        s = s + 4
    end
    return s
end

local function turtle_defense(ctx, c)
    local s = common(ctx, c)
    if c.type == "FLAG" and c.side == ctx.player_side then
        s = s + 38
    end
    if c.type == "MID" then
        s = s + 8
    end
    if c.type == "FLAG" and c.side ~= ctx.player_side then
        s = s - 8
    end
    return s
end

local function midfield_control(ctx, c)
    local s = common(ctx, c)
    if c.type == "MID" then
        s = s + 35
    end
    if c.type == "FLAG" and c.side ~= ctx.player_side then
        s = s + 8
    end
    return s
end

local function balanced(ctx, c)
    local s = common(ctx, c)
    if c.type == "FLAG" and c.side ~= ctx.player_side then
        s = s + 20
    end
    if c.type == "FLAG" and c.side == ctx.player_side then
        s = s + 12
    end
    if c.type == "MID" then
        s = s + 10
    end
    return s
end

local score_dispatch = {
    balanced = balanced,
    flag_run = flag_run,
    turtle_defense = turtle_defense,
    midfield_control = midfield_control,
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
        score = function(ctx, candidate)
            return fn(ctx, candidate)
        end,
    }
end

return Strategies
