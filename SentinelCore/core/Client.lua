local EventBus = require("events/EventBus")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")
local Defaults = require("core/Defaults")

local Blackboard = require("core/Blackboard")
local StateMachine = require("core/StateMachine")
local Config = require("core/Config")
local Sensors = require("core/Sensors")
local Telemetry = require("core/Telemetry")
local ConsoleLogger = require("core/ConsoleLogger")
local Logger = require("core/Logger")
local ModeState = require("core/ModeState")

local NavigationAdapter = require("services/NavigationAdapter")
local WorldDataAdapter = require("services/WorldDataAdapter")
local ObjectiveService = require("services/ObjectiveService")
local TargetingService = require("services/TargetingService")
local ExplorationService = require("services/ExplorationService")
local RotationEngine = require("services/RotationEngine")
local CombatService = require("services/CombatService")
local LootService = require("services/LootService")
local InventoryService = require("services/InventoryService")
local VendorService = require("services/VendorService")
local RecoveryService = require("services/RecoveryService")
local DeathRecoveryService = require("services/DeathRecoveryService")
local MountService = require("services/MountService")
local ProfileCoordinator = require("services/ProfileCoordinator")
local ProfileRecorder = require("services/ProfileRecorder")
local ProfileOverlay = require("ui/ProfileOverlay")

local get_now = require("lib/TimeHelper").get_now
local AutoAttackHelper = require("lib/AutoAttackHelper")

local GrindMode = require("modes/GrindMode")
local QuestMode = require("modes/QuestMode")
local GatherMode = require("modes/GatherMode")
local BgMode = require("modes/BgMode")

local GrindService = require("services/GrindService")
local UtilityEvaluator = require("ai/UtilityEvaluator")
local SwingTimer = require("ai/SwingTimer")
local HumanTiming = require("ai/HumanTiming")
local SessionBehavior = require("ai/SessionBehavior")
local PackTracker = require("ai/PackTracker")
local TacticalSelector = require("ai/TacticalSelector")
local SingleTargetTactic = require("tactics/SingleTargetTactic")
local RetUtil = require("rotations/paladin/RetributionUtility")

---@class SentinelClient
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _state_machine SentinelStateMachine
---@field private _config SentinelConfig
---@field private _sensors SentinelSensors
---@field private _telemetry SentinelTelemetry
---@field private _logger SentinelConsoleLogger
---@field private _services table
---@field private _modes table<string, table>
---@field private _active_mode table|nil
---@field private _active_mode_id string|nil
---@field private _active_mode_definition table|nil
---@field private _active_tree table|nil
---@field private _utility_evaluator table
---@field private _swing_timer table
---@field private _human_timing table
---@field private _session_behavior table
---@field private _grind_tree table|nil
---@field private _started boolean
---@field private _context_pending boolean
---@field private _context_last_attempt number
---@field private _dependency_pending boolean
---@field private _last_dependency_check number
---@field private _last_runtime_state_write number
local Client = {}
Client.__index = Client

