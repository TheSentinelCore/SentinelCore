---@class SentinelEvents
local Events = {
    -- Core lifecycle
    STATE_CHANGED = "core.state_changed",
    FAILED = "core.failed",
    STARTED = "core.started",
    STOPPED = "core.stopped",
    PAUSED = "core.paused",
    RESUMED = "core.resumed",
    SNAPSHOT_UPDATED = "core.snapshot_updated",
    DEPENDENCY_HEALTH = "core.dependency_health",

    -- Context
    CONTEXT_RESOLVE_STARTED = "core.context_resolve_started",
    CONTEXT_RESOLVED = "core.context_resolved",
    CONTEXT_FAILED = "core.context_failed",

    -- Grind/targeting
    TARGET_ACQUIRED = "grind.target_acquired",
    TARGET_LOST = "grind.target_lost",
    TARGET_SCORE_DEBUG = "grind.target_score_debug",
    EXPLORATION_SELECTED = "grind.exploration_selected",

    -- Objectives
    OBJECTIVE_SELECTED = "objective.selected",
    OBJECTIVE_PROGRESS = "objective.progress",
    OBJECTIVE_COMPLETED = "objective.completed",
    OBJECTIVE_FAILED = "objective.failed",

    -- Combat
    PULL_STARTED = "combat.pull_started",
    ROTATION_EXECUTED = "combat.rotation_executed",
    ROTATION_BLOCKED = "combat.rotation_blocked",
    TARGET_SWITCHED = "combat.target_switched",
    KILL_CONFIRMED = "combat.kill_confirmed",
    COMBAT_FAILED = "combat.failed",
    COMBAT_CHASE_UPDATE = "combat.chase_update",

    -- Loot
    LOOT_STARTED = "loot.started",
    LOOT_COMPLETED = "loot.completed",
    LOOT_FAILED = "loot.failed",

    -- Inventory/vendor
    INVENTORY_THRESHOLD_REACHED = "inventory.threshold_reached",
    VENDOR_STARTED = "vendor.started",
    VENDOR_COMPLETED = "vendor.completed",
    VENDOR_FAILED = "vendor.failed",
    VENDOR_SELL_STARTED = "vendor.sell_started",
    VENDOR_SELL_ITEM = "vendor.sell_item",
    VENDOR_SELL_COMPLETED = "vendor.sell_completed",
    VENDOR_REPAIR_COMPLETED = "vendor.repair_completed",

    -- Recovery
    RECOVERY_STARTED = "recovery.started",
    RECOVERY_COMPLETED = "recovery.completed",
    RECOVERY_ESCALATED = "recovery.escalated",

    -- Death recovery
    DEATH_RECOVERY_STARTED = "death.recovery_started",
    DEATH_SPIRIT_RELEASED = "death.spirit_released",
    DEATH_CORPSE_RUN_UPDATE = "death.corpse_run_update",
    DEATH_RESURRECT_ATTEMPT = "death.resurrect_attempt",
    DEATH_RESURRECTED = "death.resurrected",

    -- Behavior Tree
    BT_TICK = "bt.tick",
    BT_SUBTREE_ENTERED = "bt.subtree_entered",
    BT_SUBTREE_EXITED = "bt.subtree_exited",

    -- Utility AI
    UTILITY_EVALUATED = "utility.evaluated",
    UTILITY_ACTION_SELECTED = "utility.action_selected",

    -- Telemetry
    TELEMETRY_FLUSHED = "telemetry.flushed",

    -- World
    HOSTILE_PLAYER_DETECTED = "world.hostile_player_detected",
    ZONE_CHANGED = "world.zone_changed",

    -- Profile coordinator
    PROFILE_LOADED = "profile.loaded",
    PROFILE_UNLOADED = "profile.unloaded",
    PROFILE_LOAD_FAILED = "profile.load_failed",
    HOTSPOT_ENTERED = "profile.hotspot_entered",
    HOTSPOT_ADVANCED = "profile.hotspot_advanced",
    HOTSPOT_TRAVEL_START = "profile.hotspot_travel_start",
    VENDOR_TRIP_START = "profile.vendor_trip_start",
    VENDOR_TRIP_COMPLETE = "profile.vendor_trip_complete",
    PROFILE_LOOP_COMPLETE = "profile.loop_complete",

    -- Profile recorder
    RECORDER_STARTED = "recorder.started",
    RECORDER_STOPPED = "recorder.stopped",
    RECORDER_HOTSPOT_ADDED = "recorder.hotspot_added",
    RECORDER_HOTSPOT_REMOVED = "recorder.hotspot_removed",

    -- Blackboard
    BB_PREFIX = "bb.",
}

return Events
