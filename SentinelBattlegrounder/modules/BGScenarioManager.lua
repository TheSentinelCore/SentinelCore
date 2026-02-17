local BGData = require("modules/BGData")

local BGScenarioManager = {}
BGScenarioManager.__index = BGScenarioManager

local ROLE_NORMAL = "normal"
local ROLE_DEF_LAST_GY = "def_last_gy"

function BGScenarioManager:new()
    local o = setmetatable({}, BGScenarioManager)
    o._scenarios = {}
    o:_register_defaults()
    return o
end

function BGScenarioManager:_register_defaults()
    self:register(BGData.BG_ALTERAC, ROLE_DEF_LAST_GY, {
        id = "alterac_def_last_gy",
        label = "Alterac: Def Last GY",
        runner = "_defend_last_gy",
    })

    self:register(BGData.BG_ALTERAC, ROLE_NORMAL, {
        id = "none",
        label = "No Alterac scenario for role normal",
        runner = nil,
    })

    self:register(BGData.BG_WARSONG, ROLE_NORMAL, {
        id = "warsong_skirmish",
        label = "Warsong: Mid Pressure",
        runner = "_warsong_skirmish",
    })

    self:register(BGData.BG_WARSONG, ROLE_DEF_LAST_GY, {
        id = "warsong_skirmish",
        label = "Warsong: Mid Pressure",
        runner = "_warsong_skirmish",
    })

    self:register(BGData.BG_ARATHI, ROLE_NORMAL, {
        id = "arathi_skirmish",
        label = "Arathi: Node Pressure",
        runner = "_arathi_skirmish",
    })

    self:register(BGData.BG_ARATHI, ROLE_DEF_LAST_GY, {
        id = "arathi_skirmish",
        label = "Arathi: Node Pressure",
        runner = "_arathi_skirmish",
    })
end

function BGScenarioManager:register(bg_key, role, scenario)
    if not bg_key or not role or not scenario then
        return false
    end

    self._scenarios[bg_key] = self._scenarios[bg_key] or {}
    self._scenarios[bg_key][role] = scenario
    return true
end

function BGScenarioManager:resolve(bg_key, role)
    local by_bg = self._scenarios[bg_key]
    if not by_bg then
        return nil
    end

    if by_bg[role] then
        return by_bg[role]
    end

    return by_bg[ROLE_NORMAL]
end

return BGScenarioManager