---@param config? table
---@return SentinelClient
function Client:new(config)
    config = config or {}

    local o = setmetatable({}, Client)
    o._event_bus = EventBus:new()
    o._blackboard = Blackboard:new(o._event_bus)
    o._state_machine = StateMachine:new(o._event_bus)
    o._config = Config:new(config.runtime_overrides, config.persistence)
    o._sensors = Sensors:new(o._blackboard, o._event_bus, Events)
    o._telemetry = Telemetry:new(o._event_bus, o._blackboard, o._config:get_runtime_value("telemetry", "flush_interval", 1.0))
    o._logger = ConsoleLogger:new(o._event_bus, o._blackboard, Logger)

    -- Enrich non-blackboard domain events with common context fields so
    -- payload contracts stay consistent across services.
    local raw_emit = o._event_bus.emit
    o._event_bus.emit = function(bus, event, data)
        local payload = data
        local event_name = tostring(event or "")
        if event_name:sub(1, 3) ~= "bb." then
            if payload == nil then
                payload = {}
            end
            if type(payload) == "table" then
                if payload.timestamp == nil then
                    payload.timestamp = get_now()
                end
                if payload.session_id == nil then
                    payload.session_id = o._telemetry:get_session_id()
                end
                if payload.state == nil then
                    payload.state = o._state_machine:get_full_state()
                end
                local canonical = o._blackboard:get("context.canonical")
                if payload.map_id == nil then
                    payload.map_id = canonical and canonical.map_id or nil
                end
                if payload.zone_id == nil then
                    payload.zone_id = canonical and canonical.zone_id or nil
                end
                if payload.area_id == nil then
                    payload.area_id = canonical and canonical.area_id or nil
                end
            end
        end
        return raw_emit(bus, event, payload)
    end

    o._started = false
    o._context_pending = false
    o._context_last_attempt = 0
    o._dependency_pending = false
    o._last_dependency_check = 0
    o._last_runtime_state_write = 0

    o._blackboard:set("core.state_machine", o._state_machine)
    o._blackboard:set("core.session_id", o._telemetry:get_session_id())

    local runtime_cfg = o._config:get_runtime()
    local idle_threshold = tonumber(runtime_cfg and runtime_cfg.telemetry and runtime_cfg.telemetry.idle_full_resource_threshold)
        or 0.98
    o._blackboard:set("telemetry.idle_full_resource_threshold", idle_threshold)

    -- Initialize Logger from config
    local logging_cfg = runtime_cfg.logging or {}
    Logger.set_global_level(logging_cfg.global_level or "INFO")
    Logger.set_max_history(logging_cfg.max_history or 200)
    o._client_log = Logger:new("Client")

    o._session_cap_warned = false
    o._session_cap_fired = false
    o._started_at = nil

    o._event_bus:on(Events.ZONE_CHANGED, function(data)
        o._client_log:info("Zone changed: " .. tostring(data and data.from) .. " -> " .. tostring(data and data.to) .. " " .. tostring(data and data.name or ""))
        local wd = o._services and o._services.world_data
        if wd and type(wd.refresh) == "function" then
            pcall(function() wd:refresh() end)
        end
        if data and data.to then
            o:_apply_zone_overrides(data.to)
        end
    end, { owner = o })

    local navigation = config.navigation_adapter or NavigationAdapter:new(o._event_bus, o._blackboard, Logger:new("Nav"))
    local world_data = config.world_data_adapter or WorldDataAdapter:new(o._event_bus, o._blackboard, runtime_cfg.world_data, Logger:new("WorldData"))
    local objective = config.objective_service or ObjectiveService:new(o._event_bus, o._blackboard, runtime_cfg.objective, Logger:new("Objective"))
    local targeting = config.targeting_service or TargetingService:new(o._event_bus, o._blackboard, runtime_cfg.targeting, navigation, Logger:new("Targeting"))
    local exploration = config.exploration_service or ExplorationService:new(
        o._event_bus,
        o._blackboard,
        runtime_cfg.exploration,
        navigation,
        targeting,
        Logger:new("Exploration")
    )
    local rotation = config.rotation_engine or RotationEngine:new(o._event_bus, o._blackboard, runtime_cfg.combat, Logger:new("Rotation"))
    local combat = config.combat_service or CombatService:new(o._event_bus, o._blackboard, navigation, targeting, rotation, runtime_cfg.combat, Logger:new("Combat"))
    local loot = config.loot_service or LootService:new(o._event_bus, o._blackboard, runtime_cfg.loot, navigation, Logger:new("Loot"))

    -- Policy/cache are loaded during start; seed with defaults for construction.
    local inventory = config.inventory_service or InventoryService:new(o._event_bus, o._blackboard, runtime_cfg.inventory, o._config:get_policy(), Logger:new("Inventory"))
    local vendor = config.vendor_service or VendorService:new(o._event_bus, o._blackboard, navigation, world_data, inventory, runtime_cfg.vendor, o._config:get_vendor_cache(), Logger:new("Vendor"))
    local recovery = config.recovery_service or RecoveryService:new(o._event_bus, o._blackboard, runtime_cfg.recovery, Logger:new("Recovery"))
    local death_recovery = config.death_recovery_service or DeathRecoveryService:new(
        o._event_bus, o._blackboard, runtime_cfg.death, navigation, Logger:new("DeathRecovery")
    )
    local mount = config.mount_service or MountService:new(o._event_bus, o._blackboard, runtime_cfg.mount, Logger:new("Mount"))
    local profile_coordinator = config.profile_coordinator or ProfileCoordinator:new(
        o._event_bus, o._blackboard, runtime_cfg.profiles or {},
        navigation, targeting, Logger:new("ProfileCoord")
    )

    -- Record hotspot keybind (Insert key = 0x2D = 45)
    local record_hotspot_keybind = core.menu.key_checkbox(45, false, false, true, 0, "sc_record_hotspot")
    local profile_recorder = config.profile_recorder or ProfileRecorder:new(
        o._event_bus, o._blackboard, Logger:new("ProfileRec"), record_hotspot_keybind
    )

    local profile_overlay = ProfileOverlay:new(o._blackboard)

    o._services = {
        blackboard = o._blackboard,
        navigation = navigation,
        world_data = world_data,
        objective = objective,
        targeting = targeting,
        exploration = exploration,
        rotation = rotation,
        combat = combat,
        loot = loot,
        inventory = inventory,
        vendor = vendor,
        recovery = recovery,
        death_recovery = death_recovery,
        mount = mount,
        profile_coordinator = profile_coordinator,
        profile_recorder = profile_recorder,
        profile_overlay = profile_overlay,
    }

    o._service_update_order = {
        "objective",
        "targeting",
        "profile_coordinator",
        "profile_recorder",
        "exploration",
        "combat",
        "loot",
        "inventory",
        "vendor",
        "mount",
    }

    -- AI components for BT-driven grind mode
    o._utility_evaluator = UtilityEvaluator:new()
    o._swing_timer = SwingTimer:new()
    o._human_timing = HumanTiming:new()
    o._session_behavior = SessionBehavior:new()
    RetUtil.register_actions(o._utility_evaluator)

    -- Tactical AI
    local pack_tracker = PackTracker:new()
    local tactical_selector = TacticalSelector:new(nil)  -- nil advisor for now (Phase 4)
    tactical_selector:register(SingleTargetTactic:new())
    tactical_selector:refresh_available({})

    o._pack_tracker = pack_tracker
    o._tactical_selector = tactical_selector

    o._grind_tree = nil

    o._modes = {
        grind = GrindMode:new(),
        quest = QuestMode:new(),
        gather = GatherMode:new(),
        bg = BgMode:new(),
    }
    o._active_mode = nil
    o._active_mode_id = nil
    o._active_mode_definition = nil
    o._active_tree = nil

    return o
end

---@private
---@return boolean
function Client:_is_tbc_runtime()
    if not core or not core.get_game_version then
        return false
    end
    local version = tostring(core.get_game_version() or "")
    version = version:lower()
    return version:find("tbc", 1, true) ~= nil
end

---@private
---@param mode_id string
---@return table|nil
function Client:_get_mode(mode_id)
    return self._modes[mode_id]
end

---@private
---@param mode table
---@param mode_id string
---@return table
function Client:_resolve_mode_definition(mode, mode_id)
    local raw_definition = nil
    if mode and type(mode.get_definition) == "function" then
        local ok, value = pcall(mode.get_definition, mode)
        if ok and type(value) == "table" then
            raw_definition = value
        end
    end
    if type(raw_definition) ~= "table" then
        raw_definition = { id = mode_id }
    end
    if raw_definition.id == nil and raw_definition.mode_id == nil then
        raw_definition.id = mode_id
    end

    local definition = ModeState.normalize_definition(raw_definition)
    self._state_machine:register_mode(definition.id, definition.phases, definition.default_phase)
    return definition
end

---@private
---@param error_code string
---@param detail? table
function Client:_report_critical(error_code, detail)
    self._client_log:error("critical: %s", tostring(error_code))
    self._blackboard:set("core.fail_reason", error_code)
    self._blackboard:set("core.fail_detail", detail)

    local runtime_state = self._config:get_runtime_state()
    runtime_state.last_error_code = error_code
    runtime_state.last_state = self._state_machine:get_full_state()
    runtime_state.last_session_id = self._telemetry:get_session_id()
    self._config:set_runtime_state(runtime_state)

    self._services.recovery:report_critical(error_code, detail)
end

