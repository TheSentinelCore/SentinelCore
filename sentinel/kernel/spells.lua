-- kernel/spells.lua
-- `Sentinel.spells` -- the casting-adjacent SDK predicates a rotation needs BEFORE it emits.
--
-- ================================================================================
-- WHY THIS EXISTS EVEN THOUGH THE COMMIT GATE ALREADY CHECKS CASTABILITY
-- ================================================================================
-- kernel/intent_executors.lua gates every cast on `is_spell_castable`, so at first glance a rotation
-- asking the same question is redundant. It is not, and the difference is behavioural:
--
--   * The GATE decides whether a cast HAPPENS.
--   * The CONDITION decides whether the rotation FALLS THROUGH to its next priority.
--
-- A frost mage whose Frostbolt is out of range must evaluate Ice Lance on the SAME tick. If the
-- rotation emitted Frostbolt anyway and let the gate reject it, that tick would produce no cast at
-- all -- the priority list would have "chosen" an action that silently did nothing. That is a real
-- behaviour change, not an optimisation, which is why `frost_conditions.spell_ready` keeps its
-- pre-check (ADR §13 risk 5: port it, do not rewrite it).
--
-- ================================================================================
-- NOT IN ADR §10, AND THAT IS THE POINT
-- ================================================================================
-- §10's surface has no home for these. They were found by porting a real rotation, which is exactly
-- what Phase 4 was for -- see 08a_API_GAPS.md. They are general: any rotation with a fallthrough
-- priority list needs to ask "can I cast this?" without committing to it, and any rotation with an
-- AoE branch needs to ask where to put it.

local Spells = {}
Spells.__index = Spells

---@param opts table|nil { spell_helper?, spell_prediction?, spell_queue? } -- injected in tests
function Spells:new(opts)
    opts = opts or {}
    local o = setmetatable({}, Spells)
    o._helper = opts.spell_helper
    o._prediction = opts.spell_prediction
    o._queue = opts.spell_queue
    return o
end

---Can this spell be cast at `dest` right now -- range, facing, cooldown, known-ness.
---
---Returns a LITERAL boolean. The underlying `shared/spell_helper` returns the string `UNKNOWN` when
---the spell-book helper is unresolved, and a truthy string leaking into a condition would make an
---unavailable spell look ready -- the same fail-open shape the commit gate had to be hardened
---against.
function Spells:is_castable(spell_id, source, dest)
    return self:castability(spell_id, source, dest) == true
end

---The TRI-STATE answer: true, false, or nil for "cannot say".
---
---`shared/spell_helper` returns the string `UNKNOWN` when the spell-book helper is unresolved, and
---collapsing that to a boolean throws away the distinction that matters -- because the right default
---is OPPOSITE for the two callers:
---
---  * THE COMMIT GATE must fail CLOSED. "Cannot say" is not permission to send a packet.
---  * A ROTATION CONDITION must fail OPEN. `frost_conditions.spell_ready` used `if not castable`,
---    so an unresolved helper read as castable and the rotation carried on. That is the correct
---    default there: the gate is now the real check, and a condition that goes false on "cannot say"
---    would silently stop the mage casting anything at all.
---
---Both defaults are now explicit at their call sites instead of being an accident of Lua truthiness.
---@return boolean|nil
function Spells:castability(spell_id, source, dest)
    local helper = self._helper
    if not helper or type(helper.is_spell_castable) ~= "function" then return nil end
    local ok, castable = pcall(helper.is_spell_castable, spell_id, source, dest)
    if not ok then return nil end
    if castable == true then return true end
    if castable == false then return false end
    return nil -- UNKNOWN
end

function Spells:is_in_los(spell_id, source, dest)
    return self:los_state(spell_id, source, dest) == true
end

---Tri-state line of sight, for the same reason `castability` is tri-state: the gate wants
---"unknown means no", a rotation condition wants "unknown means carry on".
---@return boolean|nil
function Spells:los_state(spell_id, source, dest)
    local helper = self._helper
    if not helper or type(helper.is_spell_in_los) ~= "function" then return nil end
    local ok, visible = pcall(helper.is_spell_in_los, spell_id, source, dest)
    if not ok then return nil end
    if visible == true then return true end
    if visible == false then return false end
    return nil
end

---Best ground-target position for an AoE spell, and how many units it would hit.
---@return table|nil position, number hit_count
function Spells:find_aoe_position(spell_id, range, min_targets, radius)
    local prediction = self._prediction
    if not prediction or type(prediction.find_optimal_position) ~= "function" then
        return nil, 0
    end
    local ok, position, hits = pcall(
        prediction.find_optimal_position, spell_id, range, min_targets, radius)
    if not ok then return nil, 0 end
    return position, tonumber(hits) or 0
end

return Spells
