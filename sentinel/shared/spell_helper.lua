-- shared/spell_helper.lua
-- Canonical resolver for spell_helper and IZI SDK helper functions.
-- Provides cached resolution + method/plain call-style fallback.

local SpellHelper = {}

local _ref = nil
local _resolved = false
local _call_style = "self"

---Resolve spell_helper with caching.
---Always re-checks the global first (may change between tests/reloads).
---Falls back to require only once.
---@return table|nil
function SpellHelper.resolve_cached()
    if spell_helper then
        _ref = spell_helper
        _resolved = true
        _call_style = "self"
        return _ref
    end
    if not _resolved then
        local ok, mod = pcall(require, "common/utility/spell_helper")
        if ok and mod then
            _ref = mod
            _call_style = "self"
        end
        _resolved = true
    end
    return _ref
end

---Resolve spell_helper without caching (checks global every call).
---@return table|nil
function SpellHelper.resolve()
    if spell_helper then
        return spell_helper
    end
    local ok, mod = pcall(require, "common/utility/spell_helper")
    if ok and mod then
        return mod
    end
    return nil
end

---Call a spell helper method with automatic plain/method fallback.
---Tries plain-call (fn(...)) first (works for mock functions without self),
---then method-call (fn(owner, ...)) for IZI SDK convention.
---@param fn function The method to call
---@param owner table The owning module (for method-call convention)
---@param ... any Arguments
---@return boolean ok
---@return any result
function SpellHelper.call_method(fn, owner, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    -- Try plain-call first (fn(arg1, arg2, ...))
    -- This is safer — mock functions often omit the `self` parameter.
    -- If it errors (because the function expects self), we fall through.
    local ok, value = pcall(fn, ...)
    if ok then
        return true, value
    end
    -- Fallback to method-call (fn(owner, arg1, arg2, ...))
    return pcall(fn, owner, ...)
end

---Check if a spell is castable (cached helper resolution).
---@param spell_id number
---@param source table|nil
---@param dest table|nil
---@return boolean
function SpellHelper.is_spell_castable(spell_id, source, dest)
    local helper = SpellHelper.resolve_cached()
    if not helper or type(helper.is_spell_castable) ~= "function" then
        return true -- unknown = castable
    end
    local ok, castable = SpellHelper.call_method(
        helper.is_spell_castable, helper,
        spell_id, source, dest, true, true
    )
    return ok and castable == true
end

---Check spell line of sight (cached helper resolution).
---@param spell_id number
---@param source table|nil
---@param dest table|nil
---@return boolean
function SpellHelper.is_spell_in_los(spell_id, source, dest)
    local helper = SpellHelper.resolve_cached()
    if not helper or type(helper.is_spell_in_line_of_sight) ~= "function" then
        return true -- unknown = in LOS
    end
    local ok, in_los = SpellHelper.call_method(
        helper.is_spell_in_line_of_sight, helper,
        spell_id, source, dest
    )
    return ok and in_los == true
end

---Get spell cooldown (cached helper resolution).
---@param spell_id number
---@return number 0 if available or unknown
function SpellHelper.get_spell_cooldown(spell_id)
    local helper = SpellHelper.resolve_cached()
    if not helper or type(helper.get_spell_cooldown) ~= "function" then
        return 0
    end
    local ok, value = SpellHelper.call_method(helper.get_spell_cooldown, helper, spell_id)
    if ok and tonumber(value) then
        return tonumber(value)
    end
    return 0
end

return SpellHelper
