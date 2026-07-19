local Events = require("modules/combat/events")

local SpellDispatcher = {}
SpellDispatcher.__index = SpellDispatcher

-- ---------------------------------------------------------------------------
-- Spell queue resolution and method dispatch
-- ---------------------------------------------------------------------------

local _spell_queue_ref = nil
local _spell_queue_resolved = false

local function resolve_spell_queue()
    if spell_queue then
        _spell_queue_ref = spell_queue
        _spell_queue_resolved = true
        return _spell_queue_ref
    end
    if not _spell_queue_resolved then
        local ok, mod = pcall(require, "common/modules/spell_queue")
        if ok and mod then
            _spell_queue_ref = mod
        end
        _spell_queue_resolved = true
    end
    return _spell_queue_ref
end

---Call a spell queue method using method-call convention (queue:method(...)).
---The spell_queue module is external and its calling convention varies.
---We always try method-call first (our canonical convention).
---@param queue table The spell queue instance
---@param method_name string The method name to call
---@param ... any Arguments to pass after the method name
---@return boolean ok Whether the call succeeded (no error thrown)
---@return any result The return value from the method
local function call_queue_method(queue, method_name, ...)
    if not queue or type(queue[method_name]) ~= "function" then
        return false, nil
    end
    return pcall(queue[method_name], queue, ...)
end

-- ---------------------------------------------------------------------------
-- GUID and signature helpers
-- ---------------------------------------------------------------------------

local function same_guid(unit_a, unit_b)
    if not unit_a or not unit_b then
        return false
    end
    if type(unit_a.get_guid) ~= "function" or type(unit_b.get_guid) ~= "function" then
        return false
    end
    local ok_a, guid_a = pcall(unit_a.get_guid, unit_a)
    local ok_b, guid_b = pcall(unit_b.get_guid, unit_b)
    return ok_a and ok_b and tostring(guid_a) == tostring(guid_b)
end

local function target_guid(target)
    if not target or type(target.get_guid) ~= "function" then
        return "nil"
    end
    local ok, guid = pcall(target.get_guid, target)
    if ok and guid ~= nil then
        return tostring(guid)
    end
    return "nil"
end

local function position_signature(position)
    if type(position) ~= "table" then
        return "nil"
    end
    local x = math.floor((tonumber(position.x) or 0) * 10 + 0.5) / 10
    local y = math.floor((tonumber(position.y) or 0) * 10 + 0.5) / 10
    local z = math.floor((tonumber(position.z) or 0) * 10 + 0.5) / 10
    return table.concat({ tostring(x), tostring(y), tostring(z) }, ":")
end

local function snapshot_signature(snapshot, spell_id, queue_priority, target, mode)
    if type(snapshot) ~= "table" then
        return nil
    end
    local count = 0
    local latest_timestamp = 0
    for _, entry in ipairs(snapshot) do
        if tonumber(entry.spell_id) == tonumber(spell_id)
            and tonumber(entry.priority) == tonumber(queue_priority)
        then
            if mode == "position" or target == nil or entry.target == nil or same_guid(entry.target, target) then
                count = count + 1
                local ts = tonumber(entry.timestamp) or 0
                if ts > latest_timestamp then
                    latest_timestamp = ts
                end
            end
        end
    end
    return tostring(count) .. ":" .. tostring(latest_timestamp)
end

local function get_queue_snapshot(queue)
    if not queue or type(queue.get_queue_snapshot) ~= "function" then
        return nil
    end
    local ok, snapshot = pcall(queue.get_queue_snapshot, queue)
    if ok and type(snapshot) == "table" then
        return snapshot
    end
    return nil
end

function SpellDispatcher:new(event_bus, blackboard)
    local o = setmetatable({}, SpellDispatcher)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._last_signature = nil
    o._last_issue_at_ms = 0
    o._dedupe_window_ms = 150
    return o
end

function SpellDispatcher:_set_queue_diag(mode, method, ok, observed)
    self._blackboard:set("rotation.last_queue_call_mode", tostring(mode or ""))
    self._blackboard:set("rotation.last_queue_call_method", tostring(method or ""))
    self._blackboard:set("rotation.last_queue_call_ok", ok == true)
    if observed ~= nil then
        self._blackboard:set("rotation.last_queue_observed", observed == true)
    end
end

function SpellDispatcher:_can_issue(signature, now_ms)
    if signature == self._last_signature and (now_ms - self._last_issue_at_ms) < self._dedupe_window_ms then
        return false
    end
    return true
end