---@private
function Client:_refresh_policy_cache_bindings()
    local policy = self._config:get_policy()
    local vendor_cache = self._config:get_vendor_cache()

    self._services.inventory:set_policy(policy)
    self._services.vendor:set_cache(vendor_cache)
end

---@private
function Client:_apply_runtime_bindings()
    local runtime_cfg = self._config:get_runtime()

    if self._services.world_data then
        self._services.world_data._cfg = Defaults.copy(runtime_cfg.world_data or {})
    end
    if self._services.targeting then
        self._services.targeting._cfg = Defaults.copy(runtime_cfg.targeting or {})
    end
    if self._services.objective then
        self._services.objective._cfg = Defaults.copy(runtime_cfg.objective or {})
    end
    if self._services.exploration then
        self._services.exploration._cfg = Defaults.copy(runtime_cfg.exploration or {})
    end
    if self._services.rotation then
        self._services.rotation._cfg = Defaults.copy(runtime_cfg.combat or {})
    end
    if self._services.combat then
        self._services.combat._cfg = Defaults.copy(runtime_cfg.combat or {})
    end
    if self._services.loot then
        self._services.loot._cfg = Defaults.copy(runtime_cfg.loot or {})
    end
    if self._services.inventory then
        self._services.inventory._cfg = Defaults.copy(runtime_cfg.inventory or {})
    end
    if self._services.vendor then
        self._services.vendor._cfg = Defaults.copy(runtime_cfg.vendor or {})
    end
    if self._services.recovery then
        self._services.recovery._cfg = Defaults.copy(runtime_cfg.recovery or {})
    end
    if self._services.death_recovery then
        self._services.death_recovery._cfg = Defaults.copy(runtime_cfg.death or {})
    end

    local idle_threshold = tonumber(runtime_cfg and runtime_cfg.telemetry and runtime_cfg.telemetry.idle_full_resource_threshold)
        or 0.98
    self._blackboard:set("telemetry.idle_full_resource_threshold", idle_threshold)

    if self._telemetry then
        self._telemetry._flush_interval = tonumber(runtime_cfg.telemetry and runtime_cfg.telemetry.flush_interval) or 1.0
    end

    self._blackboard:set("rotation.policy", Defaults.copy(runtime_cfg.rotation or {}))

    -- Re-sync Logger global level from config
    local logging_cfg = runtime_cfg.logging or {}
    Logger.set_global_level(logging_cfg.global_level or "INFO")
    Logger.set_max_history(logging_cfg.max_history or 200)
end

---@private
function Client:_write_runtime_state(force)
    local now = get_now()
    if not force and now - self._last_runtime_state_write < 1.0 then
        return
    end
    self._last_runtime_state_write = now

    local runtime_state = self._config:get_runtime_state()
    runtime_state.last_state = self._state_machine:get_full_state()
    runtime_state.last_session_id = self._telemetry:get_session_id()
    runtime_state.auto_restart_attempts_used = self._services.recovery:get_attempts_used()

    local canonical = self._blackboard:get("context.canonical")
    if canonical then
        local pos = self._blackboard:get("player.position") or {}
        runtime_state.last_known_context = {
            canonical_map_id = canonical.map_id,
            zone_id = canonical.zone_id,
            area_id = canonical.area_id,
            x = pos.x or 0,
            y = pos.y or 0,
            z = pos.z or 0,
        }
    end

    local anchor = self._blackboard:get("core.mode_anchor") or self._blackboard:get("grind.anchor")
    if anchor then
        runtime_state.last_grind_anchor = {
            x = anchor.x or 0,
            y = anchor.y or 0,
            z = anchor.z or 0,
        }
    end

    self._config:set_runtime_state(runtime_state)
    self._config:save_runtime_state()

    self._config:set_vendor_cache(self._services.vendor:get_cache())
    self._config:save_vendor_cache()
end

---@private
function Client:_resolve_context_if_due(force)
    if self._context_pending then
        return
    end

    local now = get_now()
    local interval = self._config:get_runtime_value("runtime", "context_resolve_interval", 10.0)
    if not force and (now - self._context_last_attempt) < interval then
        return
    end

    local runtime_ctx = {
        ui_map_id = self._blackboard:get("context.ui_map_id"),
        instance_type = self._blackboard:get("context.instance_type"),
        position = self._blackboard:get("context.position"),
    }

    self._context_pending = true
    self._context_last_attempt = now
    self._services.world_data:resolve_context(runtime_ctx, function(ok, canonical_ctx, error_code)
        self._context_pending = false
        if not ok then
            self._blackboard:clear("context.canonical")
            self:_report_critical(error_code or ErrorCodes.CTX_UNRESOLVED, {
                stage = "context_resolve",
            })
            return
        end

        self._blackboard:set("context.canonical", canonical_ctx)
    end)
end

---@private
---@param force boolean
function Client:_dependency_health_check(force)
    local now = get_now()
    local interval = self._config:get_runtime_value("runtime", "dependency_health_interval", 5.0)

    if not force and (now - self._last_dependency_check) < interval then
        return
    end

    self._last_dependency_check = now

    self._services.navigation:update()
    self._services.world_data:update(now)

    local nav_ok, nav_err = self._services.navigation:is_available()
    local world_ok = self._blackboard:get("deps.world_data.healthy", true)
    local dataset_ok = self._blackboard:get("deps.world_data.dataset_ok", true)

    self._event_bus:emit(Events.DEPENDENCY_HEALTH, {
        timestamp = now,
        nav_ok = nav_ok,
        world_ok = world_ok,
        dataset_ok = dataset_ok,
    })

    if not nav_ok then
        self:_report_critical(nav_err or ErrorCodes.DEP_NAVCLIENT_MISSING, { stage = "dependency" })
        return
    end

    if world_ok == false then
        self:_report_critical(ErrorCodes.DEP_WORLDDATA_UNAVAILABLE, { stage = "dependency" })
        return
    end

    if dataset_ok == false then
        local dataset_error = self._blackboard:get("deps.world_data.dataset_error")
        self:_report_critical(dataset_error or ErrorCodes.DEP_WORLDDATA_DATASET_MISMATCH, { stage = "dependency" })
        return
    end
end

