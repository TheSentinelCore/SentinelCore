local CombatStateMachine = require("modules/combat/state_machine")
local SpellCatalog = require("modules/combat/spell_catalog")
local AuraCatalog = require("modules/combat/aura_catalog")
local SpellDispatcher = require("modules/combat/spell_dispatcher")
local CooldownTracker = require("modules/combat/cooldown_tracker")
local SwingTracker = require("modules/combat/swing_tracker")
local TargetSelector = require("modules/combat/target_selector")
local ChaseController = require("modules/combat/chase_controller")
local ContextBuilder = require("modules/combat/context_builder")
local ProfileRegistry = require("modules/combat/profiles/registry")
local Events = require("modules/combat/events")
local CombatZoneDetector = require("modules/combat/combat_zone_detector")
local Humanization = require("shared/humanization")

local SentinelCombat = {}
SentinelCombat.__index = SentinelCombat

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function same_guid(a, b)
    local ok_a, guid_a = safe_call(a, "get_guid")
    local ok_b, guid_b = safe_call(b, "get_guid")
    return ok_a and ok_b and tostring(guid_a) == tostring(guid_b)
end

function SentinelCombat:new(event_bus, blackboard, nav_adapter)
    local o = setmetatable({}, SentinelCombat)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav_adapter = nav_adapter
    o._subscriptions = {}
    o._source = nil
    o._current_target = nil
    return o
end

function SentinelCombat:initialize()
    self._spell_catalog = SpellCatalog:new()
    self._aura_catalog = AuraCatalog
    self._dispatcher = SpellDispatcher:new(self._event_bus, self._blackboard)
    self._cooldowns = CooldownTracker:new(self._spell_catalog, self._blackboard)
    self._swing_tracker = SwingTracker:new(self._event_bus, self._blackboard)
    self._state_machine = CombatStateMachine:new(self._event_bus, self._blackboard)
    self._target_selector = TargetSelector:new(self._event_bus, self._blackboard)
    self._chase_controller = ChaseController:new(self._event_bus, self._blackboard, self._nav_adapter)
    self._context_builder = ContextBuilder:new(self._blackboard)
    self._combat_zone = CombatZoneDetector:new(self._event_bus, self._blackboard)
    self._humanization = Humanization.new()

    local profile_module = ProfileRegistry.resolve(2, core and core.spell_book and core.spell_book.get_specialization_id and core.spell_book.get_specialization_id() or 0)
    self._profile = profile_module.build(self._blackboard, self._event_bus)

    self._blackboard:set("module.combat.catalog", self._spell_catalog)
    self._blackboard:set("module.combat.dispatcher", self._dispatcher)
    self._blackboard:set("module.combat.cooldowns", self._cooldowns)
    self._blackboard:set("module.combat.twist_mode", "auto")
    self._blackboard:set("module.combat.allow_estimated_twist", false)
    self._blackboard:set("module.combat.twist_window_ms", 350)
    self._blackboard:set("module.combat.enable_burst", true)
    self._blackboard:set("module.combat.preferred_blessing", "might")
    self._blackboard:set("module.combat.enabled", true)
    self._blackboard:set("module.combat.auto_engage", true)
    self._blackboard:set("module.combat.auto_engage_world", false)
    self._blackboard:set("module.combat.low_health_threshold", 0.35)
    self._blackboard:set("module.combat.retreat_outnumber_delta", 2)
    self._blackboard:set("module.combat.session_blood_unavailable", false)
    self._blackboard:set("module.combat.primary_seal_preference", "blood")
    self._blackboard:set("rotation.primary_seal", "blood")
    self._blackboard:set("rotation.desired_seal", nil)
    self._blackboard:set("rotation.desired_seal_reason", "ooc_no_seal")
    self._blackboard:set("combat.burst_context", false)
    self._blackboard:set("combat.gcd_until_ms", 0)
    self._blackboard:set("combat.leash_radius", 25)

    self:_subscribe(Events.ENGAGE_REQUESTED, function(payload)
        self:_handle_engage_requested(payload)
    end)
    self:_subscribe("bg:combat_handoff_requested", function(payload)
        self:_handle_engage_requested(payload)
    end)
    self:_subscribe(Events.DISENGAGE_REQUESTED, function(payload)
        self:disengage(payload and payload.reason or "disengage_requested")
    end)
    self:_subscribe("bg:retreat_requested", function(payload)
        self:disengage(payload and payload.reason or "bg_retreat")
    end)
    self:_subscribe("spell:manual_cast", function(payload)
        self:_handle_spell_event(payload, true)
    end)
    self:_subscribe("spell:world_cast", function(payload)
        self:_handle_spell_event(payload, false)
    end)
