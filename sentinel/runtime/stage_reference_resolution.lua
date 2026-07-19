-- sentinel/runtime/stage_reference_resolution.lua
-- SENT-6.2: Stage 2 — Reference Resolution
-- ADR 008 §5 — Resolve all references against QueryServer once

local Diagnostics = require("runtime/diagnostics")

local ReferenceResolutionStage = {}
ReferenceResolutionStage.__index = ReferenceResolutionStage

ReferenceResolutionStage.ErrorCodes = {
    UnresolvableNpc = "C-2001",
    UnresolvableQuest = "C-2002",
    UnresolvableVendor = "C-2003",
    UnresolvableCreature = "C-2004",
    UnresolvableGameObject = "C-2005",
}

function ReferenceResolutionStage:new(query_client)
    return setmetatable({ _query_client = query_client or nil }, ReferenceResolutionStage)
end

function ReferenceResolutionStage:run(profile)
    local errors = {}
    local warnings = {}
    local profile_copy = self:_deep_copy(profile)

    if not profile_copy or not profile_copy.operations then
        return { profile = profile_copy, diagnostics = { errors = errors, warnings = {} } }
    end

    for _, op in ipairs(profile_copy.operations) do
        if op.actions then
            for _, action in ipairs(op.actions) do
                self:_resolve_action_references(action)
            end
        end
    end

    return { profile = profile_copy, diagnostics = { errors = errors, warnings = warnings } }
end

function ReferenceResolutionStage:_resolve_action_references(action)
    if not action then return end
    local params = action.params or {}
    if params.npc_guid or params.quest_id or params.creature_entry or params.object_guid then
        action.params = self:_resolve_reference_params(action.params)
    end
end

function ReferenceResolutionStage:_resolve_reference_params(params)
    if not params then return params end
    local resolved = {}
    for k, v in pairs(params) do resolved[k] = v end
    if params.npc_guid and self._query_client then
        local npc = self._query_client:get_npc(params.npc_guid) or self._query_client:fetch_npc(params.npc_guid)
        if npc then
            for k, v in pairs(npc) do resolved[k] = v end
        elseif params.npc_guid then
            resolved._resolution_failed = true
            resolved._failed_for = "npc"
        end
    end
    if params.quest_id and self._query_client then
        local quest = self._query_client:get_quest(params.quest_id) or self._query_client:fetch_quest(params.quest_id)
        if quest then
            for k, v in pairs(quest) do resolved[k] = v end
        elseif params.quest_id then
            resolved._resolution_failed = true
            resolved._failed_for = "quest"
        end
    end
    return resolved
end

function ReferenceResolutionStage:_deep_copy(obj)
    if type(obj) ~= "table" then return obj end
    local copy = {}
    for k, v in pairs(obj) do copy[k] = self:_deep_copy(v) end
    return copy
end

return ReferenceResolutionStage