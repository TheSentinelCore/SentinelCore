---@class Constants
---GatherBuddy constants - states, events, configuration defaults
local Constants = {}

-- Make tables read-only (Lua 5.1 compatible)
-- Copies values into the table so pairs() works, but prevents modification
local function freeze(tbl)
    local frozen = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            frozen[k] = freeze(v)  -- Recursively freeze nested tables
        else
            frozen[k] = v
        end
    end
    return setmetatable(frozen, {
        __newindex = function()
            error("Attempt to modify read-only table")
        end,
        __metatable = false
    })
end

---Bot states for the state machine
Constants.STATES = freeze({
    IDLE            = "idle",           -- Bot stopped/paused
    LOADING         = "loading",        -- Loading profile
    TRAVELING       = "traveling",      -- Moving along route
    SCANNING        = "scanning",       -- At hotspot, scanning for nodes
    APPROACHING     = "approaching",    -- Moving to detected node
    GATHERING       = "gathering",      -- Interacting with node (casting)
    LOOTING         = "looting",        -- Loot window open
    MOUNTING        = "mounting",       -- Mount cast in progress
    DISMOUNTING     = "dismounting",    -- Dismount in progress
    COMBAT          = "combat",         -- In combat
    FLEEING         = "fleeing",        -- Running from enemies
    DEAD            = "dead",           -- Player dead
    CORPSE_RUN      = "corpse_run",     -- Ghost running to corpse
    STUCK           = "stuck",          -- Stuck, attempting recovery
    PAUSED          = "paused",         -- Temporarily paused
})

---Event names for the event bus (from GATHERBUDDY_DESIGN.md)
Constants.EVENTS = freeze({
    -- Lifecycle
    BOT_START               = "bot:start",
    BOT_STOP                = "bot:stop",
    BOT_PAUSE               = "bot:pause",
    BOT_RESUME              = "bot:resume",
    TICK                    = "bot:tick",

    -- Profile
    PROFILE_LOAD_REQUEST    = "profile:load_request",
    PROFILE_LOADED          = "profile:loaded",
    PROFILE_LOAD_FAILED     = "profile:load_failed",
    PROFILE_UNLOADED        = "profile:unloaded",
    WAYPOINT_REACHED        = "profile:waypoint_reached",
    WAYPOINT_ADDED          = "profile:waypoint_added",
    WAYPOINT_REMOVED        = "profile:waypoint_removed",
    WAYPOINTS_CLEARED       = "profile:waypoints_cleared",
    HOTSPOT_ENTERED         = "profile:hotspot_entered",
    HOTSPOT_EXITED          = "profile:hotspot_exited",
    ROUTE_COMPLETED         = "profile:route_completed",

    -- Scanning
    NODE_DETECTED           = "scanner:node_detected",
    NODE_LOST               = "scanner:node_lost",
    NODE_BLACKLISTED        = "scanner:node_blacklisted",
    SCAN_COMPLETE           = "scanner:scan_complete",

    -- Gathering
    GATHER_START            = "gather:start",
    GATHER_PROGRESS         = "gather:progress",
    GATHER_SUCCESS          = "gather:success",
    GATHER_FAILED           = "gather:failed",
    GATHER_INTERRUPTED      = "gather:interrupted",
    LOOT_WINDOW_OPENED      = "gather:loot_opened",
    LOOT_WINDOW_CLOSED      = "gather:loot_closed",
    ITEM_LOOTED             = "gather:item_looted",

    -- Movement
    MOVE_TO                 = "movement:move_to",
    MOVEMENT_STARTED        = "movement:started",
    MOVEMENT_COMPLETED      = "movement:completed",
    MOVEMENT_STOPPED        = "movement:stopped",
    MOVEMENT_STUCK          = "movement:stuck",
    MOVEMENT_STOP           = "movement:stop",
    PATH_REQUEST            = "movement:path_request",
    PATH_REQUESTED          = "movement:path_requested",
    PATH_RECEIVED           = "movement:path_received",
    PATH_FAILED             = "movement:path_failed",

    -- Route planning
    ROUTE_PLANNED           = "route:planned",
    ROUTE_REPLANNED         = "route:replanned",
    ROUTE_LEG_COMPLETED     = "route:leg_completed",
    PATH_INVALIDATED        = "route:path_invalidated",

    -- Safety
    ENEMY_DETECTED          = "safety:enemy_detected",
    COMBAT_ENTERED          = "safety:combat_entered",
    COMBAT_EXITED           = "safety:combat_exited",
    PLAYER_DIED             = "safety:player_died",
    PLAYER_RESURRECTED      = "safety:player_resurrected",
    THREAT_LEVEL_CHANGED    = "safety:threat_level_changed",

    -- Mount
    MOUNT_REQUESTED         = "mount:requested",
    MOUNT_STARTED           = "mount:started",
    MOUNT_COMPLETED         = "mount:completed",
    MOUNT_FAILED            = "mount:failed",
    DISMOUNT_REQUESTED      = "mount:dismount_requested",

    -- Inventory
    BAGS_FULL               = "inventory:bags_full",

    -- State
    STATE_CHANGED           = "state:changed",

    -- Navigation availability
    NAV_UNAVAILABLE         = "nav:unavailable",
    NAV_FAILURE_THRESHOLD   = "nav:failure_threshold",
})

