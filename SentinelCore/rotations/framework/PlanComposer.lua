---@class RotationPlanComposer
local PlanComposer = {}

---@private
---@param plan table[]
---@param actions table[]|nil
local function append_actions(plan, actions)
    if type(actions) ~= "table" then
        return
    end

    for i = 1, #actions do
        plan[#plan + 1] = actions[i]
    end
end

---@private
---@param plan table[]
local function stable_priority_sort(plan)
    local insertion_order = {}
    for i = 1, #plan do
        insertion_order[plan[i]] = i
    end

    table.sort(plan, function(a, b)
        local ap = tonumber(a and a.priority) or 0
        local bp = tonumber(b and b.priority) or 0
        if ap == bp then
            return (insertion_order[a] or 0) < (insertion_order[b] or 0)
        end
        return ap > bp
    end)
end

---@param provider table
---@param ctx table
---@param aoe_threshold number
---@return table[]
function PlanComposer.compose_combat(provider, ctx, aoe_threshold)
    local plan = {}

    append_actions(plan, provider:defensive(ctx))
    append_actions(plan, provider:interrupt(ctx))
    append_actions(plan, provider:utility(ctx))

    local enemies = tonumber(ctx.enemy_count) or 1
    if enemies >= (tonumber(aoe_threshold) or 3) then
        append_actions(plan, provider:aoe(ctx))
    else
        append_actions(plan, provider:combat(ctx))
    end

    stable_priority_sort(plan)
    return plan
end

---@param provider table
---@param ctx table
---@return table[]
function PlanComposer.compose_maintenance(provider, ctx)
    local plan = {}

    if provider and provider.maintenance then
        append_actions(plan, provider:maintenance(ctx))
    end

    stable_priority_sort(plan)
    return plan
end

return PlanComposer
