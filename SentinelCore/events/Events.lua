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

    -- Recovery
    RECOVERY_STARTED = "recovery.started",
    RECOVERY_COMPLETED = "recovery.completed",
    RECOVERY_ESCALATED = "recovery.escalated",

    -- Telemetry
    TELEMETRY_FLUSHED = "telemetry.flushed",

    -- Blackboard
    BB_PREFIX = "bb.",
}

return Events