---Waypoint types for profiles
Constants.WAYPOINT_TYPES = freeze({
    PATH        = "path",       -- Standard navigation waypoint
    HOTSPOT     = "hotspot",    -- Linger and scan for nodes
    VENDOR      = "vendor",     -- Vendor location
    MAILBOX     = "mailbox",    -- Mailbox location
    SAFE        = "safe",       -- Safe AFK spot
})

---Gathering types
Constants.GATHER_TYPES = freeze({
    HERB    = "herb",
    ORE     = "ore",
})

---Profession spell IDs (used to check if player has the skill)
Constants.PROFESSION_SPELL_IDS = freeze({
    HERBALISM = 2366,   -- Herb Gathering
    MINING = 2575,      -- Mining
})

---Threat levels for safety system
Constants.THREAT_LEVELS = freeze({
    SAFE        = 0,    -- No enemies nearby
    CAUTION     = 1,    -- Enemies in area but not close
    DANGER      = 2,    -- Enemies very close
    COMBAT      = 3,    -- In combat
})

---Internal gathering states
Constants.GATHER_STATES = freeze({
    NONE                = "none",
    FACING              = "facing",
    DISMOUNTING         = "dismounting",
    APPROACHING_FINAL   = "approaching_final",
    INTERACTING         = "interacting",
    CASTING             = "casting",
    WAITING_LOOT        = "waiting_loot",
    LOOTING             = "looting",
    COMPLETE            = "complete",
    FAILED              = "failed",
})

---Unstuck strategies with named keys for consistent access
Constants.UNSTUCK_STRATEGIES = freeze({
    JUMP = "jump",
    STRAFE = "strafe",
    BACKWARD = "backward",
    REPATH = "repath",
    SKIP_WAYPOINT = "skip_waypoint",
})

---Valid state transitions
Constants.VALID_TRANSITIONS = {
    [Constants.STATES.IDLE] = {
        Constants.STATES.LOADING,
    },
    [Constants.STATES.LOADING] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
    },
    [Constants.STATES.TRAVELING] = {
        Constants.STATES.IDLE,
        Constants.STATES.SCANNING,
        Constants.STATES.APPROACHING,
        Constants.STATES.MOUNTING,
        Constants.STATES.COMBAT,
        Constants.STATES.DEAD,
        Constants.STATES.STUCK,
        Constants.STATES.PAUSED,
    },
    [Constants.STATES.SCANNING] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
        Constants.STATES.APPROACHING,
        Constants.STATES.COMBAT,
        Constants.STATES.DEAD,
        Constants.STATES.PAUSED,
    },
    [Constants.STATES.APPROACHING] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
        Constants.STATES.GATHERING,
        Constants.STATES.DISMOUNTING,
        Constants.STATES.COMBAT,
        Constants.STATES.DEAD,
        Constants.STATES.STUCK,
        Constants.STATES.PAUSED,
    },
    [Constants.STATES.DISMOUNTING] = {
        Constants.STATES.IDLE,
        Constants.STATES.GATHERING,
        Constants.STATES.APPROACHING,
        Constants.STATES.COMBAT,
        Constants.STATES.DEAD,
    },
    [Constants.STATES.GATHERING] = {
        Constants.STATES.IDLE,
        Constants.STATES.LOOTING,
        Constants.STATES.TRAVELING,
        Constants.STATES.SCANNING,
        Constants.STATES.COMBAT,
        Constants.STATES.DEAD,
    },
    [Constants.STATES.LOOTING] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
        Constants.STATES.MOUNTING,
        Constants.STATES.SCANNING,
        Constants.STATES.COMBAT,
        Constants.STATES.DEAD,
    },
    [Constants.STATES.MOUNTING] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
        Constants.STATES.COMBAT,
        Constants.STATES.DEAD,
    },
    [Constants.STATES.COMBAT] = {
        Constants.STATES.IDLE,
        Constants.STATES.FLEEING,
        Constants.STATES.DEAD,
        Constants.STATES.TRAVELING,
        Constants.STATES.SCANNING,
        Constants.STATES.APPROACHING,
        Constants.STATES.GATHERING,
        Constants.STATES.LOOTING,
        Constants.STATES.MOUNTING,
    },
    [Constants.STATES.FLEEING] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
        Constants.STATES.COMBAT,
        Constants.STATES.DEAD,
    },
    [Constants.STATES.DEAD] = {
        Constants.STATES.CORPSE_RUN,
        Constants.STATES.IDLE,
    },
    [Constants.STATES.CORPSE_RUN] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
        Constants.STATES.DEAD,
    },
    [Constants.STATES.STUCK] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
        Constants.STATES.APPROACHING,
    },
    [Constants.STATES.PAUSED] = {
        Constants.STATES.IDLE,
        Constants.STATES.TRAVELING,
        Constants.STATES.SCANNING,
        Constants.STATES.APPROACHING,
    },
}