---@private
---@param action table Action from UtilityEvaluator (id, action_type, spell_id)
function Client:_execute_action(action)
    if not action then return end

    if action.action_type == "cast_spell_target" then
        local target = self._blackboard:get("combat.target")
        if core.input and core.input.cast_target_spell and target then
            pcall(function() core.input.cast_target_spell(action.spell_id, target) end)
        end
    elseif action.action_type == "cast_spell_self" then
        local player = self._blackboard:get("player.object")
        if core.input and core.input.cast_target_spell and player then
            pcall(function() core.input.cast_target_spell(action.spell_id, player) end)
        end
    elseif action.action_type == "auto_attack" then
        -- Idempotent auto-attack: use SDK auto_attack_helper, fall back to
        -- cast_target_spell(6603) only when not already auto-attacking.
        local target = self._blackboard:get("combat.target")
        if core.input and target then
            pcall(function()
                if core.input.set_target then core.input.set_target(target) end
            end)
            local sent = false
            -- Primary: SDK auto_attack_helper (truly idempotent)
            local aa = AutoAttackHelper.get()
            if aa and aa.start_attack then
                local ok = pcall(function()
                    aa:start_attack(target, aa.ATTACK_TYPE and aa.ATTACK_TYPE.MELEE or 6603)
                end)
                if ok then sent = true end
            end
            -- Fallback: only send 6603 toggle when NOT already auto-attacking
            if not sent and core.input.cast_target_spell then
                local p = self._blackboard:get("player.object")
                local already_attacking = false
                if p then
                    local ok, val = pcall(function() return p:is_auto_attacking() end)
                    if ok and val == true then already_attacking = true end
                end
                if not already_attacking then
                    pcall(core.input.cast_target_spell, 6603, target)
                end
            end
        end
    end
end

---@private
function Client:_service_updates()
    for i = 1, #self._service_update_order do
        local key = self._service_update_order[i]
        local service = self._services[key]
        if service and service.update then
            local ok, err = service:update()
            if ok == false and err then
                self:_report_critical(err, { stage = "service_update", service = key })
                return
            end
        end
    end
end

---@private
---@param command table
function Client:_apply_recovery_command(command)
    if not command then
        return
    end

    if command.action == "pause" then
        self:pause(command.error_code)
        return
    end

    if command.action == "restart" then
        local ok = self:resume()
        self._services.recovery:complete_restart_attempt(ok)
        return
    end

    if command.action == "fail" then
        self._services.navigation:stop()
        self._state_machine:transition("failed", {
            failure_code = command.error_code,
            failure_detail = { stage = command.stage },
        })
        return
    end
end

---@private
---@param mode table
---@param mode_definition table
---@return boolean
---@return string|nil
function Client:_bind_mode_tree(mode, mode_definition)
    mode_definition = mode_definition or ModeState.normalize_definition({
        id = mode and mode.id and mode:id() or ModeState.default_mode_id(),
    })
    self._active_mode = mode
    self._active_mode_id = mode_definition.id
    self._active_mode_definition = Defaults.copy(mode_definition)

    self._state_machine:set_active_mode(mode_definition.id)
    self._blackboard:set("core.mode", mode_definition.id)
    self._blackboard:set("core.mode_definition", Defaults.copy(mode_definition))

    local tree = mode:build_tree(self._services, {
        pause = function(reason)
            self:pause(reason)
        end,
        restart = function()
            return self:resume()
        end,
        fail = function(error_code)
            self._services.navigation:stop()
            self._state_machine:transition("failed", { failure_code = error_code })
        end,
    })
    if tree == nil then
        self._active_tree = nil
        return false, ErrorCodes.MODE_NOT_AVAILABLE
    end

    self._active_tree = tree
    return true, nil
end

---@private
---@param mode table
---@param mode_definition table
function Client:_configure_mode_objectives(mode, mode_definition)
    if not self._services.objective or not self._services.objective.set_mode then
        return
    end

    local objective_provider = nil
    if mode and type(mode.get_objective_provider) == "function" then
        local ok_provider, provider = pcall(mode.get_objective_provider, mode)
        if ok_provider then
            objective_provider = provider
        end
    end

    self._services.objective:set_mode(mode_definition.id, objective_provider, self._services)
end

---@private
---@param zone_id number|string
function Client:_apply_zone_overrides(zone_id)
    if not self._config then return end
    local ok, override = pcall(function()
        return self._config:get_zone_override(zone_id)
    end)
    if ok and type(override) == "table" then
        self._client_log:info("Applying zone override for zone " .. tostring(zone_id))
        local runtime = self._config:get_runtime()
        if runtime then
            for k, v in pairs(override) do
                runtime[k] = v
            end
            self:_apply_runtime_bindings()
        end
    end
end