end

function SentinelCombat:_subscribe(event_name, handler)
    self._subscriptions[#self._subscriptions + 1] = self._event_bus:subscribe(event_name, handler)
end

function SentinelCombat:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
    self:disengage("shutdown")
end

function SentinelCombat:_handle_engage_requested(payload)
    payload = payload or {}
    self:engage(payload.target, payload)
end

function SentinelCombat:_handle_spell_event(payload, is_manual)
    payload = payload or {}
    local spell_id = tonumber(payload.spell_id or payload.spellId)
    if not spell_id then
        return
    end
    if not is_manual then
        local caster = payload.caster
        local player = self._blackboard:get("player.object")
        if caster and player and not same_guid(caster, player) then
            return
        end
    end
    local now_ms = self._blackboard:get("system.now_ms", 0)
    self._cooldowns:record_cast(spell_id, now_ms)
    if self._spell_catalog:is_gcd_spell(spell_id) then
        self._state_machine:transition("WAITING_GCD", "spell_confirmed")
    end
end

function SentinelCombat:_target_is_valid(target)
    if not target or not self._target_selector then
        return false
    end
    return self._target_selector:is_valid_enemy(target, {
        require_player = self:_require_player_targets(),
    })
end

function SentinelCombat:_require_player_targets()
    if self._blackboard:get("bg.active", false) == true then
        return true
    end
    return self._source == "bg" or self._source == "auto"
end

function SentinelCombat:_allow_idle_auto_engage()
    if self._blackboard:get("bg.combat_zone", false) == true then
        return true
    end
    if self._blackboard:get("bg.active", false) == true then
        return true
    end
    if self._blackboard:get("player.in_combat", false) == true then
        return true
    end
    return self._blackboard:get("module.combat.auto_engage_world", false) == true
end

function SentinelCombat:_auto_engage_target()
    local require_player = self._blackboard:get("bg.active", false) == true
        or self._blackboard:get("module.combat.auto_engage_world", false) ~= true
    local direct_target = self._blackboard:get("player.target")
    if self._target_selector:is_valid_enemy(direct_target, { require_player = require_player }) then
        return direct_target
    end
    return self._target_selector:get_best_target({
        require_player = require_player,
    })
end

function SentinelCombat:_ensure_target()
    if self:_target_is_valid(self._current_target) then
        self._blackboard:set("combat.target", self._current_target)
        return self._current_target
    end
    local selected = self._target_selector:get_best_target({
        require_player = self:_require_player_targets(),
    })
    if selected then
        self._current_target = selected
        self._blackboard:set("combat.target", selected)
        return selected
    end
    self._blackboard:set("combat.target", nil)
    return nil
end

function SentinelCombat:_check_safety()
    local hp = tonumber(self._blackboard:get("player.health_pct", 0)) or 0
    local enemies = tonumber(self._blackboard:get("combat.enemy_count_10yd", 0)) or 0
    local allies = tonumber(self._blackboard:get("combat.ally_count_30yd", 0)) or 0
    local health_threshold = tonumber(self._blackboard:get("module.combat.low_health_threshold", 0.35)) or 0.35
    local outnumber_delta = tonumber(self._blackboard:get("module.combat.retreat_outnumber_delta", 2)) or 2

    if hp <= health_threshold then
        self._event_bus:publish(Events.HEALTH_THRESHOLD, {
            health_pct = hp,
            threshold = health_threshold,
            direction = "below",
        })
        self:disengage("low_health")
        return false
    end

    if enemies >= allies + outnumber_delta and enemies > 0 then
        self._event_bus:publish(Events.OUTNUMBERED, {
            enemy_count = enemies,
            ally_count = allies,
            ratio = allies > 0 and (enemies / allies) or enemies,
        })
        self:disengage("outnumbered")
        return false
    end

    return true
end

function SentinelCombat:engage(target, opts)
    if self._blackboard:get("module.combat.enabled", true) ~= true then
        return
    end
    opts = opts or {}
    self._source = opts.source or opts.bg_key or "external"
    self._blackboard:set("combat.source", self._source)
    self._blackboard:set("combat.leash_center", opts.leash_center or self._blackboard:get("player.position"))
    self._blackboard:set("combat.leash_radius", tonumber(opts.leash_radius) or 25)

    if target and not self:_target_is_valid(target) then
        if self._source == "bg" or self._source == "auto" then
            target = nil
        else
            return
        end
    end

    self._current_target = target or self._target_selector:get_best_target({
        require_player = self:_require_player_targets(),
    })
    if not self._current_target then
        return
    end

    self._blackboard:set("combat.target", self._current_target)
    self._state_machine:transition("ENGAGING", "engage")
    self._event_bus:publish(Events.ENGAGED, {
        source = self._source,
        target = self._current_target,
    })
end

function SentinelCombat:disengage(reason)
    local active = self:is_in_combat() or self._state_machine:get_state() ~= "IDLE"
    self._chase_controller:stop(reason)
    self._current_target = nil
    self._source = nil
    self._blackboard:set("combat.target", nil)
    self._blackboard:set("combat.source", nil)
    self._blackboard:set("rotation.after_judgement_reseal", false)
    self._blackboard:set("rotation.twist.pending_reseal", false)
    self._profile:reset()
    self._state_machine:transition("IDLE", reason or "disengage")
    if active then
        self._event_bus:publish(Events.DISENGAGED, {
            reason = reason or "disengage",
        })
    end
end

function SentinelCombat:update(blackboard)
    if blackboard:get("module.combat.enabled", true) ~= true then
        if self._state_machine:get_state() ~= "IDLE" then
            self:disengage("combat_disabled")
        end
        return
    end

    local now_ms = blackboard:get("system.now_ms", 0)
    self._cooldowns:refresh(now_ms)
    self._context_builder:refresh(self._event_bus)
    self._combat_zone:update(blackboard)
    self._swing_tracker:update(blackboard)

    local dead = blackboard:get("player.is_dead", false) == true
    local ghost = blackboard:get("player.is_ghost", false) == true
    local mounted = blackboard:get("player.is_mounted", false) == true
    local mount_pending = blackboard:get("bg.mount.pending", false) == true
    if dead or ghost then
        if self._state_machine:get_state() ~= "IDLE" then
            self:disengage("dead_or_ghost")
        end
        return
    end
    if mounted or mount_pending then
        if self._state_machine:get_state() ~= "IDLE" then
            self:disengage("mounted_or_mount_pending")
        end
        return
    end

    if self._state_machine:get_state() == "IDLE" then
        local maintenance_status = self._profile:tick_maintenance(blackboard)
        if maintenance_status == "SUCCESS" or maintenance_status == "RUNNING" then
            return
        end
        if blackboard:get("module.combat.auto_engage", true) ~= true then
            return
        end
        if not self:_allow_idle_auto_engage() then
            return
        end
        local auto_target = self:_auto_engage_target()
        if not auto_target then
            return
        end
        self:engage(auto_target, {
            source = "auto",
            leash_center = blackboard:get("player.position"),
            leash_radius = tonumber(blackboard:get("combat.leash_radius", 25)) or 25,
        })
    end

    if not self:_check_safety() then
        return
    end

    local target = self:_ensure_target()
    if not target then
        self:disengage("target_lost")
        return
    end

    if blackboard:get("player.is_casting", false) or blackboard:get("player.is_channeling", false) then
        self._state_machine:transition("CASTING", "player_casting")
        return
    end

    self._chase_controller:update(target)
    self._profile:tick_off_gcd(blackboard)

    if self._cooldowns:is_gcd_ready(now_ms) then
        self._state_machine:transition("ENGAGING", "gcd_ready")
        local status = self._profile:tick_gcd(blackboard)
        if status == "FAILURE" then
            self._state_machine:transition("COOLDOWN", "no_legal_action")
        end
    else
        self._state_machine:transition("WAITING_GCD", "gcd_lock")
    end
end

function SentinelCombat:is_in_combat()
    local state = self._state_machine:get_state()
    return state ~= "IDLE"
end

function SentinelCombat:get_current_target()
    return self._current_target
end

function SentinelCombat:get_state()
    return self._state_machine:get_state()
end

function SentinelCombat:set_rotation(rotation_id)
    self._blackboard:set("module.combat.rotation_override", rotation_id)
end

function SentinelCombat:get_rotation_id()
    return self._blackboard:get("rotation.profile_id")
end

function SentinelCombat:set_enabled(enabled)
    local next_enabled = enabled == true
    local current_enabled = self:is_enabled()
    self._blackboard:set("module.combat.enabled", next_enabled)
    if current_enabled == next_enabled then
        return
    end
    if enabled ~= true then
        self:disengage("combat_disabled")
    end
end

function SentinelCombat:is_enabled()
    return self._blackboard:get("module.combat.enabled", true) == true
end

return SentinelCombat
