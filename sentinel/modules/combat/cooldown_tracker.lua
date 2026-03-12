local CooldownTracker = {}
CooldownTracker.__index = CooldownTracker

local _spell_helper_ref = nil
local _spell_helper_resolved = false
local _spell_helper_call_style = "self"

local function resolve_spell_helper()
    if spell_helper then
        _spell_helper_ref = spell_helper
        _spell_helper_resolved = true
        _spell_helper_call_style = "self"
        return _spell_helper_ref
    end
    if not _spell_helper_resolved then
        local ok, mod = pcall(require, "common/utility/spell_helper")
        if ok and mod then
            _spell_helper_ref = mod
            _spell_helper_call_style = "self"
        end
        _spell_helper_resolved = true
    end
    return _spell_helper_ref
end

local function call_helper(fn, owner, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    if _spell_helper_call_style == "plain" then
        local ok, value = pcall(fn, ...)
        if ok then
            return true, value
        end
    end
    local ok, value = pcall(fn, owner, ...)
    if ok then
        return true, value
    end
    if _spell_helper_call_style ~= "plain" then
        return pcall(fn, ...)
    end
    return false, nil
end

function CooldownTracker:new(spell_catalog, blackboard)
    local o = setmetatable({}, CooldownTracker)
    o._spell_catalog = spell_catalog
    o._blackboard = blackboard
    o._last_cast_spell_id = nil
    o._gcd_ms = 1500
    return o
end

function CooldownTracker:record_cast(spell_id, now_ms)
    local spell_num = tonumber(spell_id)
    if not spell_num then
        return
    end
    self._last_cast_spell_id = spell_num
    self._blackboard:set("rotation.last_confirmed_spell_id", spell_num)
    if self._spell_catalog:is_gcd_spell(spell_num) then
        self._blackboard:set("combat.gcd_until_ms", (tonumber(now_ms) or 0) + self._gcd_ms)
    end
end

function CooldownTracker:get_last_cast_spell_id()
    return self._last_cast_spell_id
end

function CooldownTracker:is_gcd_ready(now_ms)
    return (tonumber(now_ms) or 0) >= self._blackboard:get("combat.gcd_until_ms", 0)
end

function CooldownTracker:get_cooldown(spell_id)
    local helper = resolve_spell_helper()
    if not helper or type(helper.get_spell_cooldown) ~= "function" then
        return 0
    end
    local ok, value = call_helper(helper.get_spell_cooldown, helper, spell_id)
    if ok and tonumber(value) then
        return tonumber(value)
    end
    return 0
end

function CooldownTracker:spell_ready(spell_id)
    return self:get_cooldown(spell_id) <= 0
end

function CooldownTracker:refresh(now_ms)
    if (tonumber(now_ms) or 0) >= self._blackboard:get("combat.gcd_until_ms", 0) then
        self._blackboard:set("combat.gcd_until_ms", 0)
    end
end

return CooldownTracker