---@param mode_id string
---@param opts? table
---@return boolean
---@return string|nil
function Client:start(mode_id, opts)
    opts = opts or {}
    mode_id = mode_id or "grind"
    self._client_log:info("starting mode=%s", mode_id)

    if self._state_machine:get_state() == "running" then
        return true, nil
    end

    if not self:_is_tbc_runtime() then
        self._state_machine:transition("failed", {
            failure_code = ErrorCodes.GAME_VERSION_UNSUPPORTED,
        })
        return false, ErrorCodes.GAME_VERSION_UNSUPPORTED
    end

    local valid_cfg, cfg_err = self._config:validate_runtime()
    if not valid_cfg then
        self._state_machine:transition("failed", {
            failure_code = cfg_err or ErrorCodes.CONFIG_INVALID,
        })
        return false, cfg_err or ErrorCodes.CONFIG_INVALID
    end

    local ok_load, load_err = self._config:load_persistence()
    if not ok_load then
        self._state_machine:transition("failed", {
            failure_code = load_err or ErrorCodes.PERSISTENCE_CORRUPTED,
        })
        return false, load_err or ErrorCodes.PERSISTENCE_CORRUPTED
    end
    self:_apply_runtime_bindings()
    self:_refresh_policy_cache_bindings()

    local mode = self:_get_mode(mode_id)
    if not mode then
        self._state_machine:transition("failed", {
            failure_code = ErrorCodes.MODE_NOT_AVAILABLE,
        })
        return false, ErrorCodes.MODE_NOT_AVAILABLE
    end
    local mode_definition = self:_resolve_mode_definition(mode, mode_id)
    if mode_definition.functional == false then
        self._state_machine:transition("failed", {
            failure_code = ErrorCodes.MODE_NOT_AVAILABLE,
        })
        return false, ErrorCodes.MODE_NOT_AVAILABLE
    end

    if self._state_machine:get_state() == "failed" then
        self._state_machine:reset()
    end

    self._state_machine:set_active_mode(mode_definition.id)
    local transitioned, transition_err = self._state_machine:transition("running", {
        mode_id = mode_definition.id,
        substate = ModeState.compose_substate(mode_definition.id, mode_definition.default_phase),
    })
    if not transitioned then
        return false, ErrorCodes.STATE_TRANSITION_INVALID .. ":" .. tostring(transition_err)
    end

    local bind_ok, bind_err = self:_bind_mode_tree(mode, mode_definition)
    if not bind_ok then
        self._state_machine:transition("failed", {
            failure_code = bind_err or ErrorCodes.MODE_NOT_AVAILABLE,
        })
        return false, bind_err or ErrorCodes.MODE_NOT_AVAILABLE
    end
    self._active_mode:on_enter({})
    self:_configure_mode_objectives(mode, mode_definition)

    self._started = true
    self._started_at = get_now()
    self._session_cap_warned = false
    self._session_cap_fired = false

    -- Enable persistent file logging for this session.
    -- Each bot start gets its own log file named after the session ID so logs
    -- from different runs never overwrite each other.
    local session_id = self._telemetry:get_session_id()
    local log_path = "SentinelCore/logs/session_" .. tostring(session_id) .. ".log"
    pcall(function()
        if core and core.create_data_folder then
            core.create_data_folder("SentinelCore")
            core.create_data_folder("SentinelCore/logs")
        end
        Logger.set_log_file(log_path)
    end)

    -- Start SessionBehavior timer so fatigue/idle-pause cadence is relative to this session start.
    if self._session_behavior and type(self._session_behavior.start) == "function" then
        pcall(function() self._session_behavior:start(get_now()) end)
    end

    -- Build BT grind tree for grind mode
    if mode_definition.id == "grind" then
        self._grind_tree = GrindService.build({
            bb = self._blackboard,
            evaluator = self._utility_evaluator,
            swing_timer = self._swing_timer,
            human_timing = self._human_timing,
            session_behavior = self._session_behavior,
            spell_executor = function(action) self:_execute_action(action) end,
            navigation = self._services.navigation,
            targeting = self._services.targeting,
            rotation_engine = self._services.rotation,
            vendor_service = self._services.vendor,
            exploration_service = self._services.exploration,
            loot_service = self._services.loot,
            death_recovery_service = self._services.death_recovery,
            mount_service = self._services.mount,
            tactical_selector = self._tactical_selector,
            pack_tracker = self._pack_tracker,
        })
        -- Clear stale BT state from previous session
        self._blackboard:clear("loot.pending_target")
        self._blackboard:clear("combat.target")
    end

    self._event_bus:emit(Events.STARTED, {
        timestamp = get_now(),
        mode = mode_definition.id,
        session_id = self._telemetry:get_session_id(),
    })

    self:_dependency_health_check(true)
    self:_resolve_context_if_due(true)
    self:_write_runtime_state(true)

    return true, nil
end

---@param reason? string
---@return boolean
function Client:stop(reason)
    self._client_log:info("stopping reason=%s", tostring(reason or "-"))
    local state = self._state_machine:get_state()
    if state == "idle" then
        return true
    end

    if self._active_mode then
        self._active_mode:on_exit({}, reason)
    end

    self._services.navigation:stop()
    if self._services.objective and self._services.objective.reset then
        self._services.objective:reset()
    end
    self._services.combat:reset()
    self._services.loot:reset()
    self._services.vendor:reset()
    self._services.recovery:reset()
    if self._services.rotation and self._services.rotation.reset then
        self._services.rotation:reset()
    end
    if self._services.exploration and self._services.exploration.reset then
        self._services.exploration:reset()
    end
    self._services.targeting:clear_target("stop")
    if self._services.death_recovery and self._services.death_recovery.reset then
        self._services.death_recovery:reset()
    end
    if self._services.mount and self._services.mount.reset then
        self._services.mount:reset()
    end
    self._blackboard:clear("loot.pending_target")

    self._context_pending = false
    self._grind_tree = nil
    self._active_tree = nil
    self._active_mode = nil
    self._active_mode_id = nil
    self._active_mode_definition = nil
    self._blackboard:clear("core.mode")
    self._blackboard:clear("core.mode_definition")
    self._blackboard:clear("core.mode_anchor")
    self._blackboard:clear("core.fail_reason")
    self._blackboard:clear("core.fail_detail")

    self._state_machine:reset()

    self._event_bus:emit(Events.STOPPED, {
        timestamp = get_now(),
        reason = reason,
    })

    -- Export and persist session telemetry archive on every clean stop.
    local tel_session_id = self._telemetry and self._telemetry._session_id
    if tel_session_id then
        local ok_json, json_data = pcall(function()
            return self._telemetry:export_session_json()
        end)
        if ok_json and type(json_data) == "string" and json_data ~= "" then
            pcall(function()
                self._config:get_persistence():save_session_telemetry(tel_session_id, json_data)
            end)
        end
    end

    -- Disable file logging now that the session is done.
    pcall(function() Logger.set_log_file(nil) end)

    self:_write_runtime_state(true)
    return true
end

---@param reason? string
---@return boolean
function Client:pause(reason)
    local state = self._state_machine:get_state()
    if state == "paused" then
        return true
    end

    if state ~= "running" then
        return false
    end

    local ok = self._state_machine:transition("paused")
    if not ok then
        return false
    end

    self._services.navigation:stop()
    self._event_bus:emit(Events.PAUSED, {
        timestamp = get_now(),
        reason = reason,
    })

    self:_write_runtime_state(true)
    return true
end