---Default settings for the bot
Constants.DEFAULT_SETTINGS = {
    general = {
        enabled = true,
        debug_mode = false,
        log_level = "info",
    },

    movement = {
        mount_threshold = 40,           -- Distance in yards to trigger mounting
        dismount_distance = 8,          -- Distance to dismount before node
        preferred_mount_index = 1,      -- Mount collection index
        stuck_check_interval = 2.0,     -- Seconds between stuck checks
        stuck_distance_threshold = 1.5, -- Minimum yards to move
        max_stuck_attempts = 5,         -- Maximum unstuck attempts
        path_deviation_percent = 0.10,  -- 10% path deviation for anti-detection
        waypoint_tolerance = 3.0,       -- How close to get to waypoints
        lookahead_variance = 0.5,       -- Variance added to lookahead distance for anti-detection
        micro_pause_enabled = true,     -- Enable micro-pauses for anti-detection
        micro_pause_interval_min = 2.0, -- Minimum seconds between micro-pauses
        micro_pause_interval_max = 5.0, -- Maximum seconds between micro-pauses
        preferred_smoothing = "none", -- Preferred path smoothing algorithm (none=safest, keeps all navmesh waypoints)
        smooth_iterations = 2,    -- Chaikin iterations (1-5, default 2)
        smooth_samples = 10,      -- Catmull-Rom/Bezier samples (5-50, default 10)
        smooth_ratio = 0.75,          -- Chaikin corner-cut ratio (0.5-0.95)
        min_corner_angle = 90.0,      -- Min corner angle to smooth (0-180, skip sharp corners like doorways)
        keep_originals = true,        -- Keep original navmesh waypoints (safer indoors)
        path_optimize = false,        -- String-pulling optimization
        anti_detection = false,       -- Use random deviation endpoint
        max_deviation = 5.0,          -- Max random deviation in yards
        filter_ground = 1.0,          -- Ground area cost multiplier
        filter_water = 10.0,          -- Water area cost multiplier
        filter_lava = 100.0,          -- Lava area cost multiplier
        use_corridor_indoor = true,   -- Use corridor pathfinding in dungeons/raids
        corridor_probe_dist = 15.0,   -- Lateral probe distance for corridor width (yards)
        wall_clearance_enabled = false, -- Push waypoints away from walls/obstacles
        wall_clearance = 1.5,         -- Min distance from walls (yards, 0.5-5.0)
    },

    gathering = {
        gather_herbs = true,            -- Enable herb gathering
        gather_ores = true,             -- Enable ore gathering
        check_skills = true,            -- Auto-disable if player lacks skill
        node_search_radius = 80,        -- Yards to search for nodes
        gather_timeout = 10,            -- Seconds before giving up
        loot_delay_min = 0.05,          -- Minimum delay between loots
        loot_delay_max = 0.15,          -- Maximum delay between loots
        node_blacklist_duration = 300,  -- 5 minutes for gathered nodes
        failed_node_blacklist_duration = 60, -- 1 minute for failed nodes
        max_approach_distance = 100,    -- Max distance to deviate for a node
    },

    safety = {
        enemy_scan_radius = 30,         -- Yards to scan for enemies
        skip_if_enemies_near = true,    -- Skip nodes if enemies close
        enemy_near_threshold = 15,      -- How close is "near"
        flee_health_threshold = 30,     -- Health % to trigger flee
        death_release_delay_min = 3,    -- Minimum delay before releasing
        death_release_delay_max = 10,   -- Maximum delay before releasing
    },

    anti_detection = {
        enabled = true,
        random_pause_enabled = true,
        random_pause_interval_min = 30, -- Seconds between pauses
        random_pause_interval_max = 90,
        random_pause_duration_min = 2,  -- Pause length in seconds
        random_pause_duration_max = 8,
        random_pause_chance = 0.03,     -- 3% chance per check
        random_jump_enabled = true,
        random_jump_interval_min = 45,  -- Seconds between jumps
        random_jump_interval_max = 120,
        gather_order_randomization = true, -- Don't always pick nearest
        action_delay_min = 0.15,        -- Minimum delay between actions
        action_delay_max = 0.6,         -- Maximum delay between actions
    },

    inventory = {
        min_free_slots = 2,             -- Warning threshold
    },

    hotspot = {
        default_linger_time = 5,        -- Seconds to wait at hotspot
        default_scan_radius = 30,       -- Radius to scan at hotspot
    },

    navigation = {
        base_url = "http://localhost:47110",
        timeout_ms = 5000,
        retry_count = 3,
        retry_delay_ms = 500,
        path_check_interval = 5.0,      -- Seconds between path/check calls
        path_check_max_ahead = 10,      -- Max waypoints to check ahead
        tsp_return_to_start = true,     -- Loop route back to start
        replan_on_gather = true,        -- Re-plan from current pos after gathering
    },

    ui = {
        show_overlay = true,
        show_statistics = true,
        window_x = 100,
        window_y = 100,
    },
}

