---@class BotManager
---@field private _event_bus EventBus
---@field private _state_machine StateMachine
---@field private _modules table<string, table>
---@field private _log Logger|nil
---@field private _config table
---@field private _running boolean
---@field private _paused boolean
---@field private _initialized boolean
---@field private _last_tick_time number
---@field private _tick_interval number
---@field private _pause_system table
---@field private _consecutive_nav_failures number
---@field private _max_consecutive_failures number
---@field private _navlib_available boolean
---@field private _navlib_error string|nil
---@field private _nav_recovery_cancel function|nil
local BotManager = {}
BotManager.__index = BotManager

-- Import dependencies (relative paths since we're in SentinelGather folder)
local EventBus = require("core/EventBus")
local StateMachine = require("core/StateMachine")
local Constants = require("core/Constants")
local Helpers = require("lib/Helpers")

local ModuleFactory = require("core/ModuleFactory")
local TravelingController = require("core/TravelingController")

local EVENTS = Constants.EVENTS
local STATES = Constants.STATES

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "lib/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("BotManager")
    end
    return nil
end

---Create a new BotManager instance
---@param config? table Optional configuration
---@return BotManager
function BotManager:new(config)
    local instance = setmetatable({}, BotManager)

    instance._log = get_logger()
    instance._config = config or {}

    -- Create core systems
    instance._event_bus = EventBus:new()
    instance._state_machine = StateMachine:new(instance._event_bus, STATES.IDLE)

    -- Module registry
    instance._modules = {}

    -- Bot state
    instance._running = false
    instance._paused = false
    instance._initialized = false

    -- Timing
    instance._last_tick_time = 0
    instance._tick_interval = 0.05  -- 50ms (20 ticks per second)
    instance._consecutive_nav_failures = 0
    instance._max_consecutive_failures = Constants.OPERATIONAL.MAX_CONSECUTIVE_NAV_FAILURES

    -- SentinelNavClient availability
    instance._navlib_available = false
    instance._navlib_error = nil

    -- Anti-detection
    instance._pause_system = {
        last_pause_time = 0,
        next_pause_check = 0,
        is_paused = false,
        pause_end_time = 0
    }

    if instance._log then
        instance._log:info("BotManager created")
    end

    return instance
end

---Initialize all modules
---@return boolean success
function BotManager:initialize()
    if self._initialized then
        if self._log then
            self._log:warn("Already initialized")
        end
        return true
    end

    if self._log then
        self._log:info("Initializing modules...")
    end

    -- Use SentinelNavClient's shared Facade (SentinelNavClient plugin must load before SentinelGather)
    if _G.SentinelNavClient and _G.SentinelNavClient.facade then
        self._navlib = _G.SentinelNavClient.facade
        self._modules.Navigation = self._navlib.nav_client
        self._modules.Movement   = self._navlib.movement
        self._modules.Obstacle   = self._navlib.obstacle

        self._navlib_available = true
        if self._log then
            self._log:debug("Using SentinelNavClient shared facade")
        end
    else
        self._navlib_available = false
        self._navlib_error = "SentinelNavClient plugin not loaded. Load SentinelNavClient before SentinelGather for navigation."
        if self._log then
            self._log:error(self._navlib_error)
        end
        self._event_bus:publish(EVENTS.NAV_UNAVAILABLE, {
            error = self._navlib_error,
            timestamp = core.time()
        })
    end

    -- Load local modules in order
    local module_order = {
        { name = "Settings",        path = "core/Settings" },
        { name = "ProfileManager",  path = "modules/ProfileManager" },
        { name = "NodeScanner",     path = "modules/NodeScanner" },
        { name = "Gather",          path = "modules/Gather" },
        { name = "Mount",           path = "modules/Mount" },
        { name = "Safety",          path = "modules/Safety" },
        { name = "Inventory",       path = "modules/Inventory" },
        { name = "Statistics",      path = "modules/Statistics" },
        { name = "PathVisualizer",  path = "modules/PathVisualizer" },
    }

    for _, module_info in ipairs(module_order) do
        local success, module_class = pcall(require, module_info.path)

        if success and module_class then
            local instance = self:_create_module_instance(module_info.name, module_class)
            if instance then
                self._modules[module_info.name] = instance
                if self._log then
                    self._log:debug("Loaded module: %s", module_info.name)
                end
            end
        else
            if self._log then
                self._log:error("Failed to load module %s: %s", module_info.name, tostring(module_class))
            end
        end
    end

    self._initialized = true

    -- Subscribe to events
    self:_subscribe_events()

    if self._log then
        self._log:info("Initialization complete - %d modules loaded", self:_count_modules())
    end

    return true
end

---Subscribe to bot-level events
function BotManager:_subscribe_events()
    -- Handle hotspot entry - transition to SCANNING state
    self._event_bus:subscribe(EVENTS.HOTSPOT_ENTERED, function(data)
        if self._log then
            self._log:info("Entered hotspot, transitioning to SCANNING")
        end
        self._state_machine:transition(STATES.SCANNING, {
            hotspot = data.waypoint,
            radius = data.radius,
            linger_time = data.linger_time
        })
    end, 50, false, "BotManager")

    -- Handle hotspot exit - return to TRAVELING
    self._event_bus:subscribe(EVENTS.HOTSPOT_EXITED, function()
        if self._log then
            self._log:debug("Exited hotspot, continuing to travel")
        end
        -- Only transition if currently scanning
        if self._state_machine:get_state() == STATES.SCANNING then
            self._state_machine:transition(STATES.TRAVELING)
        end
    end, 50, false, "BotManager")
end

---Create a module instance with appropriate dependencies
---@param name string Module name
---@param module_class table Module class
---@return table|nil instance
function BotManager:_create_module_instance(name, module_class)
    return ModuleFactory.create(name, module_class, {
        event_bus = self._event_bus,
        state_machine = self._state_machine,
        config = self._config,
        modules = self._modules,
    })
end

---Count loaded modules
---@return number
function BotManager:_count_modules()
    local count = 0
    for _ in pairs(self._modules) do
        count = count + 1
    end
    return count
end

---Start the bot
---@param profile_path? string Optional profile to load
---@return boolean success
function BotManager:start(profile_path)
    if not self._initialized then
        self:initialize()
    end

    if self._running then
        if self._log then
            self._log:warn("Bot is already running")
        end
        return false
    end

    -- Load profile if specified
    if profile_path then
        local profile_mgr = self._modules.ProfileManager
        if profile_mgr then
            local success = profile_mgr:load_profile(profile_path)
            if not success then
                if self._log then
                    self._log:error("Failed to load profile: %s", profile_path)
                end
                return false
            end
        end
    end

    self._running = true
    self._paused = false
    self._last_tick_time = core.time()
    TravelingController.reset()

    -- Transition to loading/traveling
    self._state_machine:transition(STATES.LOADING)

    if self._log then
        self._log:info("Bot started")
    end

    -- Publish start event
    self._event_bus:publish(EVENTS.BOT_START, {
        timestamp = core.time()
    })

    return true
end

---Stop the bot
function BotManager:stop()
    if not self._running then
        return
    end

    self._running = false
    self._paused = false
    TravelingController.reset()

    -- Cancel nav recovery timer if active
    if self._nav_recovery_cancel then
        self._nav_recovery_cancel()
        self._nav_recovery_cancel = nil
    end

    -- Stop movement
    local movement = self._modules.Movement
    if movement then
        movement:stop()
    end

    -- Cancel gathering
    local gather = self._modules.Gather
    if gather then
        gather:cancel_gather()
    end

    -- Reset to idle
    self._state_machine:reset()

    if self._log then
        self._log:info("Bot stopped")
    end

    -- Publish stop event
    self._event_bus:publish(EVENTS.BOT_STOP, {
        timestamp = core.time()
    })
end

---Pause the bot
function BotManager:pause()
    if not self._running or self._paused then
        return
    end

    self._paused = true

    -- Stop movement
    local movement = self._modules.Movement
    if movement then
        movement:stop()
    end

    -- Store current state
    local current_state = self._state_machine:get_state()
    self._state_machine:transition(STATES.PAUSED, {
        previous_state = current_state
    })

    if self._log then
        self._log:info("Bot paused")
    end

    self._event_bus:publish(EVENTS.BOT_PAUSE, {
        timestamp = core.time()
    })
end

---Resume the bot
function BotManager:resume()
    if not self._running or not self._paused then
        return
    end

    self._paused = false

    -- Return to previous state
    local ctx = self._state_machine:get_context()
    local previous_state = ctx.data.previous_state or STATES.TRAVELING

    self._state_machine:transition(previous_state)

    if self._log then
        self._log:info("Bot resumed")
    end

    self._event_bus:publish(EVENTS.BOT_RESUME, {
        timestamp = core.time()
    })
end

---Toggle pause state
function BotManager:toggle_pause()
    if self._paused then
        self:resume()
    else
        self:pause()
    end
end

---Main update tick (call from game loop)
function BotManager:update()
    if not self._running then
        return
    end

    local now = core.time()

    -- Rate limit ticks
    if now - self._last_tick_time < self._tick_interval then
        return
    end
    local delta = now - self._last_tick_time
    self._last_tick_time = now

    -- Don't process if paused
    if self._paused then
        return
    end

    -- Check for anti-detection pause
    if self:_check_random_pause() then
        return
    end

    -- Publish tick event
    self._event_bus:publish(EVENTS.TICK, {
        timestamp = now,
        delta = delta
    })

    -- Update all modules
    self:_update_modules()

    -- Run state logic
    self:_process_state()
end

---Update all modules
function BotManager:_update_modules()
    -- SentinelNavClient facade updates itself via its own on_update callback.
    -- We only update SentinelGather-specific modules here.
    local update_order = {
        "Safety",
        "NodeScanner",
        "Gather",
        "Mount",
        "Inventory",
        "Statistics",
    }

    for _, name in ipairs(update_order) do
        local module = self._modules[name]
        if module and module.update then
            local success, err = pcall(module.update, module)
            if not success and self._log then
                self._log:error("Error updating %s: %s", name, tostring(err))
            end
        end
    end
end

---Process current state logic
function BotManager:_process_state()
    local state = self._state_machine:get_state()

    if state == STATES.LOADING then
        self:_process_loading()
    elseif state == STATES.TRAVELING then
        self:_process_traveling()
    elseif state == STATES.SCANNING then
        self:_process_scanning()
    elseif state == STATES.APPROACHING then
        self:_process_approaching()
    elseif state == STATES.GATHERING then
        -- Handled by Gather
    elseif state == STATES.LOOTING then
        -- Handled by Gather
    elseif state == STATES.MOUNTING then
        -- Handled by Mount
    elseif state == STATES.COMBAT then
        self:_process_combat()
    elseif state == STATES.DEAD then
        self:_process_dead()
    elseif state == STATES.CORPSE_RUN then
        self:_process_corpse_run()
    elseif state == STATES.STUCK then
        self:_process_stuck()
    end
end

---Process loading state
function BotManager:_process_loading()
    local profile_mgr = self._modules.ProfileManager

    if profile_mgr and profile_mgr:is_profile_loaded() then
        -- Profile loaded, start traveling
        self._state_machine:transition(STATES.TRAVELING)
    else
        if self._log then
            self._log:warn("No profile loaded, stopping")
        end
        self:stop()
    end
end

---Process traveling state
function BotManager:_process_traveling()
    TravelingController.process({
        modules = self._modules,
        state_machine = self._state_machine,
        event_bus = self._event_bus,
        log = self._log,
        on_nav_failure = function()
            self._consecutive_nav_failures = self._consecutive_nav_failures + 1
            if self._consecutive_nav_failures >= self._max_consecutive_failures then
                if self._log then
                    self._log:error("Too many consecutive navigation failures (%d), pausing",
                        self._consecutive_nav_failures)
                end
                self._event_bus:publish(EVENTS.NAV_FAILURE_THRESHOLD, {
                    failure_count = self._consecutive_nav_failures,
                    timestamp = core.time()
                })
                self:pause()
                local izi = require("common/izi_sdk")
                self._nav_recovery_cancel = izi.after(Constants.OPERATIONAL.NAV_RECOVERY_COOLDOWN, function()
                    self._consecutive_nav_failures = 0
                    self._nav_recovery_cancel = nil
                    if self._paused then
                        self:resume()
                        if self._log then
                            self._log:info("Navigation recovery: resumed after cooldown")
                        end
                    end
                end)
                return true  -- signal: bot paused
            end
            return false
        end,
        on_nav_success = function()
            self._consecutive_nav_failures = 0
        end,
    })
end

---Process scanning state (at hotspot)
function BotManager:_process_scanning()
    local scanner = self._modules.NodeScanner
    local safety = self._modules.Safety
    local movement = self._modules.Movement

    if scanner then
        local nodes = scanner:scan()

        if #nodes > 0 and safety and safety:is_safe_to_gather() then
            local node = scanner:get_node_with_variance()
            if node then
                self._state_machine:transition(STATES.APPROACHING, {
                    target_node = node
                })

                if movement then
                    movement:move_to(node.position, nil, {
                        use_navmesh = true
                    })
                end
                return
            end
        end
    end

    -- No nodes found, continue traveling
    self._state_machine:transition(STATES.TRAVELING)
end

---Process approaching state
function BotManager:_process_approaching()
    local movement = self._modules.Movement

    -- If movement stopped but we're still in APPROACHING, something went wrong
    if movement and not movement:is_moving() then
        -- Check if we've been stuck in this state too long
        local ctx = self._state_machine:get_context()
        local approach_start = ctx.data and ctx.data.approach_start_time

        if not approach_start then
            -- First time noticing we're stuck, record start time
            ctx.data = ctx.data or {}
            ctx.data.approach_start_time = core.time()
        elseif core.time() - approach_start > Constants.OPERATIONAL.APPROACH_TIMEOUT then
            -- Stuck for over 2 seconds, abort approach
            if self._log then
                self._log:warn("Stuck in APPROACHING state, returning to TRAVELING")
            end

            -- Blacklist the node if we have one
            local node = ctx.data and ctx.data.target_node
            local scanner = self._modules.NodeScanner
            if node and node.guid and scanner then
                scanner:blacklist_node(node.guid, "Approach timeout")
            end

            self._state_machine:transition(STATES.TRAVELING)
        end
    end
end

---Process combat state
function BotManager:_process_combat()
    local safety = self._modules.Safety

    -- Combat handling is primarily done by Safety
    -- Could add flee logic here if needed
end

---Process dead state
function BotManager:_process_dead()
    local safety = self._modules.Safety

    if safety then
        -- Auto-release after short delay
        local ctx = self._state_machine:get_context()
        local death_time = ctx.data.death_time or core.time()

        if core.time() - death_time > Helpers.gaussian_random(2, 5) then
            safety:release_spirit()
        end
    end
end

---Process corpse run state
function BotManager:_process_corpse_run()
    local safety = self._modules.Safety
    local movement = self._modules.Movement

    if not safety or not movement then
        return
    end

    local corpse_pos = safety:get_corpse_position()
    if not corpse_pos then
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    -- Move to corpse if not moving
    if not movement:is_moving() then
        local player_pos = player:get_position()
        local dist = Helpers.distance_3d(player_pos, corpse_pos)

        if dist > Constants.OPERATIONAL.RESURRECT_DISTANCE then
            movement:move_to(corpse_pos, nil, {
                use_navmesh = true
            })
        else
            -- Close enough, resurrect
            safety:resurrect()
        end
    end
end

---Process stuck state
function BotManager:_process_stuck()
    -- Movement module handles unstuck attempts
    -- After unstuck, should transition back to traveling
    local movement = self._modules.Movement

    if movement and not movement:is_moving() then
        -- Unstuck complete, return to traveling
        self._state_machine:transition(STATES.TRAVELING)
    end
end

---Check for random anti-detection pause
---@return boolean is_pausing
function BotManager:_check_random_pause()
    local settings = self._modules.Settings
    if not settings then
        return false
    end

    local anti_detection = settings.get("anti_detection") or {}
    if not anti_detection.enabled or not anti_detection.random_pause_enabled then
        return false
    end

    local now = core.time()
    local ps = self._pause_system

    -- Currently pausing
    if ps.is_paused then
        if now >= ps.pause_end_time then
            ps.is_paused = false
            if self._log then
                self._log:debug("Random pause ended")
            end
            return false
        end
        return true
    end

    -- Check if should pause
    local min_interval = anti_detection.random_pause_min_interval or 30
    local max_interval = anti_detection.random_pause_max_interval or 90

    if now - ps.last_pause_time < min_interval then
        return false
    end

    if now < ps.next_pause_check then
        return false
    end

    ps.next_pause_check = now + 1  -- Check every second

    local chance = anti_detection.random_pause_chance or 0.03
    if math.random() < chance then
        -- Start pause
        local min_duration = anti_detection.random_pause_min_duration or 2
        local max_duration = anti_detection.random_pause_max_duration or 8

        ps.is_paused = true
        ps.last_pause_time = now
        ps.pause_end_time = now + Helpers.gaussian_random(min_duration, max_duration)

        if self._log then
            self._log:debug("Random pause started (%.1fs)", ps.pause_end_time - now)
        end

        return true
    end

    return false
end

---Get a module by name
---@param name string Module name
---@return table|nil
function BotManager:get_module(name)
    return self._modules[name]
end

---Check if navigation is available
---@return boolean
function BotManager:is_navigation_available()
    return self._navlib_available
end

---Get navigation error message
---@return string|nil
function BotManager:get_navigation_error()
    return self._navlib_error
end

---Get the event bus
---@return EventBus
function BotManager:get_event_bus()
    return self._event_bus
end

---Get the state machine
---@return StateMachine
function BotManager:get_state_machine()
    return self._state_machine
end

---Get loaded module count
---@return number
function BotManager:get_module_count()
    return self:_count_modules()
end

---Check if bot is running
---@return boolean
function BotManager:is_running()
    return self._running
end

---Check if bot is paused
---@return boolean
function BotManager:is_paused()
    return self._paused
end

---Get current state
---@return string
function BotManager:get_state()
    return self._state_machine:get_state()
end

---Clean up and destroy
function BotManager:destroy()
    self:stop()

    -- Destroy SentinelGather-owned modules only.
    -- SentinelNavClient modules (Navigation, Movement, Obstacle) are shared references
    -- owned by SentinelNavClient's singleton — do not destroy them here.
    local navlib_modules = { Navigation = true, Movement = true, Obstacle = true }
    for name, module in pairs(self._modules) do
        if not navlib_modules[name] and module.destroy then
            pcall(module.destroy, module)
        end
    end

    self._modules = {}
    self._initialized = false

    if self._log then
        self._log:info("BotManager destroyed")
    end
end

---Run unit tests
---@return table<string, boolean> Test results
function BotManager:_test()
    local results = {}

    -- Test 1: Create manager
    local manager = BotManager:new()
    results.create = (manager ~= nil)

    -- Test 2: Initial state
    results.initial_not_running = not manager:is_running()
    results.initial_not_paused = not manager:is_paused()
    results.initial_state_idle = (manager:get_state() == STATES.IDLE)

    -- Test 3: Event bus exists
    results.has_event_bus = (manager:get_event_bus() ~= nil)

    -- Test 4: State machine exists
    results.has_state_machine = (manager:get_state_machine() ~= nil)

    -- Test 5: Module count before init
    results.modules_before_init = (manager:_count_modules() == 0)

    return results
end

return BotManager
