local AuraCatalog = require("kernel/catalogs/aura")
local Geometry = require("core/geometry")

local ContextBuilder = {}
ContextBuilder.__index = ContextBuilder

local function num(value)
    return tonumber(value) or 0
end

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

-- F5: delegate to Geometry.distance. Unmeasurable input now returns math.huge
-- (was a private 99999 sentinel), matching every other distance helper.
local function distance(a, b)
    return Geometry.distance(a, b)
end


function ContextBuilder:new(blackboard, izi_bridge)
    local o = setmetatable({}, ContextBuilder)
    o._blackboard = blackboard
    o._izi_bridge = izi_bridge
    o._last_active_seal = nil
    o._last_vengeance = 0
    return o
end

function ContextBuilder:refresh(event_bus)
    local player = self._blackboard:get("player.object")
    local target = self._blackboard:get("combat.target") or self._blackboard:get("player.target")
    local active_seal = nil
    if player then
        if AuraCatalog.has_any(player, AuraCatalog.seal_of_blood) then
            active_seal = "blood"
        elseif AuraCatalog.has_any(player, AuraCatalog.seal_of_command_ranks) then
            active_seal = "command"
        elseif AuraCatalog.has_any(player, AuraCatalog.seal_of_righteousness_ranks) then
            active_seal = "righteousness"
        end
    end

    if self._last_active_seal ~= active_seal then
        event_bus:publish("rotation:seal_changed", {
            from_seal = self._last_active_seal,
            to_seal = active_seal,
            reason = "context_refresh",
        })
        self._last_active_seal = active_seal
    end

    local player_pos = self._blackboard:get("player.position")
    local ok_target_pos, target_pos = safe_call(target, "get_position")
    local target_distance
    if ok_target_pos then
        target_distance = distance(player_pos, target_pos)
    else
        -- C6: ContextBuilder:refresh() runs BEFORE module.lua's _ensure_target()
        -- picks a fresh target for this tick (see chase_controller.lua for the
        -- other writer of this key). On an acquisition tick `target` above is
        -- still nil/positionless here even though a target is about to be
        -- chosen a few lines later in module.lua. Writing a hardcoded "far"
        -- sentinel in that gap would stomp the real distance chase_controller
        -- wrote last tick and spuriously fail `target_distance <= 10.0` below,
        -- suppressing burst_context on the very tick a nearby target is
        -- acquired. Instead, keep whatever is already on the blackboard (the
        -- last real measurement) and only fall back to Geometry's math.huge
        -- "unmeasurable" sentinel if nothing has ever been written.
        target_distance = tonumber(self._blackboard:get("combat.target_distance")) or math.huge
    end
    self._blackboard:set("combat.target_distance", target_distance)

    local vengeance = AuraCatalog.get_stacks(player, AuraCatalog.vengeance_proc_auras)
    if vengeance ~= self._last_vengeance then
        event_bus:publish("rotation:vengeance_changed", {
            previous_stacks = self._last_vengeance,
            stacks = vengeance,
        })
        self._last_vengeance = vengeance
    end
    self._blackboard:set("rotation.vengeance_stacks", vengeance)

    local player_in_combat = self._blackboard:get("player.in_combat", false) == true
    local combat_state = tostring(self._blackboard:get("combat.state", "IDLE") or "IDLE")
    local target_valid = false
    if target ~= nil then
        local ok_dead, dead = safe_call(target, "is_dead")
        target_valid = (not ok_dead) or dead ~= true
    end
    local hp = num(self._blackboard:get("player.health_pct", 0))
    local burst_enabled = self._blackboard:get("module.combat.enable_burst", true) == true
    local in_combat_context = player_in_combat or combat_state ~= "IDLE"

    -- Use combat forecast to gate burst if available
    local burst_context = burst_enabled
        and in_combat_context
        and target_valid
        and target_distance <= 10.0
        and hp > 0.40
    if burst_context and self._izi_bridge then
        local forecast = self._izi_bridge:get_forecast()
        local min_burst_duration = 6.0
        if forecast and forecast < min_burst_duration then
            burst_context = false
        end
    end
    self._blackboard:set("combat.burst_context", burst_context)

    local preferred_primary_seal = tostring(self._blackboard:get("module.combat.primary_seal_preference", "blood") or "blood")
    if preferred_primary_seal ~= "command" then
        preferred_primary_seal = "blood"
    end

    local primary_seal = self:_best_known_seal(preferred_primary_seal)
    self._blackboard:set("rotation.primary_seal", primary_seal)

    local desired_seal = nil
    local desired_reason = "ooc_no_seal"
    if in_combat_context and target_valid then
        if num(self._blackboard:get("combat.enemy_count_10yd", 0)) >= 2 then
            -- Use TTD to decide if worth switching to Command for AoE
            local worth_switching = true
            if self._izi_bridge then
                local ttd = self._izi_bridge:get_time_to_die(target)
                if ttd and ttd < 3.0 then
                    worth_switching = false
                end
            end
            if worth_switching then
                -- AoE wants Command, but never ask for a seal the character has
                -- not learned — below the Ret talent it degrades to what it has.
                desired_seal = self:_best_known_seal("command")
                desired_reason = "aoe"
            else
                desired_seal = primary_seal
                desired_reason = "single_target_fast_kill"
            end
        else
            desired_seal = primary_seal
            desired_reason = "single_target"
        end
    end

    self._blackboard:set("rotation.desired_seal", desired_seal)
    self._blackboard:set("rotation.desired_seal_reason", desired_reason)
end

-- Seal catalog keys in descending power order. A Paladin levelling 1->70 learns
-- them in reverse: Righteousness at 3, Command via the Ret talent, Blood at 64.
local SEAL_SPELL_KEYS = {
    blood = "seal_of_blood",
    command = "seal_of_command",
    righteousness = "seal_of_righteousness",
}
local SEAL_FALLBACK_ORDER = { "blood", "command", "righteousness" }

---Resolve `preferred` down to the strongest seal the character can actually cast.
---
---The spell catalog resolves ranks through core.spell_book.has_spell, so an
---unlearned seal returns nil. Publishing a desired seal the character does not
---know is what stranded the low-level rotation: apply_seal_before_combat required
---Seal of Blood, no seal ever went up, and judgement (gated on active_seal_present)
---never fired.
---
---With no catalog on the blackboard (offline tests, early boot) availability is
---unknowable, so the preference is returned unchanged rather than guessed at.
---@param preferred string
---@return string|nil the best castable seal, or nil if none are known
function ContextBuilder:_best_known_seal(preferred)
    local catalog = self._blackboard:get("module.combat.catalog")
    if not catalog or type(catalog.resolve_best_rank) ~= "function" then
        return preferred
    end

    local function is_known(seal)
        local key = SEAL_SPELL_KEYS[seal]
        if not key then
            return false
        end
        local ok, spell_id = pcall(catalog.resolve_best_rank, catalog, key)
        return ok and spell_id ~= nil
    end

    if is_known(preferred) then
        return preferred
    end

    -- Walk down from the preference: never upgrade past what was asked for.
    local below_preference = false
    for _, seal in ipairs(SEAL_FALLBACK_ORDER) do
        if seal == preferred then
            below_preference = true
        elseif below_preference and is_known(seal) then
            return seal
        end
    end
    return nil
end

return ContextBuilder
