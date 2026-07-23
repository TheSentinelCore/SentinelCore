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
            self:disengage("low_health")
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

function SentinelCombat:_ensure_target()
    if self:_target_is_valid(self._current_target) then
        self._blackboard:set("combat.target", self._current_target)
        return self._current_target
    end
    -- A forced (quest) target stays current while it lives, even though the selector rejects it
    -- for being neutral. Without this it would be dropped on the very next tick after engage.
    if self._forced_target and self._forced_target == self._current_target then
        local ok, dead = pcall(self._forced_target.is_dead, self._forced_target)
        if ok and dead ~= true then
            self._blackboard:set("combat.target", self._current_target)
            return self._current_target
        end
        self._forced_target = nil
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

    if effective_hp <= health_threshold then
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
    local now_ms = self._blackboard:get("system.now_ms", 0)
    if self._outnumbered_backoff_until_ms and now_ms < self._outnumbered_backoff_until_ms then
        return
    end
    opts = opts or {}
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
    self._forced_target = forced and target or nil

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
    -- Clean up cast cancellation movement so the player doesn't walk forward forever
    if self._blackboard:get("combat._cancel_cast_pending") then
        if core and core.input and type(core.input.move_forward_stop) == "function" then
            pcall(core.input.move_forward_stop)
        end
        self._blackboard:set("combat._cancel_cast_pending", false)
    end
    self._current_target = nil
    self._source = nil
    self._blackboard:set("combat.target", nil)
    self._blackboard:set("combat.source", nil)
    self._blackboard:set("rotation.after_judgement_reseal", false)
    self._blackboard:set("rotation.twist.pending_reseal", false)
    if reason == "outnumbered" then
        local now_ms = self._blackboard:get("system.now_ms", 0)
        self._outnumbered_backoff_until_ms = now_ms + OUTNUMBERED_BACKOFF_MS
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

    local target = self:_ensure_target()
    if not target then
        self:disengage("target_lost")
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
