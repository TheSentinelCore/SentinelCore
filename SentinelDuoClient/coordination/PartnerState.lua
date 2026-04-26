-- PartnerState.lua — Parsed partner state model from heartbeat response.

---@class PartnerState
---@field phase string
---@field health_pct number
---@field mana_pct number
---@field bags_full boolean
---@field is_dead boolean
---@field in_instance boolean
---@field connected boolean
local PartnerState = {}
PartnerState.__index = PartnerState

local COMBAT_PHASES = {
    pull_running  = true,
    pull_ice_block = true,
    aoe_opening   = true,
    aoe_both      = true,
}

---@param json_table table|nil
---@return PartnerState
function PartnerState:new(json_table)
    local t = json_table or {}
    return setmetatable({
        phase       = t.phase       or "offline",
        health_pct  = t.health_pct  or 0,
        mana_pct    = t.mana_pct    or 0,
        bags_full   = t.bags_full   or false,
        is_dead     = t.is_dead     or false,
        in_instance = t.in_instance or false,
        connected   = t.connected   or false,
    }, PartnerState)
end

---@return boolean
function PartnerState:is_alive()
    return not self.is_dead
end

---@return boolean
function PartnerState:is_online()
    return self.connected
end

---@return boolean
function PartnerState:is_in_combat()
    return COMBAT_PHASES[self.phase] == true
end

return PartnerState
