local Events = require("events/Events")
local get_now = require("lib/TimeHelper").get_now

---@class SentinelConsoleLogger
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _enabled boolean
---@field private _Logger SentinelLogger|nil
local ConsoleLogger = {}
ConsoleLogger.__index = ConsoleLogger

-- Level numbers matching Logger.get_levels()
local LEVEL_DEBUG = 1
local LEVEL_INFO = 2
local LEVEL_WARNING = 3
local LEVEL_ERROR = 4

---@param event_bus EventBus
---@param blackboard Blackboard
---@param LoggerClass? SentinelLogger
---@return SentinelConsoleLogger
function ConsoleLogger:new(event_bus, blackboard, LoggerClass)
    local o = setmetatable({}, ConsoleLogger)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._enabled = true
    o._Logger = LoggerClass or nil
    o:_bind()
    return o
end

---@private
---@param level_num number
---@param message string
---@param event_name? string
function ConsoleLogger:_log(level_num, message, event_name)
    -- Push to shared Logger history if available
    if self._Logger and self._Logger.push_history then
        self._Logger.push_history(level_num, message, event_name or "event")
    end

    if not self._enabled then
        return
    end

    -- Level filtering via Logger global level
    if self._Logger and self._Logger.get_global_level then
        if level_num < self._Logger.get_global_level() then
            return
        end
    end

    local prefix = "[SentinelCore] "
    if not core then
        return
    end

    if level_num >= LEVEL_ERROR and core.log_error then
        core.log_error(prefix .. message)
        return
    end
    if level_num >= LEVEL_WARNING and core.log_warning then
        core.log_warning(prefix .. message)
        return
    end
    if core.log then
        core.log(prefix .. message)
    end
end