---@return boolean
function Client:resume()
    local state = self._state_machine:get_state()
    if state == "running" then
        return true
    end

    if state ~= "paused" then
        return false
    end

    local mode_definition = self._active_mode_definition
    if type(mode_definition) ~= "table" then
        mode_definition = self._blackboard:get("core.mode_definition")
    end
    if type(mode_definition) ~= "table" then
        mode_definition = ModeState.normalize_definition({
            id = self._blackboard:get("core.mode") or ModeState.default_mode_id(),
        })
    else
        mode_definition = ModeState.normalize_definition(mode_definition)
    end

    self._state_machine:register_mode(mode_definition.id, mode_definition.phases, mode_definition.default_phase)
    self._state_machine:set_active_mode(mode_definition.id)

    local ok = self._state_machine:transition("running", {
        mode_id = mode_definition.id,
        substate = ModeState.compose_substate(mode_definition.id, mode_definition.default_phase),
    })
    if not ok then
        return false
    end

    self._event_bus:emit(Events.RESUMED, {
        timestamp = get_now(),
    })

    self:_resolve_context_if_due(true)
    self:_write_runtime_state(true)
    return true
end

function Client:update()
    -- 1) Sensors
    self._sensors:update()

    local state = self._state_machine:get_state()
    local now = self._blackboard:get("_time", 0)

    -- F6: Session length hard cap
    if state == "running" then
        local max_session_minutes = (self._config and self._config:get_runtime()
            and self._config:get_runtime().policy
            and self._config:get_runtime().policy.max_session_minutes) or 240
        local session_elapsed_mins = (get_now() - (self._started_at or get_now())) / 60.0

        if session_elapsed_mins >= max_session_minutes then
            if not self._session_cap_fired then
                self._session_cap_fired = true
                self:_report_critical(ErrorCodes.SESSION_EXPIRED, "Max session duration reached (" .. math.floor(session_elapsed_mins) .. " min)")
            end
            return
        elseif session_elapsed_mins >= max_session_minutes * 0.80 and not self._session_cap_warned then
            self._session_cap_warned = true
            self._client_log:warn("Session approaching max duration: " .. string.format("%.0f/%.0f min", session_elapsed_mins, max_session_minutes))
        end
    end

    if state == "running" then
        -- 2) Dependency health checks (nav needed for corpse run).
        self:_dependency_health_check(false)

        if self._grind_tree then
            -- BT-driven grind loop: tree handles death, combat, loot, rest, etc.
            self:_resolve_context_if_due(false)

            -- Essential service updates: maintain BB state for BT decisions.
            -- TargetingService: validates current target, updates combat.enemy_count.
            -- InventoryService: refreshes inventory.free_slots, inventory.needs_vendor.
            -- DeathRecoveryService: manages death state machine, death.corpse_position.
            pcall(function() self._services.targeting:update() end)
            pcall(function() self._services.inventory:update() end)
            pcall(function() self._services.death_recovery:update() end)

            -- Update PackTracker from TargetingService's visible hostiles
            if self._pack_tracker and self._services.targeting then
                local hostiles = self._services.targeting:get_visible_hostiles()
                local player_pos = self._blackboard:get("player.position")
                local player = self._blackboard:get("player.object")
                local player_guid = ""
                if player then
                    local ok, guid = pcall(function() return player:get_guid() end)
                    if ok and guid then player_guid = guid end
                end
                if hostiles and player_pos then
                    self._pack_tracker:update(hostiles, player_pos, player_guid)
                    local pack = self._pack_tracker:get_pack()
                    self._blackboard:set("pack.count", pack.count)
                    self._blackboard:set("pack.centroid", pack.centroid)
                    self._blackboard:set("pack.spread", pack.spread)
                    self._blackboard:set("pack.gathered_count", pack.gathered_count)
                    self._blackboard:set("pack.nearest_dist", pack.nearest_dist)
                end
            end

            self._grind_tree:tick()

            -- Recovery supervisor still runs for stuck detection.
            local recovery_command = self._services.recovery:update(now)
            self:_apply_recovery_command(recovery_command)
        else
            -- Legacy pipeline for non-grind modes.
            -- 3) Death recovery gate.
            local was_dead = self._services.death_recovery:is_active()
            self._services.death_recovery:update()
            local is_dead = self._services.death_recovery:is_active()

            -- Post-resurrection cleanup: clear stale service state.
            if was_dead and not is_dead then
                self._services.combat:reset()
                self._services.loot:reset()
                self._services.targeting:clear_target("resurrected")
            end

            if is_dead then
                local recovery_command = self._services.recovery:update(now)
                self:_apply_recovery_command(recovery_command)
            else
                -- 4) Normal operations.
                self:_resolve_context_if_due(false)
                if self._active_mode and self._active_tree and self._blackboard:has("context.canonical") then
                    local can_enter = self._active_mode:can_enter({
                        dependencies_ok = true,
                        canonical_context = self._blackboard:get("context.canonical"),
                        mode_id = self._active_mode_id,
                        mode_definition = self._active_mode_definition,
                    })
                    if not can_enter then
                        self:_report_critical(ErrorCodes.MODE_CAN_ENTER_FAILED, { stage = "mode_tick" })
                    else
                        self._active_mode:tick({})
                    end
                end

                -- 5) Service updates.
                self:_service_updates()

                -- 6) Recovery supervisor.
                local recovery_command = self._services.recovery:update(now)
                self:_apply_recovery_command(recovery_command)
            end
        end
    elseif state == "paused" then
        local recovery_command = self._services.recovery:update(now)
        self:_apply_recovery_command(recovery_command)
    end

    -- 7) Telemetry + snapshot.
    self._telemetry:update(now)
    local snapshot = self:get_snapshot()
    self._event_bus:emit(Events.SNAPSHOT_UPDATED, snapshot)

    self:_write_runtime_state(false)
end

---@return string
function Client:get_state()
    return self._state_machine:get_state()
end

---@return string
function Client:get_full_state()
    return self._state_machine:get_full_state()
end

