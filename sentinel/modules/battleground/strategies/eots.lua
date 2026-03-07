local Strategies = {}

local defs = {
    balanced = { id = "balanced", label = "Balanced" },
    node_control = { id = "node_control", label = "Node Control" },
    flag_focus = { id = "flag_focus", label = "Flag Focus" },
    hybrid = { id = "hybrid", label = "Hybrid" },
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

local function in_bootstrap_window(ctx)
    local phase = tostring(ctx and ctx.bootstrap_phase or "")
    return ctx and (
        ctx.prep_blocked == true
        or phase == "prep"
        or phase == "pending"
        or phase == "active"
    ) or false
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
    s = s - (num(c.distance) * 0.04)
    s = s + (num(c.allies_near) * 0.9)
    s = s - (num(c.enemies_near) * 0.8)

    if c.owner == "CONTESTED" then
        s = s + 14
    end

    s = s + priority_type_bonus(ctx, c.type)
    return s
end

local function node_control(ctx, c)
    local s = common(ctx, c)
    if in_bootstrap_window(ctx) and c.id == "CENTER_FLAG" then
        s = s - 28
    end
    if c.type == "NODE" then
        if in_bootstrap_window(ctx) then
            s = s + 12
        end
        if c.owner == "ENEMY" then s = s + 20 end
        if c.owner == "NEUTRAL" then s = s + 16 end
        if c.owner == "CONTESTED" then s = s + 12 end
    end
    if c.type == "FLAG" then
        s = s + 4
    end
    return s
end

local function flag_focus(ctx, c)
    local s = common(ctx, c)
    if c.id == "CENTER_FLAG" then
        s = s + 40
    elseif c.type == "NODE" then
        s = s + 8
        if c.owner == "FRIENDLY" then
            s = s + 6
        end
    end
    return s
end

local function hybrid(ctx, c)
    local s = common(ctx, c)
    if c.id == "CENTER_FLAG" then
        s = s + 16
        if in_bootstrap_window(ctx) then
            s = s - 24
        end
    end
    if c.type == "NODE" then
        if in_bootstrap_window(ctx) then
            s = s + 10
        end
        if c.owner == "ENEMY" then s = s + 14 end
        if c.owner == "NEUTRAL" then s = s + 10 end
        if c.owner == "FRIENDLY" then s = s + 6 end
    end
    return s
end

local function balanced(ctx, c)
    local s = common(ctx, c)
    if c.id == "CENTER_FLAG" then
        s = s + 10
        if in_bootstrap_window(ctx) then
            s = s - 26
        end
    end
    if c.type == "NODE" then
        if in_bootstrap_window(ctx) then
            s = s + 12
        end
        if c.owner == "CONTESTED" then s = s + 12 end
        if c.owner == "ENEMY" then s = s + 10 end
        if c.owner == "NEUTRAL" then s = s + 8 end
    end
    return s
end

local score_dispatch = {
    balanced = balanced,
    node_control = node_control,
    flag_focus = flag_focus,
    hybrid = hybrid,
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
