-- shared/spell_helper.lua
-- Canonical resolver for spell_helper and IZI SDK helper functions.
-- Provides cached resolution + method/plain call-style fallback.

local SpellHelper = {}

---Sentinel returned when the helper is unresolved (offline/mocked env) instead
---of a hard `true`. C3: the previous unconditional `return true` fail-open made
---every offline test exercise the "unknown" branch without ever distinguishing
---it from a real, verified `true` result. Existing callers across the codebase
---(condition_library, frost_conditions, retribution_conditions, target
---strategies) use truthiness (`if ok then`), so `SpellHelper.UNKNOWN` being
---non-nil/non-false keeps them behaving exactly as before. New/future callers
---that need to tell "verified castable" apart from "helper unavailable" can
---compare `result == true` vs `result == SpellHelper.UNKNOWN`.
SpellHelper.UNKNOWN = "unknown"

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

---Call a spell helper method using the Sylvannas IZI SDK method-call
---convention: fn(owner, ...), i.e. `owner:fn(...)`.
---C1: previously this tried a plain call (fn(...)) FIRST and only fell back
---to the method-call form on error. Every real Sylvannas source uses the
---colon/method form (spellbook-helper.md, spell-queue.md, fire-mage.md) where
---the first parameter is `self`/owner. The plain-call-first branch shifted
---every argument by one; when the callee didn't immediately index `self`,
---pcall silently succeeded with the WRONG answer reported as authoritative.
---That fallback existed only to match test mocks that omit `self`, not the
---real SDK — see CLAUDE.md's warning against this exact pattern for
---`spell_queue`. Method-call is now the only path.
-- VERIFY-IN-GAME: confirm the real spellbook helper accepts the colon form
-- for all three wrapped methods, e.g.:
--   game_eval("return tostring(spell_helper:is_spell_castable(133, core.object_manager.get_local_player(), core.object_manager.get_local_player(), false, false))")
--   game_eval("return tostring(spell_helper:is_spell_in_line_of_sight(133, core.object_manager.get_local_player(), core.object_manager.get_local_player()))")
--   game_eval("return tostring(spell_helper:get_spell_cooldown(133))")
---@param fn function The method to call
---@param owner table The owning module (for method-call convention)
---@param ... any Arguments
---@return boolean ok
---@return any result
function SpellHelper.call_method(fn, owner, ...)
    if type(fn) ~= "function" then
        return false, nil
    end
    return pcall(fn, owner, ...)
end

---Check if a spell is castable (cached helper resolution).
---@param spell_id number
---@param source table|nil
---@param dest table|nil
---@return boolean|string true, false, or SpellHelper.UNKNOWN when the helper is unresolved
function SpellHelper.is_spell_castable(spell_id, source, dest)
    local helper = SpellHelper.resolve_cached()
    if not helper or type(helper.is_spell_castable) ~= "function" then
        return SpellHelper.UNKNOWN -- C3: unresolved helper, not a verified castable=true
    end
    -- C2: trailing params are (skip_facing, skips_range). Every documented
    -- example (spellbook-helper.md:163) passes false, false — the caller
    -- wants a real castability check, not one that ignores facing/range.
    -- VERIFY-IN-GAME:
    --   game_eval("return tostring(spell_helper:is_spell_castable(133, core.object_manager.get_local_player(), core.object_manager.get_local_player(), false, false))")
    local ok, castable = SpellHelper.call_method(
        helper.is_spell_castable, helper,
        spell_id, source, dest, false, false
    )
    return ok and castable == true
end

---Check spell line of sight (cached helper resolution).
---@param spell_id number
---@param source table|nil
---@param dest table|nil
---@return boolean|string true, false, or SpellHelper.UNKNOWN when the helper is unresolved
function SpellHelper.is_spell_in_los(spell_id, source, dest)
    local helper = SpellHelper.resolve_cached()
    if not helper or type(helper.is_spell_in_line_of_sight) ~= "function" then
        return SpellHelper.UNKNOWN -- C3: unresolved helper, not a verified in_los=true
    end
    -- VERIFY-IN-GAME:
    --   game_eval("return tostring(spell_helper:is_spell_in_line_of_sight(133, core.object_manager.get_local_player(), core.object_manager.get_local_player()))")
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