---@private
function ConsoleLogger:_bind()
    -- === Core lifecycle (existing, 6 events) ===
    self._event_bus:on(Events.STATE_CHANGED, function(data)
        self:_log(LEVEL_INFO, string.format("state %s -> %s (%s)",
            tostring(data.from),
            tostring(data.to),
            tostring(data.substate_to or "-")), Events.STATE_CHANGED)
    end, { owner = self })

    self._event_bus:on(Events.STARTED, function(data)
        self:_log(LEVEL_INFO, "started mode=" .. tostring(data and data.mode or "unknown"), Events.STARTED)
    end, { owner = self })

    self._event_bus:on(Events.STOPPED, function(data)
        self:_log(LEVEL_INFO, "stopped reason=" .. tostring(data and data.reason or "-"), Events.STOPPED)
    end, { owner = self })

    self._event_bus:on(Events.PAUSED, function(data)
        self:_log(LEVEL_WARNING, "paused reason=" .. tostring(data and data.reason or "-"), Events.PAUSED)
    end, { owner = self })

    self._event_bus:on(Events.RESUMED, function()
        self:_log(LEVEL_INFO, "resumed", Events.RESUMED)
    end, { owner = self })

    self._event_bus:on(Events.FAILED, function(data)
        self:_log(LEVEL_ERROR, "failed: " .. tostring(data.error_code or "unknown"), Events.FAILED)
    end, { owner = self })

    -- === Context (3 events: 1 existing + 2 new) ===
    self._event_bus:on(Events.CONTEXT_RESOLVE_STARTED, function()
        self:_log(LEVEL_DEBUG, "context resolve started", Events.CONTEXT_RESOLVE_STARTED)
    end, { owner = self })

    self._event_bus:on(Events.CONTEXT_RESOLVED, function(data)
        local ctx = data and data.context or {}
        self:_log(LEVEL_INFO, string.format("context resolved map=%s zone=%s area=%s",
            tostring(ctx.map_id or "?"),
            tostring(ctx.zone_id or "?"),
            tostring(ctx.area_id or "?")), Events.CONTEXT_RESOLVED)
    end, { owner = self })

    self._event_bus:on(Events.CONTEXT_FAILED, function(data)
        self:_log(LEVEL_WARNING, "context resolve failed: " .. tostring(data.error_code or "unknown"), Events.CONTEXT_FAILED)
    end, { owner = self })

    -- === Targeting (3 new + 1 existing) ===
    self._event_bus:on(Events.TARGET_ACQUIRED, function(data)
        self:_log(LEVEL_INFO, string.format("target acquired: %s (score=%.2f)",
            tostring(data and data.target_name or "unknown"),
            tonumber(data and data.score) or 0), Events.TARGET_ACQUIRED)
    end, { owner = self })

    self._event_bus:on(Events.TARGET_LOST, function(data)
        self:_log(LEVEL_INFO, string.format("target lost: %s reason=%s",
            tostring(data and data.target_name or "unknown"),
            tostring(data and data.reason or "-")), Events.TARGET_LOST)
    end, { owner = self })

    self._event_bus:on(Events.TARGET_SCORE_DEBUG, function(data)
        self:_log(LEVEL_DEBUG, string.format("target score: %s score=%.2f",
            tostring(data and data.target_name or "unknown"),
            tonumber(data and data.score) or 0), Events.TARGET_SCORE_DEBUG)
    end, { owner = self })

    self._event_bus:on(Events.TARGET_SWITCHED, function(data)
        self:_log(LEVEL_WARNING, string.format(
            "combat target switched (%s): %s -> %s",
            tostring(data and data.reason or "unknown"),
            tostring(data and data.from_target_name or "unknown"),
            tostring(data and data.to_target_name or "unknown")
        ), Events.TARGET_SWITCHED)
    end, { owner = self })

    -- === Exploration (1 new) ===
    self._event_bus:on(Events.EXPLORATION_SELECTED, function(data)
        self:_log(LEVEL_INFO, string.format("exploration: %s",
            tostring(data and data.reason or "selected")), Events.EXPLORATION_SELECTED)
    end, { owner = self })

    -- === Objectives (existing 3 + 1 new) ===
    self._event_bus:on(Events.OBJECTIVE_SELECTED, function(data)
        local objective = data and data.objective or {}
        self:_log(LEVEL_INFO, string.format(
            "objective selected (%s): %s",
            tostring(data and data.mode or "unknown"),
            tostring(objective.label or objective.id or "objective")
        ), Events.OBJECTIVE_SELECTED)
    end, { owner = self })

    self._event_bus:on(Events.OBJECTIVE_PROGRESS, function(data)
        self:_log(LEVEL_DEBUG, string.format("objective progress: %s",
            tostring(data and data.status or "-")), Events.OBJECTIVE_PROGRESS)
    end, { owner = self })

    self._event_bus:on(Events.OBJECTIVE_COMPLETED, function(data)
        local objective = data and data.objective or {}
        self:_log(LEVEL_INFO, string.format(
            "objective completed (%s): %s",
            tostring(data and data.mode or "unknown"),
            tostring(objective.label or objective.id or "objective")
        ), Events.OBJECTIVE_COMPLETED)
    end, { owner = self })

    self._event_bus:on(Events.OBJECTIVE_FAILED, function(data)
        local objective = data and data.objective or {}
        self:_log(LEVEL_WARNING, string.format(
            "objective failed (%s): %s err=%s",
            tostring(data and data.mode or "unknown"),
            tostring(objective.label or objective.id or "objective"),
            tostring(data and data.error_code or "unknown")
        ), Events.OBJECTIVE_FAILED)
    end, { owner = self })

    -- === Combat (6 events: 2 existing + 4 new) ===
    self._event_bus:on(Events.PULL_STARTED, function(data)
        self:_log(LEVEL_INFO, string.format("pull started: %s",
            tostring(data and data.target_name or "unknown")), Events.PULL_STARTED)
    end, { owner = self })

    self._event_bus:on(Events.KILL_CONFIRMED, function(data)
        self:_log(LEVEL_INFO, string.format("kill confirmed: %s",
            tostring(data and data.target_name or "unknown")), Events.KILL_CONFIRMED)
    end, { owner = self })

    self._event_bus:on(Events.COMBAT_FAILED, function(data)
        self:_log(LEVEL_WARNING, "combat failed: " .. tostring(data and data.error_code or "unknown"), Events.COMBAT_FAILED)
    end, { owner = self })

    self._event_bus:on(Events.ROTATION_EXECUTED, function(data)
        self:_log(LEVEL_DEBUG, string.format("rotation executed: %s",
            tostring(data and data.action or "-")), Events.ROTATION_EXECUTED)
    end, { owner = self })

    self._event_bus:on(Events.ROTATION_BLOCKED, function(data)
        self:_log(LEVEL_DEBUG, string.format("rotation blocked: %s",
            tostring(data and data.reason or "-")), Events.ROTATION_BLOCKED)
    end, { owner = self })

    self._event_bus:on(Events.COMBAT_CHASE_UPDATE, function(data)
        self:_log(LEVEL_DEBUG, string.format("chase update: dist=%.1f",
            tonumber(data and data.distance) or 0), Events.COMBAT_CHASE_UPDATE)
    end, { owner = self })

    -- === Loot (3 new) ===
    self._event_bus:on(Events.LOOT_STARTED, function(data)
        self:_log(LEVEL_INFO, string.format("loot started: %s",
            tostring(data and data.target_name or "unknown")), Events.LOOT_STARTED)
    end, { owner = self })

    self._event_bus:on(Events.LOOT_COMPLETED, function(data)
        self:_log(LEVEL_INFO, string.format("loot completed: %s",
            tostring(data and data.target_name or "unknown")), Events.LOOT_COMPLETED)
    end, { owner = self })

    self._event_bus:on(Events.LOOT_FAILED, function(data)
        self:_log(LEVEL_WARNING, string.format("loot failed: %s err=%s",
            tostring(data and data.target_name or "unknown"),
            tostring(data and data.error_code or "-")), Events.LOOT_FAILED)
    end, { owner = self })

    -- === Vendor (7 events: 2 existing + 5 new) ===
    self._event_bus:on(Events.VENDOR_STARTED, function(data)
        self:_log(LEVEL_INFO, string.format("vendor trip started: %s",
            tostring(data and data.vendor_name or "unknown")), Events.VENDOR_STARTED)
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_SELL_STARTED, function(data)
        self:_log(LEVEL_DEBUG, "vendor sell started", Events.VENDOR_SELL_STARTED)
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_SELL_ITEM, function(data)
        self:_log(LEVEL_DEBUG, string.format("vendor sell item: %s",
            tostring(data and data.item_name or "unknown")), Events.VENDOR_SELL_ITEM)
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_SELL_COMPLETED, function(data)
        self:_log(LEVEL_INFO, string.format("vendor sell completed: sold=%d",
            tonumber(data and data.sold_count) or 0), Events.VENDOR_SELL_COMPLETED)
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_REPAIR_COMPLETED, function(data)
        self:_log(LEVEL_INFO, "vendor repair completed", Events.VENDOR_REPAIR_COMPLETED)
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_COMPLETED, function()
        self:_log(LEVEL_INFO, "vendor completed", Events.VENDOR_COMPLETED)
    end, { owner = self })

    self._event_bus:on(Events.VENDOR_FAILED, function(data)
        self:_log(LEVEL_WARNING, "vendor failed: " .. tostring(data.error_code or "unknown"), Events.VENDOR_FAILED)
    end, { owner = self })

    -- === Inventory (1 new) ===
    self._event_bus:on(Events.INVENTORY_THRESHOLD_REACHED, function(data)
        self:_log(LEVEL_DEBUG, string.format("inventory threshold: free=%d",
            tonumber(data and data.free_slots) or 0), Events.INVENTORY_THRESHOLD_REACHED)
    end, { owner = self })

    -- === Recovery (existing 3) ===
    self._event_bus:on(Events.RECOVERY_STARTED, function(data)
        self:_log(LEVEL_WARNING, "recovery started: " .. tostring(data and data.error_code or "unknown"), Events.RECOVERY_STARTED)
    end, { owner = self })

    self._event_bus:on(Events.RECOVERY_ESCALATED, function(data)
        self:_log(LEVEL_WARNING, "recovery escalation: " .. tostring(data and data.stage or "unknown"), Events.RECOVERY_ESCALATED)
    end, { owner = self })

    self._event_bus:on(Events.RECOVERY_COMPLETED, function()
        self:_log(LEVEL_INFO, "recovery completed", Events.RECOVERY_COMPLETED)
    end, { owner = self })

    -- === Death recovery (5 new) ===
    self._event_bus:on(Events.DEATH_RECOVERY_STARTED, function(data)
        self:_log(LEVEL_INFO, "death recovery started", Events.DEATH_RECOVERY_STARTED)
    end, { owner = self })

    self._event_bus:on(Events.DEATH_SPIRIT_RELEASED, function()
        self:_log(LEVEL_DEBUG, "spirit released", Events.DEATH_SPIRIT_RELEASED)
    end, { owner = self })

    self._event_bus:on(Events.DEATH_CORPSE_RUN_UPDATE, function(data)
        self:_log(LEVEL_DEBUG, string.format("corpse run: dist=%.1f",
            tonumber(data and data.distance) or 0), Events.DEATH_CORPSE_RUN_UPDATE)
    end, { owner = self })

    self._event_bus:on(Events.DEATH_RESURRECT_ATTEMPT, function()
        self:_log(LEVEL_DEBUG, "resurrect attempt", Events.DEATH_RESURRECT_ATTEMPT)
    end, { owner = self })

    self._event_bus:on(Events.DEATH_RESURRECTED, function()
        self:_log(LEVEL_INFO, "resurrected", Events.DEATH_RESURRECTED)
    end, { owner = self })

    -- === Telemetry (1 new) ===
    self._event_bus:on(Events.TELEMETRY_FLUSHED, function(data)
        self:_log(LEVEL_DEBUG, string.format("telemetry flushed: events=%d",
            tonumber(data and data.count) or 0), Events.TELEMETRY_FLUSHED)
    end, { owner = self })

    -- === Dependency health (1 new) ===
    self._event_bus:on(Events.DEPENDENCY_HEALTH, function(data)
        self:_log(LEVEL_DEBUG, string.format("dependency health: nav=%s world=%s",
            tostring(data and data.nav_ok or "?"),
            tostring(data and data.world_ok or "?")), Events.DEPENDENCY_HEALTH)
    end, { owner = self })
end

function ConsoleLogger:set_enabled(enabled)
    self._enabled = enabled == true
end

---@param limit? number
---@return table[]
function ConsoleLogger:get_history(limit)
    if self._Logger and self._Logger.get_history then
        return self._Logger.get_history(limit)
    end
    return {}
end

function ConsoleLogger:clear_history()
    if self._Logger and self._Logger.clear_history then
        self._Logger.clear_history()
    end
end

function ConsoleLogger:destroy()
    self._event_bus:off_owner(self)
end

return ConsoleLogger
