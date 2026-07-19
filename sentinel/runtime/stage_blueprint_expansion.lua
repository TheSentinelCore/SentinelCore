-- sentinel/runtime/stage_blueprint_expansion.lua
-- SENT-6.3: Stage 3 — Blueprint Expansion
-- ADR 008 §6 — Recursively expand Blueprint references to primitive actions

local BlueprintRegistry = require("runtime/blueprint_registry")
local Diagnostics = require("runtime/diagnostics")

local BlueprintExpansionStage = {}
BlueprintExpansionStage.__index = BlueprintExpansionStage

BlueprintExpansionStage.ErrorCodes = {
    BlueprintNotFound = "C-3001",
    InvalidParams = "C-3002",
    ExpansionFailed = "C-3003",
    RecursionLimit = "C-3004",
}

BlueprintExpansionStage.MAX_RECURSION_DEPTH = 10

function BlueprintExpansionStage:new(blueprint_registry)
    return setmetatable({
        _registry = blueprint_registry or BlueprintRegistry:new(),
    }, BlueprintExpansionStage)
end

function BlueprintExpansionStage:run(profile)
    local errors = {}
    local warnings = {}
    self._errors = {}
    local profile_copy = self:_deep_copy(profile)

    if not profile_copy or not profile_copy.operations then
        return { profile = profile_copy, diagnostics = { errors = errors, warnings = warnings } }
    end

    for _, op in ipairs(profile_copy.operations) do
        if op.actions then
            op.actions = self:_expand_operation_actions(op.actions, 0)
        end
    end

    return { profile = profile_copy, diagnostics = { errors = self._errors, warnings = {} } }
end

function BlueprintExpansionStage:_expand_operation_actions(actions, depth)
    if depth > self.MAX_RECURSION_DEPTH then
        table.insert(self._errors, {
            code = BlueprintExpansionStage.ErrorCodes.RecursionLimit,
            message = "Blueprint expansion exceeded max recursion depth",
            stage = Diagnostics.Stage.BlueprintExpansion,
            severity = Diagnostics.Severity.ERROR,
        })
        return actions
    end

    local expanded = {}
    for i, action in ipairs(actions) do
        if self._registry:is_blueprint(action) then
            local result = self._registry:expand(action)
            if result then
                for _, expanded_action in ipairs(result) do
                    if self._registry:is_blueprint(expanded_action) then
                        local nested = self:_expand_operation_actions({ expanded_action }, depth + 1)
                        for _, nested_action in ipairs(nested) do
                            nested_action.generated_from = action.id or action.blueprint_id
                            table.insert(expanded, nested_action)
                        end
                    else
                        expanded_action.generated_from = action.id or action.blueprint_id
                        table.insert(expanded, expanded_action)
                    end
                end
            else
                table.insert(self._errors, {
                    code = BlueprintExpansionStage.ErrorCodes.BlueprintNotFound,
                    message = "Blueprint not found: " .. tostring(action.blueprint_id),
                    stage = Diagnostics.Stage.BlueprintExpansion,
                    severity = Diagnostics.Severity.ERROR,
                })
            end
        else
            table.insert(expanded, action)
        end
    end
    return expanded
end

function BlueprintExpansionStage:_deep_copy(obj)
    if type(obj) ~= "table" then return obj end
    local copy = {}
    for k, v in pairs(obj) do copy[k] = self:_deep_copy(v) end
    return copy
end

return BlueprintExpansionStage