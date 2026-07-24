local CombatStateMachine = require("modules/combat/state_machine")
local SpellCatalog = require("modules/combat/spell_catalog")
local AuraCatalog = require("modules/combat/aura_catalog")
local SpellDispatcher = require("modules/combat/spell_dispatcher")
local CooldownTracker = require("modules/combat/cooldown_tracker")
local SwingTracker = require("modules/combat/swing_tracker")
local TargetSelector = require("modules/combat/target_selector_v2")
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

-- B8: the Title-Case class_id -> name map now lives in shared/class_names.lua as the one
-- authority (questing's ClassIs conditions need Title-Case). Combat's `player.class_name`
-- blackboard key has always been UPPER-CASE, so upper-case here at combat's own boundary
-- rather than exposing a second casing from the shared module.
local ClassNames = require("shared/class_names")
local CLASS_ID_TO_NAME = setmetatable({}, {
    __index = function(_, class_id)
        local name = ClassNames.resolve(class_id)
        return name and name:upper() or nil
    end,
})

-- Reads a real numeric class_id off the local player, or nil when the player
-- object isn't available yet (e.g. during a loading screen) or get_class()
-- returns something that isn't a real class id. Never guesses a class.
-- VERIFY-IN-GAME: confirm get_local_player() becomes available and get_class()
-- returns a numeric id within the first few ticks after login/reload.
local function detect_class_id()
    local player = core and core.object_manager and core.object_manager.get_local_player
        and core.object_manager.get_local_player()
    if not player or type(player.get_class) ~= "function" then
        return nil
    end
    local ok, raw_class = pcall(player.get_class, player)
    if not ok then
        return nil
    end
    return tonumber(raw_class)
end

function SentinelCombat:new(event_bus, blackboard, nav_adapter, izi_bridge)
    local o = setmetatable({}, SentinelCombat)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav_adapter = nav_adapter
    o._izi_bridge = izi_bridge
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
    self._target_selector = TargetSelector:new(self._event_bus, self._blackboard, self._izi_bridge)
    self._chase_controller = ChaseController:new(self._event_bus, self._blackboard, self._nav_adapter)
    self._context_builder = ContextBuilder:new(self._blackboard, self._izi_bridge)
    self._combat_zone = CombatZoneDetector:new(self._event_bus, self._blackboard)
    self._humanization = Humanization.new()

    -- Store izi_bridge in blackboard for profiles to access
    self._blackboard:set("module.combat.izi_bridge", self._izi_bridge)
    self._blackboard:set("module.combat.rotation_engine", "dsl")

    -- Class detection: a real numeric class_id must be read before the
    -- profile is treated as final. `initialize()` can fire from the first
    -- on_update, which can happen during a loading screen when the local
    -- player object isn't valid yet — building the wrong class' rotation
    -- and never re-checking silently ran the wrong spec for the whole
    -- session (see audit finding B2). `self._class_confirmed` latches once
    -- a real class_id has been read; `update()` keeps retrying detection
    -- every tick until then and rebuilds the profile exactly once on the
    -- tick detection succeeds.
    local class_id = detect_class_id()
    self._class_confirmed = class_id ~= nil
    if not self._class_confirmed and core and type(core.log) == "function" then
        pcall(core.log, "[Combat] WARNING: player class not yet detectable, deferring profile confirmation (placeholder mage build in use until detection succeeds)")
    end
    class_id = class_id or 8
    self._class_id = class_id
    local spec_id = core and core.spell_book and core.spell_book.get_specialization_id and core.spell_book.get_specialization_id() or 0
    local profile_module = ProfileRegistry.resolve(class_id, spec_id)
    if not profile_module then
        -- Unit C: no profile registered for this class_id (registry.lua fails
        -- loud instead of silently falling back to Paladin). Disable combat
        -- cleanly rather than crash the ModuleRegistry lifecycle or run the
        -- wrong rotation.
        if core and type(core.log) == "function" then
            pcall(core.log, "[Combat] class_id=" .. tostring(class_id) .. " has no registered profile; combat disabled")
        end
        self._profile = nil
        self._unsupported_class = true
    else
        self._profile = profile_module.build(self._blackboard, self._event_bus)
    end
    self._blackboard:set("module.combat.profile", self._profile)

    self._blackboard:set("player.class_id", class_id)
    -- Store class name string (e.g. "WARRIOR") for quest modules that need it
    self._blackboard:set("player.class_name", CLASS_ID_TO_NAME[class_id] or "WARRIOR")
    self._blackboard:set("module.combat.catalog", self._spell_catalog)
    self._blackboard:set("module.combat.dispatcher", self._dispatcher)
    self._blackboard:set("module.combat.cooldowns", self._cooldowns)

    -- F12: static scalar defaults (no live objects, no computed values) collected in one
    -- place so the real, still-in-use config surface is unambiguous. This used to be ~30
    -- inline `self._blackboard:set(...)` calls, a dozen of which seeded the deleted grind
    -- subsystem (removed in Wave 1 / ADR-001) with no way to tell live keys from dead ones
    -- at a glance. Values and set order are unchanged from before this pass.
    local STATIC_DEFAULTS = {
        { "module.combat.twist_mode", "auto" },
        { "module.combat.allow_estimated_twist", false },
        { "module.combat.twist_window_ms", 350 },
        { "module.combat.enable_burst", true },
        { "module.combat.preferred_blessing", "might" },
        { "module.combat.enabled", true },
        { "module.combat.auto_engage", true },
        { "module.combat.auto_engage_world", false },
        { "module.combat.low_health_threshold", 0.35 },
        { "module.combat.retreat_outnumber_delta", 2 },
        { "module.combat.session_blood_unavailable", false },
        { "module.combat.primary_seal_preference", "blood" },
        { "rotation.primary_seal", "blood" },
        { "rotation.desired_seal", nil },
        { "rotation.desired_seal_reason", "ooc_no_seal" },
        { "combat.burst_context", false },
        { "combat.gcd_until_ms", 0 },
        { "combat.leash_radius", 25 },
    }
    for _, kv in ipairs(STATIC_DEFAULTS) do
        self._blackboard:set(kv[1], kv[2])
    end
    if self._unsupported_class then
        -- Must win over the STATIC_DEFAULTS "module.combat.enabled = true"
        -- entry above -- an unsupported class_id stays disabled.
        self._blackboard:set("module.combat.enabled", false)
    end
    self._cooldown_enter_ms = 0

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

    -- Subscribe to SensorHub transition events for reactive state management.
    -- These fire on state changes rather than every frame, reducing polling.

    self:_subscribe(Events.PLAYER_DEATH_CHANGED, function(payload)
        if payload.is_dead or payload.is_ghost then
            if self._state_machine:get_state() ~= "IDLE" then
                self:disengage("dead_or_ghost")
            end
        end
    end)

    self:_subscribe(Events.PLAYER_MOUNT_CHANGED, function(payload)
        if payload.is_mounted then
            if self._state_machine:get_state() ~= "IDLE" then
                self:disengage("mounted")
            end
        end
    end)

    self:_subscribe(Events.PLAYER_HEALTH_THRESHOLD, function(payload)
        local health_threshold = tonumber(self._blackboard:get("module.combat.low_health_threshold", 0.35)) or 0.35
        if payload.direction == "below" and payload.threshold == health_threshold then
            -- Same gate as _check_safety: while a mob is still actively attacking,
            -- fighting back beats standing there dying at melee range.
            if not self:_attacker_still_on_player() then
                self:disengage("low_health")
            end
        end
    end)

    self:_subscribe(Events.UNIT_BUFF_APPLIED, function(payload)
        local target = self._blackboard:get("combat.target")
        if target and payload.unit and same_guid(target, payload.unit) then
            if AuraCatalog.has_protection(target) then
                self._blackboard:set("combat.target_has_immunity", true)
            end
        end
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
    -- Only transition state when formally engaged. The pull phase fires
    -- spells before the engage event arrives — transitioning here would
    -- put the combat module into a phantom non-IDLE state with no source,
    -- causing chase_controller to navigate independently of the grind tree.
    if self._spell_catalog:is_gcd_spell(spell_id) and self._source ~= nil then
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

-- Low-HP recovery latch. Armed by disengage() whenever combat ends below the
-- low-health threshold; blocks ONLY idle auto-engage (explicit/forced engages
-- never consult it). Passive regen and profile maintenance heals do the
-- recovery; the latch releases on HP recovery, timeout, or the instant a mob
-- is actively attacking the player again (fight back rather than stand there).
-- Without it, `player.in_combat` alone re-triggered engage the tick after a
-- low_health disengage and the pair flip-flopped once per frame below 35% HP.
local LOW_HP_RECOVERY_EXIT_PCT = 0.60
local LOW_HP_RECOVERY_TIMEOUT_MS = 60000

function SentinelCombat:_attacker_still_on_player()
    return self._blackboard:get("player.in_combat", false) == true
        and self:_find_attacker() ~= nil
end

function SentinelCombat:_low_hp_recovery_active()
    local until_ms = self._low_hp_recovery_until_ms
    if not until_ms then
        return false
    end
    local now_ms = self._blackboard:get("system.now_ms", 0)
    local hp = tonumber(self._blackboard:get("player.health_pct", 0)) or 0
    if hp >= LOW_HP_RECOVERY_EXIT_PCT
        or now_ms >= until_ms
        or self:_attacker_still_on_player() then
        self._low_hp_recovery_until_ms = nil
        return false
    end
    return true
end

function SentinelCombat:_allow_idle_auto_engage()
    if self:_low_hp_recovery_active() then
        return false
    end
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

-- ============================================================================
-- F4: per-tick object snapshot
-- ============================================================================
-- get_all_objects is the most expensive Sylvannas call available (object-manager.md:45).
-- _find_attacker used to scan it fresh on every call; if a future call site needs the same
-- data within the same tick (e.g. a second lookup during the same update()), it would silently
-- pay for a second full scan the module has no way to know about. Cache the scan against the
-- tick clock the module already reads everywhere else (`system.now_ms`, set once per frame by
-- system_sensor.lua) so repeated lookups within one tick share a single scan, while a genuinely
-- new tick still gets a fresh one.
SentinelCombat._object_scan_count = 0 -- exposed for offline testing only (F4 regression guard)

---Full object-manager scan, cached for the duration of the current tick (keyed by
---blackboard `system.now_ms`, the module's existing per-frame clock).
---@return table|nil objects
function SentinelCombat:_get_all_objects_this_tick()
    if not core or not core.object_manager then return nil end
    local now_ms = self._blackboard and self._blackboard:get("system.now_ms", 0) or 0
    local cache = self._tick_object_cache
    if cache and cache.tick == now_ms then
        return cache.objects
    end
    SentinelCombat._object_scan_count = SentinelCombat._object_scan_count + 1
    local ok, objects = pcall(core.object_manager.get_all_objects)
    local result = (ok and type(objects) == "table") and objects or nil
    self._tick_object_cache = { tick = now_ms, objects = result }
    return result
end

---Find a mob that is actively targeting (attacking) the player.
---Only returns NPC mobs that have the player as their target.
---@return table|nil unit The attacker, or nil
function SentinelCombat:_find_attacker()
    local player = self._blackboard:get("player.object")
    if not player then return nil end
    if not core or not core.object_manager then return nil end
    local ok_guid, player_guid = pcall(player.get_guid, player)
    if not ok_guid then return nil end
    local player_guid_str = tostring(player_guid)

    local objects = self:_get_all_objects_this_tick()
    if type(objects) ~= "table" then return nil end

    for _, obj in ipairs(objects) do
        if self._target_selector:is_valid_enemy(obj, { require_player = false }) then
            local ok_t, mob_target = pcall(obj.get_target, obj)
            if ok_t and mob_target then
                local ok_tg, tg = pcall(mob_target.get_guid, mob_target)
                if ok_tg and tostring(tg) == player_guid_str then
                    return obj
                end
            end
        end
    end
    return nil
end

function SentinelCombat:_auto_engage_target()
    local require_player = self._blackboard:get("bg.active", false) == true
        or self._blackboard:get("module.combat.auto_engage_world", false) ~= true
    local direct_target = self._blackboard:get("player.target")
    local in_combat = self._blackboard:get("player.in_combat", false) == true

    -- When being attacked, allow the direct target without require_player restriction
    if direct_target then
        local dt_require = require_player and not in_combat
        if self._target_selector:is_valid_enemy(direct_target, { require_player = dt_require }) then
            return direct_target
        end
    end

    -- When in combat, find a mob actively targeting (attacking) the player.
    -- This is safer than get_best_target({require_player=false}) which would
    -- pick up random non-aggro mobs and prevent rest from ever firing.
    if in_combat then
        local attacker = self:_find_attacker()
        if attacker then
            return attacker
        end
    end

    return self._target_selector:get_best_target({
        require_player = require_player,
    })
end

--- A forced (quest) target is usually NEUTRAL — Elwynn's Young Wolves never aggro — and
--- every consumer of GrindTargetStrategy:is_valid_enemy (the rotation's own target
--- validity checks included) rejects neutral units. The exemption is scoped to EXACTLY
--- this unit via combat.forced_target_guid: the strategy accepts a neutral unit only
--- when its GUID matches. (The first fix flipped module.grind.attack_neutral for the
--- whole engagement, which made every neutral mob on screen a valid idle auto-engage
--- target — live-caught as combat stealing the player target for a kobold 23yd away
--- while the quest kill chased its own mob.)
function SentinelCombat:_set_forced_target(target)
    self._forced_target = target
    self._forced_progress = nil
    local guid = nil
    if target and target.get_guid then
        local ok, g = pcall(target.get_guid, target)
        if ok then guid = g end
    end
    self._blackboard:set("combat.forced_target_guid", guid)
end

function SentinelCombat:_clear_forced_target()
    self._forced_target = nil
    self._forced_progress = nil
    self._blackboard:set("combat.forced_target_guid", nil)
end

-- Zero-HP-progress window for a forced (quest) target. Evade/leash-reset,
-- despawn, and immunity all leave is_dead()==false — without these checks a
-- questing-forced GUID was chased forever. There is no evade flag in the SDK
-- (game-object.md exposes only is_valid); an evading mob heals to full and
-- then takes no damage, so the HP-stall window catches it.
local FORCED_STALL_TIMEOUT_MS = 20000

function SentinelCombat:_forced_target_still_valid(unit)
    local ok_dead, dead = safe_call(unit, "is_dead")
    if ok_dead and dead == true then
        return false
    end
    -- Despawned / gone from the object manager.
    local ok_valid, valid = safe_call(unit, "is_valid")
    if ok_valid and valid == false then
        return false
    end
    -- Immunity flagged by the UNIT_BUFF_APPLIED handler: an immune forced
    -- target is as unkillable as a despawned one.
    if self._blackboard:get("combat.target_has_immunity", false) == true then
        return false
    end
    -- HP stall: progress means the target's HP went DOWN (an evading mob's
    -- heal-to-full must not count as progress).
    local now_ms = self._blackboard:get("system.now_ms", 0)
    local ok_hp, hp = safe_call(unit, "get_health_percentage")
    hp = ok_hp and tonumber(hp) or nil
    local prog = self._forced_progress
    if not prog or prog.hp == nil or hp == nil then
        self._forced_progress = { hp = hp, since_ms = now_ms }
    elseif hp < prog.hp then
        prog.hp = hp
        prog.since_ms = now_ms
    elseif now_ms - prog.since_ms >= FORCED_STALL_TIMEOUT_MS then
        return false
    end
    return true
end

-- How long an immune GUID stays skipped by the selector. TBC leveling
-- immunities (bubble, evade-adjacent protection auras) outlive a kill window;
-- 30s keeps the mob re-targetable once the aura is long gone.
local IMMUNE_BLACKLIST_MS = 30000

function SentinelCombat:_blacklist_immune_target(unit)
    local ok, guid = safe_call(unit, "get_guid")
    if not ok or guid == nil then
        return
    end
    local now_ms = self._blackboard:get("system.now_ms", 0)
    local blacklist = self._blackboard:get("combat.immune_target_guids")
    if type(blacklist) ~= "table" then
        blacklist = {}
    end
    blacklist[tostring(guid)] = now_ms + IMMUNE_BLACKLIST_MS
    self._blackboard:set("combat.immune_target_guids", blacklist)
end

function SentinelCombat:_ensure_target()
    -- Consume combat.target_has_immunity (set by the UNIT_BUFF_APPLIED handler;
    -- previously write-only). An immune grind/auto target gets its GUID
    -- blacklisted so the selector skips it for a period; an immune FORCED
    -- target falls through to _forced_target_still_valid below, which clears it
    -- via the same path as any other invalid forced target.
    if self._current_target and self._current_target ~= self._forced_target
        and self._blackboard:get("combat.target_has_immunity", false) == true then
        self:_blacklist_immune_target(self._current_target)
        self._blackboard:set("combat.target_has_immunity", false)
        self._current_target = nil
    end
    if self:_target_is_valid(self._current_target) then
        self._blackboard:set("combat.target", self._current_target)
        return self._current_target
    end
    -- A forced (quest) target stays current while it lives, even though the selector rejects it
    -- for being neutral. Without this it would be dropped on the very next tick after engage.
    if self._forced_target and self._forced_target == self._current_target then
        if self:_forced_target_still_valid(self._forced_target) then
            self._blackboard:set("combat.target", self._current_target)
            return self._current_target
        end
        self:_clear_forced_target()
    end
    -- Defensive chain (source="defense"): only ever fights units actively attacking
    -- the player. _find_attacker can never return a neutral non-attacker (it only
    -- yields units whose target is the player), so the chain is self-limiting: it
    -- ends with a clean disengage the moment nothing is attacking. It must NOT fall
    -- through to the selector, whose "best target" has no attacker notion.
    if self._source == "defense" then
        local attacker = self:_find_attacker()
        if attacker then
            self._current_target = attacker
            self._blackboard:set("combat.target", attacker)
            return attacker
        end
        self:disengage("defense_complete")
        return nil
    end
    -- A questing engagement never self-selects a replacement target. When the forced
    -- target dies (or goes invalid), control goes BACK to the kill action, which picks
    -- the next entry-filtered quest mob and re-requests engagement. Falling through to
    -- the selector here is how the bot fought neutral Kobold Vermin and then A RABBIT
    -- under source="questing" (live-caught): the selector's idea of "best target" has no
    -- notion of which entries the quest needs. Real aggressors re-enter combat through
    -- _find_attacker, which only ever yields units attacking the player.
    -- EXCEPTION: if the forced kill ended while OTHER mobs are still beating the
    -- player, handing control back leaves nothing fighting back. Chain into a
    -- DEFENSIVE engagement (not questing-sourced — self-defense may keep chaining
    -- until no attacker remains) against the live attacker.
    if self._source == "questing" then
        local attacker = self:_attacker_still_on_player() and self:_find_attacker() or nil
        self:disengage("quest_target_done")
        if attacker then
            self:engage(attacker, { source = "defense" })
            if self._current_target then
                return self._current_target
            end
        end
        return nil
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

    -- Use health prediction if available for proactive safety
    local effective_hp = hp
    if self._izi_bridge then
        local player = self._blackboard:get("player.object")
        local predicted_pct = self._izi_bridge:predict_hp_pct(player, 3.0)
        if predicted_pct and predicted_pct < hp then
            effective_hp = predicted_pct
        end
    end

    -- Low HP with a mob still actively attacking: do NOT disengage — the mob keeps
    -- meleeing either way, and idle auto-engage would re-enter combat next tick
    -- anyway (the engage/disengage pair oscillated once per frame below the
    -- threshold). Only bail when nothing is attacking; disengage() then arms the
    -- recovery latch that keeps idle auto-engage quiet until HP recovers.
    if effective_hp <= health_threshold and not self:_attacker_still_on_player() then
        self._event_bus:publish(Events.HEALTH_THRESHOLD, {
            health_pct = hp,
            predicted_pct = effective_hp,
            threshold = health_threshold,
            direction = "below",
        })
        self:disengage("low_health")
        return false
    end

    -- outnumber_delta tunes the enemy/ally ratio that trips this (default 2,
    -- i.e. "enemies >= allies + 2"). Whether get_ally_list_around includes
    -- the player is an open in-game question (audit B6) — that only shifts
    -- where the trigger sits (2-vs-3 vs 1-vs-2), it does not change the
    -- disengage/backoff mechanism below. Without OUTNUMBERED_BACKOFF_MS a
    -- solo pull of `outnumber_delta` mobs re-triggers engage (via auto-engage
    -- next tick) then immediately disengage("outnumbered") again, every
    -- single frame, with both mobs still attacking — see engage()'s backoff
    -- gate.
    if enemies >= allies + outnumber_delta and enemies > 0 then
        self._event_bus:publish(Events.OUTNUMBERED, {
            enemy_count = enemies,
            ally_count = allies,
            ratio = allies > 0 and (enemies / allies) or enemies,
        })
        self:disengage("outnumbered")
        return false
    end

    -- Leash check: don't chase mobs too far from the engagement origin
    local leash_center = self._blackboard:get("combat.leash_center")
    local leash_radius = tonumber(self._blackboard:get("combat.leash_radius", 25)) or 25
    local player_pos = self._blackboard:get("player.position")
    if leash_center and type(player_pos) == "table" then
        local dx = (tonumber(player_pos.x) or 0) - (tonumber(leash_center.x) or 0)
        local dy = (tonumber(player_pos.y) or 0) - (tonumber(leash_center.y) or 0)
        local dz = (tonumber(player_pos.z) or 0) - (tonumber(leash_center.z) or 0)
        local leash_dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if leash_dist > leash_radius then
            self:disengage("leash_exceeded")
            return false
        end
    end

    return true
end

-- Minimum time after an "outnumbered" disengage before engage() will accept
-- a new engagement (audit B6). Without this, questing/auto re-publish an
-- engage request the very next tick (B3), _check_safety immediately
-- disengages again, and the pair oscillates once per frame while the mobs
-- keep attacking. VERIFY-IN-GAME: tune against real pull cadence.
local OUTNUMBERED_BACKOFF_MS = 2000

function SentinelCombat:engage(target, opts)
    if self._blackboard:get("module.combat.enabled", true) ~= true then
        return
    end
    -- A dead or ghost-running player can never accept an engagement — questing's Kill
    -- action re-publishes engage_requested every commit, and without this the state
    -- machine churned ENGAGING→disengage("dead_or_ghost") once per tick during recovery.
    if self._blackboard:get("player.is_dead", false) == true
        or self._blackboard:get("player.is_ghost", false) == true then
        return
    end
    local now_ms = self._blackboard:get("system.now_ms", 0)
    if self._outnumbered_backoff_until_ms and now_ms < self._outnumbered_backoff_until_ms then
        return
    end
    opts = opts or {}
    -- Questing owns combat while its forced target lives: an idle auto-engage or bg
    -- engage must not steal the player target mid-kill (live-caught: the kill action
    -- chased its mob at 13yd while an auto engage re-targeted a kobold 23yd away and the
    -- rotation swung at air). A forced request may always replace a forced target.
    local incoming_forced = target ~= nil
        and (opts.force == true or (opts.source or opts.bg_key) == "questing")
    if self._forced_target and not incoming_forced then
        local ok_fd, forced_dead = pcall(self._forced_target.is_dead, self._forced_target)
        if ok_fd and forced_dead ~= true then
            return
        end
    end
    -- combat.leash_center anchors the "don't chase mobs too far" check in
    -- _check_safety. It must only be set on entry into combat from IDLE —
    -- setting it on every engage() call (audit B3) tracks the player's own
    -- position each tick (execute_kill re-publishes engage_requested every
    -- tick while in range, with no dedup), so leash_dist stays ~0 forever
    -- and disengage("leash_exceeded") becomes unreachable.
    local already_engaged = self:is_in_combat()
    self._source = opts.source or opts.bg_key or "external"
    self._blackboard:set("combat.source", self._source)
    if not already_engaged then
        self._blackboard:set("combat.leash_center", opts.leash_center or self._blackboard:get("player.position"))
        self._blackboard:set("combat.leash_radius", tonumber(opts.leash_radius) or 25)
    end

    -- An explicitly requested quest target is trusted even if the target selector would reject it.
    -- Quest mobs are frequently NEUTRAL (Elwynn's Young Wolves are `enemy = false` and never
    -- aggro), so `_target_is_valid` discards them, engage falls through to get_best_target, that
    -- returns nil, and the bot stands next to the mob it was told to kill. Auto/BG engagement keeps
    -- the validity check — this only trusts a caller that named a specific unit on purpose.
    local function is_alive(unit)
        if not unit or not unit.is_dead then return false end
        local ok, dead = pcall(unit.is_dead, unit)
        return ok and dead ~= true
    end
    local forced = target ~= nil
        and (opts.force == true or self._source == "questing")
        and is_alive(target)

    if target and not forced and not self:_target_is_valid(target) then
        -- bg/auto and every other source alike: drop it and let the selector choose.
        target = nil
    end
    if forced then
        self:_set_forced_target(target)
    else
        self:_clear_forced_target()
    end

    local previous_target = self._current_target
    self._current_target = target or self._target_selector:get_best_target({
        require_player = self:_require_player_targets(),
    })
    if not self._current_target then
        return
    end

    -- combat.target_has_immunity describes exactly one unit. Questing re-publishes
    -- engage for the SAME target every tick, so only a genuine target change may
    -- reset the flag — resetting unconditionally would erase it before
    -- _ensure_target ever consumed it.
    if not same_guid(previous_target, self._current_target) then
        self._blackboard:set("combat.target_has_immunity", false)
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
    -- Recall the pet (passive + follow) so a Voidwalker/Water Elemental stops
    -- attacking and cannot chain-pull between kills. The controller key is only
    -- set by pet-class profiles; every call is guarded for SDK absence inside.
    local pet_ctrl = self._blackboard:get("module.combat.pet_controller")
    if pet_ctrl and type(pet_ctrl.passive) == "function" then
        pcall(pet_ctrl.passive, pet_ctrl)
    end
    -- Clean up cast cancellation movement so the player doesn't walk forward forever
    if self._blackboard:get("combat._cancel_cast_pending") then
        if core and core.input and type(core.input.move_forward_stop) == "function" then
            pcall(core.input.move_forward_stop)
        end
        self._blackboard:set("combat._cancel_cast_pending", false)
    end
    self._current_target = nil
    self._source = nil
    self:_clear_forced_target()
    self._blackboard:set("combat.target", nil)
    self._blackboard:set("combat.source", nil)
    self._blackboard:set("rotation.after_judgement_reseal", false)
    self._blackboard:set("rotation.twist.pending_reseal", false)
    if reason == "outnumbered" then
        local now_ms = self._blackboard:get("system.now_ms", 0)
        self._outnumbered_backoff_until_ms = now_ms + OUTNUMBERED_BACKOFF_MS
    end
    self._progress_guard = nil
    self._blackboard:set("combat.target_has_immunity", false)
    -- Combat ending below the low-health threshold (whatever the reason) arms
    -- the recovery latch — see _low_hp_recovery_active.
    if active then
        local hp = tonumber(self._blackboard:get("player.health_pct", 1)) or 1
        local health_threshold = tonumber(self._blackboard:get("module.combat.low_health_threshold", 0.35)) or 0.35
        if hp <= health_threshold then
            local now_ms = self._blackboard:get("system.now_ms", 0)
            self._low_hp_recovery_until_ms = now_ms + LOW_HP_RECOVERY_TIMEOUT_MS
        end
    end
    -- Unit C: self._profile can be nil when the class_id has no registered
    -- profile (combat disabled) -- guard so a stray disengage() (event
    -- handlers are wired regardless of resolve outcome) can't crash.
    if self._profile then
        self._profile:reset()
    end
    self._state_machine:transition("IDLE", reason or "disengage")
    if active then
        self._event_bus:publish(Events.DISENGAGED, {
            reason = reason or "disengage",
        })
    end
end

function SentinelCombat:_combat_diag(blackboard, msg)
    local now = blackboard:get("system.now_ms", 0)
    if not self._last_diag_ms or (now - self._last_diag_ms) >= 2000 then
        self._last_diag_ms = now
        if core and type(core.log) == "function" then
            local state = self._state_machine and self._state_machine:get_state() or "?"
            local target = self._current_target and "yes" or "no"
            local source = self._source or "nil"
            local block = blackboard:get("rotation.last_block_reason", "-")
            pcall(core.log, string.format("[Combat] %s | state=%s target=%s source=%s block=%s", msg, state, target, source, tostring(block)))
        end
    end
end

-- Retries class detection until a real numeric class_id is read, then
-- rebuilds the profile exactly once for the confirmed class and latches
-- `_class_confirmed` so this never runs again. No-op once confirmed.
function SentinelCombat:_confirm_class_detection(blackboard)
    if self._class_confirmed then
        return
    end
    local class_id = detect_class_id()
    if not class_id then
        return
    end
    self._class_confirmed = true
    if class_id == self._class_id then
        return
    end
    self._class_id = class_id
    local spec_id = core and core.spell_book and core.spell_book.get_specialization_id and core.spell_book.get_specialization_id() or 0
    local profile_module = ProfileRegistry.resolve(class_id, spec_id)
    if not profile_module then
        -- Unit C: same fail-loud guard as initialize() -- the confirmed class_id
        -- has no registered profile. Disable combat cleanly instead of crashing
        -- on a nil `.build` or silently keeping/running the previous rotation.
        self._profile = nil
        self._unsupported_class = true
        self._blackboard:set("module.combat.profile", nil)
        self._blackboard:set("player.class_id", class_id)
        self._blackboard:set("player.class_name", CLASS_ID_TO_NAME[class_id] or "WARRIOR")
        self._blackboard:set("module.combat.enabled", false)
        if core and type(core.log) == "function" then
            pcall(core.log, "[Combat] confirmed class_id=" .. tostring(class_id) .. " has no registered profile; combat disabled")
        end
        return
    end
    self._profile = profile_module.build(self._blackboard, self._event_bus)
    self._blackboard:set("module.combat.profile", self._profile)
    self._blackboard:set("player.class_id", class_id)
    self._blackboard:set("player.class_name", CLASS_ID_TO_NAME[class_id] or "WARRIOR")
    if core and type(core.log) == "function" then
        pcall(core.log, string.format("[Combat] player class confirmed as %s (id=%d), profile rebuilt", CLASS_ID_TO_NAME[class_id] or "?", class_id))
    end
end

-- Loss-of-control detection. The SDK has no player:is_stunned()/is_feared();
-- the one CC surface on a unit is get_loss_of_control_info() (game-object.md:575)
-- -> { valid, spell_id, start_time, end_time, duration, type, lockout_school }.
-- `valid == true` means a loss-of-control effect is live. While controlled the
-- update loop suspends chase movement and spell queueing (the fear path made
-- chase_controller issue look_at/move_to against the fear walk and the rotation
-- burned queues) and resumes automatically when the info goes invalid. When the
-- method is absent (older SDK), this returns false and behavior is unchanged.
function SentinelCombat:_loss_of_control_active(blackboard)
    local player = blackboard:get("player.object")
    local ok, info = safe_call(player, "get_loss_of_control_info")
    if not ok or type(info) ~= "table" then
        return false
    end
    return info.valid == true
end

-- Emergency flee consumer (combat.emergency_flee is set by the mage's
-- emergency_escape action / cleared by frost state reset — it had zero readers).
-- Disengage, then issue a nav flee toward a point ~FLEE_DISTANCE_YD directly
-- away from the (pre-disengage) target through the shared NavAdapter, and
-- release ownership so questing can re-claim the adapter. Every adapter call is
-- pcall-guarded; with no usable positions the flee degrades to disengage+log.
local FLEE_DISTANCE_YD = 30

function SentinelCombat:_execute_emergency_flee(blackboard)
    local player_pos = blackboard:get("player.position")
    local ok_tp, target_pos = safe_call(self._current_target, "get_position")
    self:disengage("emergency_flee")
    if core and type(core.log) == "function" then
        pcall(core.log, "[Combat] combat_emergency_flee")
    end
    if type(player_pos) ~= "table" or not ok_tp or type(target_pos) ~= "table" then
        return
    end
    local dx = (tonumber(player_pos.x) or 0) - (tonumber(target_pos.x) or 0)
    local dy = (tonumber(player_pos.y) or 0) - (tonumber(target_pos.y) or 0)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then
        dx, dy, len = 1, 0, 1
    end
    local dest = {
        x = (tonumber(player_pos.x) or 0) + dx / len * FLEE_DISTANCE_YD,
        y = (tonumber(player_pos.y) or 0) + dy / len * FLEE_DISTANCE_YD,
        z = tonumber(player_pos.z) or 0,
    }
    if not self._nav_adapter then
        return
    end
    pcall(function()
        self._nav_adapter:move_to(dest, { use_navmesh = true, owner = "combat", preempt = true })
        self._nav_adapter:release("combat")
    end)
end

local NO_PROGRESS_TIMEOUT_MS = 15000

-- True when the current engagement has made zero progress — target HP not
-- decreasing and distance to it not closing — for NO_PROGRESS_TIMEOUT_MS.
-- Tracker resets on target change (guid) and on disengage.
function SentinelCombat:_progress_guard_stalled(blackboard, target, now_ms)
    local ok_guid, guid = safe_call(target, "get_guid")
    guid = ok_guid and tostring(guid) or nil
    local ok_hp, hp = safe_call(target, "get_health_percentage")
    hp = ok_hp and tonumber(hp) or nil
    local dist = tonumber(blackboard:get("combat.target_distance"))
    local guard = self._progress_guard
    if not guard or guard.guid ~= guid then
        self._progress_guard = { guid = guid, hp = hp, dist = dist, since_ms = now_ms }
        return false
    end
    local progressed = false
    if hp and (guard.hp == nil or hp < guard.hp) then
        guard.hp = hp
        progressed = true
    end
    if dist and (guard.dist == nil or dist < guard.dist) then
        guard.dist = dist
        progressed = true
    end
    if progressed then
        guard.since_ms = now_ms
        return false
    end
    return (now_ms - guard.since_ms) >= NO_PROGRESS_TIMEOUT_MS
end

function SentinelCombat:update(blackboard)
    if blackboard:get("module.combat.enabled", true) ~= true then
        if self._state_machine:get_state() ~= "IDLE" then
            self:disengage("combat_disabled")
        end
        return
    end

    self:_confirm_class_detection(blackboard)

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

    -- Consume combat.emergency_flee (see _execute_emergency_flee). The flag is
    -- cleared unconditionally — a stale flag with combat already over must not
    -- fire a flee on some later engagement.
    if blackboard:get("combat.emergency_flee", false) == true then
        blackboard:set("combat.emergency_flee", false)
        if self:is_in_combat() then
            self:_execute_emergency_flee(blackboard)
            return
        end
    end

    if self._state_machine:get_state() == "IDLE" then
        self:_combat_diag(blackboard, "idle")

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

    -- Guard: phantom combat state — spell events or stale transitions left
    -- the state machine in a non-IDLE state without a formal engagement.
    -- Reset to IDLE so nothing tries to act without a real source.
    if self._source == nil then
        if self._state_machine:get_state() ~= "IDLE" then
            self._state_machine:transition("IDLE", "phantom_reset")
        end
        return
    end

    if not self:_check_safety() then
        return
    end

    -- A hardcast aimed at a corpse is pure waste — stop it before _ensure_target
    -- replaces/clears the dead target. The rotation only ever casts at
    -- combat.target, so _current_target is the cast's target. cancel_spells()
    -- is the SDK's cast-stop (input.md: Spell Cancellation).
    if blackboard:get("player.is_casting", false) == true
        and core and core.input and type(core.input.cancel_spells) == "function" then
        local ok_dead, cur_dead = safe_call(self._current_target, "is_dead")
        if ok_dead and cur_dead == true then
            pcall(core.input.cancel_spells)
        end
    end

    local target = self:_ensure_target()
    if not target then
        self:disengage("target_lost")
        return
    end

    -- Loss of control (fear/stun/…): suspend chase movement and spell queueing
    -- and wait the CC out — do NOT disengage. The progress guard is reset so a
    -- long CC can never be miscounted as a no-progress stall.
    if self:_loss_of_control_active(blackboard) then
        self._chase_controller:stop("loss_of_control")
        self._progress_guard = nil
        self:_combat_diag(blackboard, "loss_of_control")
        return
    end

    -- Independent no-progress guard: the COOLDOWN no-legal-action timeout is
    -- unreachable while profile fallbacks (melee/wand) return SUCCESS every
    -- tick, so an unreachable target (ledge, pathing hole) was chased forever.
    -- No HP progress AND no distance progress for the window means the
    -- engagement is going nowhere.
    if self:_progress_guard_stalled(blackboard, target, now_ms) then
        if self._forced_target and self._forced_target == self._current_target then
            self:_clear_forced_target()
        end
        self:disengage("no_progress")
        return
    end

    if blackboard:get("player.is_casting", false) or blackboard:get("player.is_channeling", false) then
        self._state_machine:transition("CASTING", "player_casting")
        self:_combat_diag(blackboard, "casting")
        return
    end

    -- Clean up after cast cancellation (move_forward_start broke the cast)
    if blackboard:get("combat._cancel_cast_pending") then
        if core and core.input and type(core.input.move_forward_stop) == "function" then
            pcall(core.input.move_forward_stop)
        end
        blackboard:set("combat._cancel_cast_pending", false)
    end

    -- Only chase when not kiting (kite controller owns movement during kite)
    local kite_state = blackboard:get("combat.kite_state", "NONE")
    if kite_state == "NONE" then
        self._chase_controller:update(target)
    else
        -- Stop any active chase nav so it doesn't fight the kite controller
        self._chase_controller:stop("kiting")
    end

    -- Don't try to cast if target is well beyond combat range (closing gap).
    -- Always tick off-GCD during kite so the kite controller can transition states.
    local target_dist = tonumber(blackboard:get("combat.target_distance", 0)) or 0
    local combat_range = tonumber(blackboard:get("module.combat.combat_range")) or 4.5
    if target_dist > combat_range + 10 and kite_state == "NONE" then
        self:_combat_diag(blackboard, string.format("out_of_range dist=%.0f range=%.0f", target_dist, combat_range))
        return
    end

    self._profile:tick_off_gcd(blackboard)

    -- COOLDOWN timeout: if the GCD tree found no legal actions and we've been
    -- waiting long enough, disengage and return to IDLE. This prevents the
    -- combat phase from wedging indefinitely when there's nothing to do
    -- (e.g. all spells on cooldown, target out of range, no valid target).
    -- The timeout is reset whenever we transition out of COOLDOWN (e.g. a
    -- spell confirms via the event handler).
    local COOLDOWN_TIMEOUT_MS = 2500
    if self._state_machine:get_state() == "COOLDOWN" then
        if self._cooldown_enter_ms == 0 then
            self._cooldown_enter_ms = now_ms
        elseif now_ms - self._cooldown_enter_ms >= COOLDOWN_TIMEOUT_MS then
            self._cooldown_enter_ms = 0
            self:disengage("no_legal_action_timeout")
            return
        end
    else
        self._cooldown_enter_ms = 0
    end

    if self._cooldowns:is_gcd_ready(now_ms) then
        self._state_machine:transition("ENGAGING", "gcd_ready")
        
        -- Ensure seal is active before combat actions (seal must be up for Judgement)
        -- Run maintenance BEFORE GCD tick since GCD priorities may need seal present
        local maintenance_status = self._profile:tick_maintenance(blackboard)
        if maintenance_status == "SUCCESS" or maintenance_status == "RUNNING" then
            return
        end
        
        local status = self._profile:tick_gcd(blackboard)
        if status == "FAILURE" then
            self._state_machine:transition("COOLDOWN", "no_legal_action")
            self._cooldown_enter_ms = now_ms
            self:_combat_diag(blackboard, "gcd_tree_failure")
        end
    else
        self:_combat_diag(blackboard, string.format("waiting_gcd until=%d now=%d", blackboard:get("combat.gcd_until_ms", 0), now_ms))
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