---@return table
function Client:get_snapshot()
    local canonical = self._blackboard:get("context.canonical") or {}
    local telemetry = self._telemetry:get_snapshot()
    local objective_snapshot = {}
    if self._services.objective and self._services.objective.get_snapshot then
        objective_snapshot = self._services.objective:get_snapshot()
    end

    -- Compute player resource percentages from blackboard / player object
    local bb = self._blackboard
    local health_pct = (bb:get("player.health") or 0) / math.max(1, bb:get("player.max_health") or 1)
    local xp_pct = (bb:get("player.xp") or 0) / math.max(1, bb:get("player.max_xp") or 1)
    local durability_pct = bb:get("player.durability_pct") or 1.0
    local mana_pct = 0
    local player_obj = bb:get("player.object")
    if player_obj and player_obj.get_power then
        local ok_m, m_val = pcall(function()
            local p = player_obj:get_power(0) or 0
            local mp = player_obj:get_max_power(0) or 1
            return p / math.max(1, mp)
        end)
        if ok_m and type(m_val) == "number" then mana_pct = m_val end
    end

    return {
        timestamp = self._blackboard:get("_time", 0),
        session_id = telemetry.session_id,
        state = self._state_machine:get_state(),
        substate = self._state_machine:get_substate(),
        full_state = self._state_machine:get_full_state(),
        mode = self._active_mode_id or self._blackboard:get("core.mode"),
        fail_reason = self._blackboard:get("core.fail_reason"),
        context = {
            ui_map_id = self._blackboard:get("context.ui_map_id"),
            map_id = canonical.map_id,
            zone_id = canonical.zone_id,
            area_id = canonical.area_id,
            position = self._blackboard:get("player.position"),
        },
        dependencies = {
            nav_available = self._blackboard:get("deps.nav.available", false),
            nav_server_available = self._blackboard:get("deps.nav.server_available", false),
            world_data_healthy = self._blackboard:get("deps.world_data.healthy", false),
            world_dataset_ok = self._blackboard:get("deps.world_data.dataset_ok", false),
        },
        inventory = {
            free_slots = self._services.inventory and self._services.inventory:get_free_slots() or 0,
            needs_vendor = self._services.inventory and self._services.inventory:needs_vendor_trip() or false,
        },
        resources = {
            health_pct = health_pct,
            mana_pct = mana_pct,
            xp_pct = xp_pct,
            durability_pct = durability_pct,
        },
        death = {
            active = self._blackboard:get("death.active", false),
            state = self._blackboard:get("death.state", "idle"),
            distance_to_corpse = self._blackboard:get("death.distance_to_corpse"),
        },
        objective = objective_snapshot,
        telemetry = telemetry,
    }
end

---@return table
function Client:get_runtime_config()
    return self._config:get_runtime()
end

---@return table
function Client:get_policy_config()
    return self._config:get_policy()
end

---@param section string
---@param key string
---@param value any
---@param persist? boolean
---@return boolean
---@return string|nil
function Client:set_runtime_setting(section, key, value, persist)
    local set_ok, set_err = self._config:set_runtime_value(section, key, value)
    if not set_ok then
        return false, set_err
    end
    self:_apply_runtime_bindings()

    if persist == true then
        local ok_profile, profile_err = self._config:save_current_profile()
        if not ok_profile then
            return false, profile_err
        end
        local ok_save, save_err = self._config:save_profiles()
        if not ok_save then
            return false, save_err
        end
    end
    return true, nil
end

---@param key string
---@param value any
---@param persist? boolean
---@return boolean
---@return string|nil
function Client:set_policy_setting(key, value, persist)
    local policy = self._config:get_policy()
    policy[key] = value
    self._config:set_policy(policy)
    self:_apply_runtime_bindings()
    self:_refresh_policy_cache_bindings()

    -- Blackboard override survives profile reloads during start().
    if key == "vendor_enabled" and self._services.inventory then
        self._services.inventory:set_vendor_enabled(value)
    end

    if persist == true then
        local ok_policy, policy_err = self._config:save_policy()
        if not ok_policy then
            return false, policy_err
        end

        local ok_profile, profile_err = self._config:save_current_profile()
        if not ok_profile then
            return false, profile_err
        end
        local ok_save, save_err = self._config:save_profiles()
        if not ok_save then
            return false, save_err
        end
    end

    return true, nil
end

---@return table[]
function Client:list_profiles()
    return self._config:list_profiles()
end

---@return string
function Client:get_active_profile_id()
    return self._config:get_active_profile_id()
end

---@param profile table  parsed profile data
---@return boolean ok, string|nil error
function Client:load_grinding_profile(profile)
    return self._services.profile_coordinator:load_profile(profile)
end

function Client:unload_grinding_profile()
    self._services.profile_coordinator:unload_profile()
end

---@return string  FSM state: "idle"|"at_hotspot"|"traveling"|"vendor_trip"
function Client:get_grinding_profile_state()
    return self._services.profile_coordinator:get_state()
end

---@param existing_profile? table  If provided, edit this profile instead of creating new
---@return boolean ok
function Client:start_recording(existing_profile)
    return self._services.profile_recorder:start_recording(existing_profile)
end

---@return table|nil profile, string|nil error
function Client:stop_recording()
    return self._services.profile_recorder:finish_recording()
end

function Client:cancel_recording()
    return self._services.profile_recorder:cancel_recording()
end

---@return string  "idle"|"recording"
function Client:get_recorder_state()
    return self._services.profile_recorder:get_state()
end