function SpellDispatcher:_commit(signature, action_id, spell_id, queue_mode, queue_priority, now_ms)
    self._last_signature = signature
    self._last_issue_at_ms = now_ms
    self._blackboard:set("rotation.last_action_id", action_id)
    self._blackboard:set("rotation.last_spell_id", spell_id)
    self._blackboard:set("rotation.last_queue_mode", queue_mode)
    self._blackboard:set("rotation.last_queue_priority", queue_priority)
    self._blackboard:set("rotation.last_queue_at_ms", now_ms)
    self._blackboard:set("rotation.last_block_reason", nil)
    self._event_bus:publish(Events.ACTION_QUEUED, {
        action_id = action_id,
        spell_id = spell_id,
        queue_mode = queue_mode,
        queue_priority = queue_priority,
    })
end

function SpellDispatcher:_block(action_id, spell_id, reason)
    self._blackboard:set("rotation.last_block_reason", tostring(reason))
    self._event_bus:publish(Events.ACTION_BLOCKED, {
        action_id = action_id,
        spell_id = spell_id,
        reason = tostring(reason),
    })
end

function SpellDispatcher:queue_target(action_id, spell_id, target, queue_priority, message, opts)
    local now_ms = self._blackboard:get("system.now_ms", 0)
    if not spell_id or not target then
        self:_block(action_id, spell_id, "missing_target_or_spell")
        return false
    end

    opts = opts or {}
    local queue_mode = opts.fast and "target_fast" or "target"
    local target_key = target_guid(target)
    local signature = table.concat({ tostring(action_id), tostring(spell_id), queue_mode, tostring(queue_priority), target_key }, ":")
    if not self:_can_issue(signature, now_ms) then
        return false
    end
    self._blackboard:set("rotation.last_queue_target_guid", target_key)

    self._event_bus:publish(Events.ACTION_SELECTED, {
        action_id = action_id,
        spell_id = spell_id,
        queue_mode = queue_mode,
        queue_priority = queue_priority,
        target_guid = target_key ~= "nil" and target_key or nil,
    })

    local queue = resolve_spell_queue()
    if not queue then
        self:_block(action_id, spell_id, "spell_queue_unavailable")
        return false
    end

    local before_snapshot = nil
    local before_signature = nil
    if not opts.fast then
        before_snapshot = get_queue_snapshot(queue)
        before_signature = snapshot_signature(before_snapshot, spell_id, queue_priority, target, "target")
    end

    -- Dispatch to spell queue using canonical method-call convention.
    -- Only method_with_self is supported (flat calls were dead code).
    local ok, queued = false, nil
    local queue_method = ""
    if opts.fast and type(queue.queue_spell_target_fast) == "function" then
        ok, queued = call_queue_method(queue, "queue_spell_target_fast",
            spell_id, target, queue_priority, message, opts.allow_movement ~= false)
        queue_method = "method_with_self"
    elseif type(queue.queue_spell_target) == "function" then
        ok, queued = call_queue_method(queue, "queue_spell_target",
            spell_id, target, queue_priority, message, opts.allow_movement ~= false)
        queue_method = "method_with_self"
    end

    -- Verify by snapshot comparison (non-fast only)
    local observed = true
    if ok and not opts.fast and before_signature ~= nil then
        local after_snapshot = get_queue_snapshot(queue)
        local after_signature = snapshot_signature(after_snapshot, spell_id, queue_priority, target, "target")
        observed = after_signature ~= before_signature
        self._blackboard:set("rotation.last_queue_snapshot_size", after_snapshot and #after_snapshot or 0)
    end

    self:_set_queue_diag(queue_mode, queue_method, ok, observed)

    if ok and queued ~= false and (opts.fast or before_signature == nil or observed) then
        self:_commit(signature, action_id, spell_id, queue_mode, queue_priority, now_ms)
        return true
    end

    self:_block(action_id, spell_id, observed and (queued and tostring(queued) or "queue_target_failed") or "queue_not_observed_in_snapshot")
    return false
end

function SpellDispatcher:queue_position(action_id, spell_id, position, queue_priority, message)
    local now_ms = self._blackboard:get("system.now_ms", 0)
    if not spell_id or type(position) ~= "table" then
        self:_block(action_id, spell_id, "missing_position_or_spell")
        return false
    end

    local position_key = position_signature(position)
    local signature = table.concat({ tostring(action_id), tostring(spell_id), "position", tostring(queue_priority), position_key }, ":")
    if not self:_can_issue(signature, now_ms) then
        return false
    end
    self._blackboard:set("rotation.last_queue_position_key", position_key)

    local queue = resolve_spell_queue()
    if not queue or type(queue.queue_spell_position) ~= "function" then
        self:_block(action_id, spell_id, "spell_queue_position_unavailable")
        return false
    end

    local ok, queued = call_queue_method(queue, "queue_spell_position",
        spell_id, position, queue_priority, message, true)
    self:_set_queue_diag("position", "method_with_self", ok, nil)
    if ok and queued ~= false then
        self:_commit(signature, action_id, spell_id, "position", queue_priority, now_ms)
        return true
    end

    self:_block(action_id, spell_id, queued and tostring(queued) or "queue_position_failed")
    return false
end

return SpellDispatcher