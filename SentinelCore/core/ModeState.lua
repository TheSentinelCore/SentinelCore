---@class SentinelModeState
local ModeState = {}

local DEFAULT_MODE_ID = "grind"
local DEFAULT_PHASES = {
    "scout",
    "acquire",
    "objective",
    "pull",
    "combat",
    "loot",
    "vendor",
    "recover",
}

---@param value any
---@param fallback string
---@return string
local function normalize_token(value, fallback)
    local token = tostring(value or ""):lower()
    token = token:gsub("[^%w_]", "")
    if token == "" then
        token = tostring(fallback or "")
    end
    if token == "" then
        token = "unknown"
    end
    return token
end

---@return string
function ModeState.default_mode_id()
    return DEFAULT_MODE_ID
end

---@return string[]
function ModeState.default_phases()
    local phases = {}
    for i = 1, #DEFAULT_PHASES do
        phases[i] = DEFAULT_PHASES[i]
    end
    return phases
end

---@param mode_id any
---@param phase any
---@return string
function ModeState.compose_substate(mode_id, phase)
    local mode = normalize_token(mode_id, DEFAULT_MODE_ID)
    local phase_name = normalize_token(phase, DEFAULT_PHASES[1])
    return string.format("running.%s.%s", mode, phase_name)
end

---@param substate any
---@return string|nil
---@return string|nil
function ModeState.parse_substate(substate)
    if type(substate) ~= "string" then
        return nil, nil
    end
    local mode_id, phase = string.match(substate, "^running%.([%w_]+)%.([%w_]+)$")
    if mode_id == nil or phase == nil then
        return nil, nil
    end
    return mode_id, phase
end

---@param raw any
---@return table
function ModeState.normalize_definition(raw)
    raw = type(raw) == "table" and raw or {}

    local mode_id = normalize_token(raw.id or raw.mode_id, DEFAULT_MODE_ID)
    local phases_in = type(raw.phases) == "table" and raw.phases or DEFAULT_PHASES
    local phases = {}
    local seen = {}

    for i = 1, #phases_in do
        local phase = normalize_token(phases_in[i], "")
        if phase ~= "" and seen[phase] ~= true then
            phases[#phases + 1] = phase
            seen[phase] = true
        end
    end

    if #phases < 1 then
        phases = ModeState.default_phases()
        seen = {}
        for i = 1, #phases do
            seen[phases[i]] = true
        end
    end

    local default_phase = normalize_token(raw.default_phase, phases[1])
    if seen[default_phase] ~= true then
        default_phase = phases[1]
    end

    local capability_flags = {}
    local capability_source = type(raw.capability_flags) == "table" and raw.capability_flags
        or type(raw.capabilities) == "table" and raw.capabilities
        or nil
    if capability_source then
        for key, value in pairs(capability_source) do
            capability_flags[key] = value
        end
    end

    local description = nil
    if raw.description ~= nil then
        description = tostring(raw.description)
    end

    return {
        id = mode_id,
        phases = phases,
        default_phase = default_phase,
        functional = raw.functional ~= false,
        capability_flags = capability_flags,
        description = description,
    }
end

---@param blackboard Blackboard
---@param phase string
---@return boolean
---@return string|nil
function ModeState.set_phase(blackboard, phase)
    if not blackboard or type(blackboard.get) ~= "function" then
        return false, "blackboard_unavailable"
    end

    local mode_definition = blackboard:get("core.mode_definition")
    local mode_id = mode_definition and mode_definition.id
        or blackboard:get("core.mode")
        or DEFAULT_MODE_ID
    local substate = ModeState.compose_substate(mode_id, phase)

    local state_machine = blackboard:get("core.state_machine")
    if not state_machine or type(state_machine.set_substate) ~= "function" then
        return false, "state_machine_unavailable"
    end

    return state_machine:set_substate(substate)
end

return ModeState