---@return table[]
function Client:list_modes()
    local mode_ids = {}
    for mode_id, _ in pairs(self._modes) do
        mode_ids[#mode_ids + 1] = mode_id
    end
    table.sort(mode_ids)

    local out = {}
    for i = 1, #mode_ids do
        local mode_id = mode_ids[i]
        local mode = self._modes[mode_id]
        local definition = self:_resolve_mode_definition(mode, mode_id)
        out[#out + 1] = {
            id = definition.id,
            functional = definition.functional == true,
            default_phase = definition.default_phase,
            phases = Defaults.copy(definition.phases),
            capability_flags = Defaults.copy(definition.capability_flags),
            description = definition.description,
        }
    end
    return out
end

---@return string|nil
function Client:get_active_mode_id()
    return self._active_mode_id or self._blackboard:get("core.mode")
end

---@private
---@param mode_id string
---@return string
function Client:_objective_queue_key(mode_id)
    return string.format("objective.%s.queue", tostring(mode_id))
end

---@private
---@param mode_id string
---@return string
function Client:_objective_index_key(mode_id)
    return string.format("objective.%s.queue_index", tostring(mode_id))
end

---@private
---@param mode_id string
---@return string
function Client:_objective_loop_key(mode_id)
    return string.format("objective.%s.loop", tostring(mode_id))
end

---@param mode_id string
---@param waypoints table[]
---@param opts? table
---@return boolean
---@return string|nil
function Client:set_mode_objective_queue(mode_id, waypoints, opts)
    opts = opts or {}
    if type(waypoints) ~= "table" then
        return false, ErrorCodes.INVALID_PARAMS
    end

    local normalized_mode = ModeState.normalize_definition({ id = mode_id }).id
    local queue = {}
    for i = 1, #waypoints do
        local waypoint = waypoints[i]
        if type(waypoint) ~= "table" then
            return false, ErrorCodes.INVALID_PARAMS
        end
        local x = tonumber(waypoint.x)
        local y = tonumber(waypoint.y)
        local z = tonumber(waypoint.z)
        if x == nil or y == nil or z == nil then
            return false, ErrorCodes.INVALID_PARAMS
        end

        queue[#queue + 1] = {
            x = x,
            y = y,
            z = z,
            label = waypoint.label ~= nil and tostring(waypoint.label) or nil,
            arrive_distance = tonumber(waypoint.arrive_distance),
            reissue_secs = tonumber(waypoint.reissue_secs),
            timeout_secs = tonumber(waypoint.timeout_secs),
        }
    end

    self._blackboard:set(self:_objective_queue_key(normalized_mode), queue)
    self._blackboard:set(self:_objective_index_key(normalized_mode), 1)
    if opts.loop ~= nil then
        self._blackboard:set(self:_objective_loop_key(normalized_mode), opts.loop == true)
    end
    return true, nil
end

---@param mode_id string
---@return table[]
---@return table
function Client:get_mode_objective_queue(mode_id)
    local normalized_mode = ModeState.normalize_definition({ id = mode_id }).id
    local queue = self._blackboard:get(self:_objective_queue_key(normalized_mode)) or {}
    local metadata = {
        index = tonumber(self._blackboard:get(self:_objective_index_key(normalized_mode), 1)) or 1,
        loop = self._blackboard:get(self:_objective_loop_key(normalized_mode), false) == true,
    }
    return Defaults.copy(queue), metadata
end

---@param mode_id string
function Client:clear_mode_objective_queue(mode_id)
    local normalized_mode = ModeState.normalize_definition({ id = mode_id }).id
    self._blackboard:set(self:_objective_queue_key(normalized_mode), {})
    self._blackboard:set(self:_objective_index_key(normalized_mode), 1)
    self._blackboard:clear(self:_objective_loop_key(normalized_mode))
end

---@param profile_id string
---@return boolean
---@return string|nil
function Client:load_profile(profile_id)
    local ok, err = self._config:set_active_profile(profile_id)
    if not ok then
        return false, err
    end

    self:_apply_runtime_bindings()
    self:_refresh_policy_cache_bindings()

    local ok_save, save_err = self._config:save_profiles()
    if not ok_save then
        return false, save_err
    end

    local ok_policy, policy_err = self._config:save_policy()
    if not ok_policy then
        return false, policy_err
    end

    return true, nil
end

---@param profile_name string
---@return boolean
---@return string|nil
---@return string|nil
function Client:create_profile(profile_name)
    local name = tostring(profile_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        name = "Profile"
    end

    local base_id = name:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if base_id == "" then
        base_id = "profile"
    end

    local existing = self._config:list_profiles()
    local used = {}
    for i = 1, #existing do
        used[tostring(existing[i].profile_id)] = true
    end

    local candidate = base_id
    local suffix = 1
    while used[candidate] do
        suffix = suffix + 1
        candidate = string.format("%s_%d", base_id, suffix)
    end

    local ok, err = self._config:save_as_profile(candidate, name)
    if not ok then
        return false, err, nil
    end

    local ok_save, save_err = self._config:save_profiles()
    if not ok_save then
        return false, save_err, nil
    end

    local ok_policy, policy_err = self._config:save_policy()
    if not ok_policy then
        return false, policy_err, nil
    end

    return true, nil, candidate
end

---@param profile_id string
---@param profile_name? string
---@return boolean
---@return string|nil
function Client:save_profile(profile_id, profile_name)
    local id = tostring(profile_id or "")
    if id == "" then
        id = self._config:get_active_profile_id()
    end

    local list = self._config:list_profiles()
    local resolved_name = profile_name
    if not resolved_name or resolved_name == "" then
        for i = 1, #list do
            if tostring(list[i].profile_id) == id then
                resolved_name = list[i].name
                break
            end
        end
        if not resolved_name or resolved_name == "" then
            resolved_name = id
        end
    end

    local ok, err = self._config:save_as_profile(id, resolved_name)
    if not ok then
        return false, err
    end

    local ok_policy, policy_err = self._config:save_policy()
    if not ok_policy then
        return false, policy_err
    end

    local ok_profiles, profiles_err = self._config:save_profiles()
    if not ok_profiles then
        return false, profiles_err
    end

    return true, nil
end

---@param profile_id string
---@return boolean
---@return string|nil
function Client:delete_profile(profile_id)
    local ok, err = self._config:delete_profile(profile_id)
    if not ok then
        return false, err
    end

    self:_apply_runtime_bindings()
    self:_refresh_policy_cache_bindings()

    local ok_save, save_err = self._config:save_profiles()
    if not ok_save then
        return false, save_err
    end

    return true, nil
end

---@param profile_id string
---@param new_name string
---@return boolean
---@return string|nil
function Client:rename_profile(profile_id, new_name)
    local ok, err = self._config:rename_profile(profile_id, new_name)
    if not ok then
        return false, err
    end

    local ok_save, save_err = self._config:save_profiles()
    if not ok_save then
        return false, save_err
    end
    return true, nil
end

---@return EventBus
function Client:get_event_bus()
    return self._event_bus
end

---@return Blackboard
function Client:get_blackboard()
    return self._blackboard
end

---@param limit? number
---@return table[]
function Client:get_log_feed(limit)
    if not self._logger or not self._logger.get_history then
        return {}
    end
    return self._logger:get_history(limit)
end

function Client:clear_log_feed()
    if self._logger and self._logger.clear_history then
        self._logger:clear_history()
    end
end

function Client:destroy()
    self:stop("destroy")
    self._telemetry:destroy()
    self._logger:destroy()
    self._event_bus:clear()
    self._blackboard:clear()
end

return Client