---Error codes
Constants.ERROR_CODES = freeze({
    INVALID_PROFILE         = "E001",
    PROFILE_NOT_FOUND       = "E002",
    NAV_SERVICE_UNREACHABLE = "E003",
    PATH_NOT_FOUND          = "E004",
    NODE_DESPAWNED          = "E005",
    GATHER_TIMEOUT          = "E006",
    STUCK_UNRECOVERABLE     = "E007",
    INVALID_GAME_STATE      = "E008",
})

---Available smoothing algorithms for path processing (NavBuddy)
---@type table<number, {id: string, name: string, description: string}>
Constants.SMOOTHING_ALGORITHMS = {
    { id = "none", name = "None", description = "Keep exact navmesh waypoints" },
    { id = "chaikin", name = "Chaikin", description = "Corner cutting smoothing" },
    { id = "catmull_rom", name = "Catmull-Rom", description = "Spline interpolation" },
    { id = "bezier", name = "Bezier", description = "Bezier curve smoothing" },
}

---Operational constants (hardcoded thresholds extracted for visibility)
Constants.OPERATIONAL = freeze({
    -- Gathering timing
    LOOT_WINDOW_TIMEOUT = 0.5,        -- Seconds to wait for loot window after cast
    INTERACTION_TIMEOUT = 1.0,        -- Seconds to wait for cast to start after interact

    -- Threat distance thresholds (yards)
    THREAT_DISTANCE_DANGER = 10,
    THREAT_DISTANCE_CAUTION = 20,

    -- Navigation recovery
    MAX_CONSECUTIVE_NAV_FAILURES = 10,
    NAV_RECOVERY_COOLDOWN = 30,       -- Seconds to pause before retry

    -- Approach
    APPROACH_TIMEOUT = 2.0,           -- Seconds before aborting approach

    -- Corpse run
    RESURRECT_DISTANCE = 10,          -- Yards from corpse to resurrect

    -- UI
    PROFILE_SCAN_INTERVAL = 5,        -- Seconds between profile rescans
})

---Run unit tests
---@return table<string, boolean> Test results
function Constants._test()
    local results = {}

    -- Test that STATES exists and has expected values
    results.states_exists = (Constants.STATES ~= nil)
    results.states_idle = (Constants.STATES.IDLE == "idle")
    results.states_traveling = (Constants.STATES.TRAVELING == "traveling")

    -- Test that EVENTS exists
    results.events_exists = (Constants.EVENTS ~= nil)
    results.events_bot_start = (Constants.EVENTS.BOT_START == "bot:start")

    -- Test valid transitions exist
    results.transitions_exist = (Constants.VALID_TRANSITIONS ~= nil)
    results.transitions_idle = (Constants.VALID_TRANSITIONS[Constants.STATES.IDLE] ~= nil)

    -- Test default settings
    results.settings_exist = (Constants.DEFAULT_SETTINGS ~= nil)
    results.settings_movement = (Constants.DEFAULT_SETTINGS.movement ~= nil)
    results.settings_mount_threshold = (Constants.DEFAULT_SETTINGS.movement.mount_threshold == 40)

    -- Test freeze functionality (should error on write attempt)
    local freeze_works = false
    local success = pcall(function()
        Constants.STATES.NEW_STATE = "test"
    end)
    freeze_works = not success
    results.freeze_works = freeze_works

    return results
end

return Constants
