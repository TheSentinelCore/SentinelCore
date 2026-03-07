local Catalog = require("modules/battleground/data/bg_catalog")
local Events = require("modules/battleground/events")

local QueueManager = {}
QueueManager.__index = QueueManager

local KNOWN_STATUS = {
    none = true,
    queued = true,
    confirm = true,
    active = true,
}

local function num(value)
    return tonumber(value) or 0
end

local function safe_set(blackboard, key, value)
    blackboard:set(key, value)
end

local function is_trueish(value)
    if value == true or value == 1 then
        return true
    end
    local lowered = tostring(value or ""):lower()
    return lowered == "true" or lowered == "1"
end

local function normalize_status(raw)
    if type(raw) == "table" then
        raw = raw.status or raw.state or raw[1] or ""
    end
    local lowered = tostring(raw or ""):lower()
    if KNOWN_STATUS[lowered] then
        return lowered
    end
    return "unknown"
end

local function has_pending_or_confirm_slot(slots)
    for index = 1, 3 do
        local status = slots[index]
        if status == "queued" or status == "confirm" then
            return true
        end
    end
    return false
end

local function first_confirm_slot(slots)
    for index = 1, 3 do
        if slots[index] == "confirm" then
            return index
        end
    end
    return nil
end

function QueueManager:new(event_bus, blackboard)
    local o = setmetatable({}, QueueManager)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._izi = nil
    o._izi_resolved = false
    o._random = math.random
    o:_reset_internal()
    o:_publish_snapshot()
    return o
end

function QueueManager:_reset_internal()
    self._last_join_at_ms = 0
    self._last_join_ok = nil
    self._last_join_bg_id = nil
    self._last_join_at_recorded_ms = 0
    self._join_dispatched = false
    self._join_confirmed = nil
    self._join_confirm_deadline_ms = 0

    self._accept_scheduled = false
    self._accept_deadline_ms = 0
    self._next_retry_at_ms = 0
    self._accept_idx = nil
    self._accept_kind = "pvp"
    self._accept_attempts = 0
    self._last_attempt_ok = nil
    self._last_skip_reason = ""

    self._accept_dispatched = false
    self._accept_confirmed = false
    self._accept_confirm_reason = ""
    self._accept_dispatch_at_ms = 0
    self._accept_confirm_deadline_ms = 0
    self._accept_method = ""
    self._accept_method_attempted = ""
    self._accept_method_last_confirmed = ""
    self._accept_unconfirmed_count = 0
    self._accept_method_cursor = 1
    self._accept_signal = ""

    self._last_popup_seq = 0
    self._active_signal_seq = 0
    self._status_confirm_seq = 0
    self._last_status_confirm = false
    self._active_without_bg_since_ms = 0
    self._last_skip_emit_key = ""
    self._last_infer_emit_key = ""
    self._last_infer_emit_seq = 0
    self._stale_active_emitted = false

    self._status_summary = "unknown|unknown|unknown"
    self._status_slots = { "unknown", "unknown", "unknown" }
end

function QueueManager:initialize()
    self:reset("initialize")
end

function QueueManager:reset(_reason)
    self:_reset_internal()
    self:_publish_snapshot()
end

function QueueManager:_now_ms()
    return num(self._blackboard:get("system.now_ms", 0))
end

function QueueManager:_resolve_izi()
    if not self._izi_resolved then
        local ok, mod = pcall(require, "common/izi_sdk")
        if ok then
            self._izi = mod
        end
        self._izi_resolved = true
    end
    return self._izi
end

function QueueManager:_random_between(min_value, max_value)
    local min_n = tonumber(min_value) or 0
    local max_n = tonumber(max_value) or 0
    if min_n > max_n then
        min_n, max_n = max_n, min_n
    end
    if math.abs(max_n - min_n) < 0.0001 then
        return min_n
    end
    local rng = self._random or math.random
    local ok, unit = pcall(rng)
    if not ok or type(unit) ~= "number" then
        unit = 0.5
    end
    if unit < 0 then unit = 0 end
    if unit > 1 then unit = 1 end
    return min_n + ((max_n - min_n) * unit)
end

function QueueManager:_emit(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

function QueueManager:_emit_skip(reason, payload)
    local key = tostring(reason or "unknown")
    if payload and payload.kind then
        key = key .. "|" .. tostring(payload.kind)
    end
    if payload and payload.status_summary then
        key = key .. "|" .. tostring(payload.status_summary)
    end
    if key == self._last_skip_emit_key then
        return
    end
    self._last_skip_emit_key = key
    self._last_skip_reason = tostring(reason or "unknown")
    local out = payload or {}
    out.reason = self._last_skip_reason
    self:_emit(Events.QUEUE_ACCEPT_SKIPPED, out)
end

function QueueManager:_read_settings()
    return {
        enabled = self._blackboard:get("module.bg.enabled", true) == true,
        auto_queue = self._blackboard:get("module.bg.auto_queue", false) == true,
        queue_selection = tostring(self._blackboard:get("module.bg.queue_selection", "AV") or "AV"),
        join_interval_ms = math.floor((tonumber(self._blackboard:get("module.bg.queue_join_interval_s", 12)) or 12) * 1000),
        accept_delay_min_ms = math.floor((tonumber(self._blackboard:get("module.bg.queue_accept_delay_min_s", 0.6)) or 0.6) * 1000),
        accept_delay_max_ms = math.floor((tonumber(self._blackboard:get("module.bg.queue_accept_delay_max_s", 1.8)) or 1.8) * 1000),
        accept_retry_interval_ms = math.floor((tonumber(self._blackboard:get("module.bg.queue_accept_retry_interval_s", 0.35)) or 0.35) * 1000),
        accept_max_attempts = math.max(1, math.floor(tonumber(self._blackboard:get("module.bg.queue_accept_max_attempts", 20)) or 20)),
        accept_confirm_timeout_ms = math.floor((tonumber(self._blackboard:get("module.bg.queue_accept_confirm_timeout_s", 2.5)) or 2.5) * 1000),
        join_confirm_timeout_ms = math.floor((tonumber(self._blackboard:get("module.bg.queue_join_confirm_timeout_s", 5.0)) or 5.0) * 1000),
        active_without_bg_timeout_ms = math.floor((tonumber(self._blackboard:get("module.bg.queue_active_without_bg_timeout_s", 10.0)) or 10.0) * 1000),
        accept_mode = tostring(self._blackboard:get("module.bg.queue_accept_mode", "strict_pvp") or "strict_pvp"),
        dependencies_policy = tostring(self._blackboard:get("module.bg.queue_dependencies_policy", "accept_anyway") or "accept_anyway"),
    }
end

function QueueManager:_read_sensor()
    local slots = self._blackboard:get("bg.sensor.queue_status_slots", {})
    local normalized = {}
    local any_queued = false
    local any_confirm = false
    local any_active = false
    for index = 1, 3 do
        local status = normalize_status(slots[index])
        normalized[index] = status
        if status == "queued" or status == "confirm" or status == "active" then
            any_queued = true
        end
        if status == "confirm" then
            any_confirm = true
        end
        if status == "active" then
            any_active = true
        end
    end
    return {
        in_bg = self._blackboard:get("bg.sensor.in_bg", false) == true,
        popup = self._blackboard:get("bg.sensor.queue_popup", false) == true,
        popup_kind = tostring(self._blackboard:get("bg.sensor.queue_popup_kind", "unknown") or "unknown"),
        popup_source = tostring(self._blackboard:get("bg.sensor.queue_popup_source", "none") or "none"),
        popup_confidence = tostring(self._blackboard:get("bg.sensor.queue_popup_confidence", "none") or "none"),
        popup_seq = num(self._blackboard:get("bg.sensor.queue_popup_seq", 0)),
        popup_age_ms = num(self._blackboard:get("bg.sensor.queue_popup_age_ms", 0)),
        popup_slot_idx = self._blackboard:get("bg.sensor.queue_popup_slot_idx"),
        status_slots = normalized,
        status_summary = tostring(self._blackboard:get("bg.sensor.queue_status_summary", table.concat(normalized, "|")) or table.concat(normalized, "|")),
        any_queued = any_queued,
        any_confirm = any_confirm,
        any_active = any_active,
    }
end

function QueueManager:_publish_snapshot()
    local next_attempt_at_ms = 0
    if self._accept_dispatched then
        next_attempt_at_ms = self._accept_confirm_deadline_ms
    elseif self._accept_scheduled then
        next_attempt_at_ms = math.max(self._accept_deadline_ms, self._next_retry_at_ms)
    end
    safe_set(self._blackboard, "bg.queue.scheduled", self._accept_scheduled)
    safe_set(self._blackboard, "bg.queue.next_attempt_at_ms", next_attempt_at_ms)
    safe_set(self._blackboard, "bg.queue.attempt_count", self._accept_attempts)
    safe_set(self._blackboard, "bg.queue.last_attempt_ok", self._last_attempt_ok)
    safe_set(self._blackboard, "bg.queue.skip_reason", self._last_skip_reason)
    safe_set(self._blackboard, "bg.queue.accept_dispatched", self._accept_dispatched)
    safe_set(self._blackboard, "bg.queue.accept_confirmed", self._accept_confirmed)
    safe_set(self._blackboard, "bg.queue.accept_confirm_reason", self._accept_confirm_reason)
    safe_set(self._blackboard, "bg.queue.accept_method", self._accept_method)
    safe_set(self._blackboard, "bg.queue.accept_method_attempted", self._accept_method_attempted)
    safe_set(self._blackboard, "bg.queue.accept_method_last_confirmed", self._accept_method_last_confirmed)
    safe_set(self._blackboard, "bg.queue.accept_unconfirmed_count", self._accept_unconfirmed_count)
    safe_set(self._blackboard, "bg.queue.accept_dispatch_at_ms", self._accept_dispatch_at_ms)
    safe_set(self._blackboard, "bg.queue.last_join_ok", self._last_join_ok)
    safe_set(self._blackboard, "bg.queue.last_join_bg_id", self._last_join_bg_id)
    safe_set(self._blackboard, "bg.queue.last_join_at_ms", self._last_join_at_recorded_ms)
    safe_set(self._blackboard, "bg.queue.join_dispatched", self._join_dispatched)
    safe_set(self._blackboard, "bg.queue.join_confirmed", self._join_confirmed)
    safe_set(self._blackboard, "bg.queue.status_summary", self._status_summary)
    safe_set(self._blackboard, "bg.queue.status_slots", self._status_slots)
end

function QueueManager:_try_join(bg_id)
    local input = core and core.input or nil
    local join_fn = input and input.join_battlefield or nil
    if type(join_fn) ~= "function" then
        return false
    end

    local id = tonumber(bg_id)
    if not id then
        return false
    end

    local attempts = {
        function() return pcall(join_fn, id, 0) end,
        function() return pcall(join_fn, input, id, 0) end,
        function() return pcall(join_fn, id) end,
        function() return pcall(join_fn, input, id) end,
    }

    for _, attempt in ipairs(attempts) do
        local ok, value = attempt()
        if ok and (value == nil or is_trueish(value)) then
            return true
        end
    end
    return false
end

function QueueManager:_dispatch_accept(kind, idx, confirm_slot)
    local izi = self:_resolve_izi()
    local input = core and core.input or nil
    local methods = {}

    local function add_method(name, fn)
        methods[#methods + 1] = { name = name, run = fn }
    end

    local function queue_accept_direct(...)
        if not izi or type(izi.queue_accept) ~= "function" then
            return false
        end
        local ok1, value1 = pcall(izi.queue_accept, ...)
        if ok1 and (value1 == nil or is_trueish(value1)) then
            return true
        end
        local ok2, value2 = pcall(izi.queue_accept, izi, ...)
        if ok2 and (value2 == nil or is_trueish(value2)) then
            return true
        end
        return false
    end

    local function accept_port(index, is_accept)
        if not input or type(input.accept_battlefield_port) ~= "function" then
            return false
        end
        local port_fn = input.accept_battlefield_port
        local ok1, value1 = pcall(port_fn, index, is_accept)
        if ok1 and (value1 == nil or is_trueish(value1)) then
            return true
        end
        local ok2, value2 = pcall(port_fn, input, index, is_accept)
        if ok2 and (value2 == nil or is_trueish(value2)) then
            return true
        end
        return false
    end

    if izi and type(izi.queue_accept) == "function" then
        add_method("izi.queue_accept(kind,idx)", function()
            return queue_accept_direct(kind, idx)
        end)
        add_method("izi.queue_accept(kind)", function()
            return queue_accept_direct(kind)
        end)
        add_method("izi.queue_accept()", function()
            return queue_accept_direct()
        end)
    end

    local slot_candidates = {}
    local seen = {}
    local function push_slot(slot)
        local value = tonumber(slot)
        if value == nil then
            return
        end
        value = math.floor(value)
        local key = tostring(value)
        if seen[key] then
            return
        end
        seen[key] = true
        slot_candidates[#slot_candidates + 1] = value
    end

    push_slot(idx)
    push_slot(confirm_slot)
    push_slot(1)
    push_slot(0)

    for _, slot in ipairs(slot_candidates) do
        add_method(string.format("core.input.accept_battlefield_port(%d,true)", slot), function()
            return accept_port(slot, true)
        end)
    end
    for _, slot in ipairs(slot_candidates) do
        add_method(string.format("core.input.accept_battlefield_port(%d)", slot), function()
            return accept_port(slot, nil)
        end)
    end

    if #methods == 0 then
        self._accept_method_attempted = ""
        return false, nil
    end

    local start_index = num(self._accept_method_cursor)
    if start_index < 1 or start_index > #methods then
        start_index = 1
    end

    for offset = 0, (#methods - 1) do
        local method_index = ((start_index - 1 + offset) % #methods) + 1
        local method = methods[method_index]
        self._accept_method_attempted = method.name
        local ok = false
        if type(method.run) == "function" then
            ok = method.run() == true
        end
        if ok then
            self._accept_method_cursor = (method_index % #methods) + 1
            self._accept_method = method.name
            self:_emit(Events.QUEUE_ACCEPT_DISPATCHED, {
                kind = kind,
                idx = idx,
                method = method.name,
            })
            return true, method.name
        end
    end

    self._accept_method_cursor = (start_index % #methods) + 1
    return false, nil
end

function QueueManager:update()
    local settings = self:_read_settings()
    local sensor = self:_read_sensor()
    self._status_summary = sensor.status_summary
    self._status_slots = sensor.status_slots

    if settings.enabled ~= true then
        self:reset("bg_disabled")
        return self:get_snapshot()
    end

    if settings.auto_queue ~= true then
        self._join_dispatched = false
        self._join_confirmed = nil
        self._accept_scheduled = false
        self._accept_dispatched = false
        self._accept_confirmed = false
        self._accept_confirm_reason = ""
        self._accept_method = ""
        self._accept_method_attempted = ""
        self._accept_deadline_ms = 0
        self._next_retry_at_ms = 0
        self._last_skip_reason = ""
        self:_publish_snapshot()
        return self:get_snapshot()
    end

    local now_ms = self:_now_ms()

    if sensor.any_confirm and not self._last_status_confirm then
        self._status_confirm_seq = self._status_confirm_seq + 1
    end
    self._last_status_confirm = sensor.any_confirm

    local pending_or_confirm = has_pending_or_confirm_slot(sensor.status_slots)

    if (not sensor.in_bg) and sensor.any_active and (not pending_or_confirm) and (not sensor.popup) then
        if self._active_without_bg_since_ms <= 0 then
            self._active_without_bg_since_ms = now_ms
            self._stale_active_emitted = false
        elseif (not self._stale_active_emitted)
            and (now_ms - self._active_without_bg_since_ms) >= math.max(2000, settings.active_without_bg_timeout_ms) then
            self._stale_active_emitted = true
            self:_emit(Events.QUEUE_ACTIVE_STATUS_STALE, {
                status_summary = sensor.status_summary,
                elapsed_s = (now_ms - self._active_without_bg_since_ms) / 1000,
            })
        end
    else
        self._active_without_bg_since_ms = 0
        self._stale_active_emitted = false
    end

    if self._join_dispatched then
        if sensor.popup or sensor.any_queued then
            self._join_dispatched = false
            self._join_confirmed = true
            self:_emit(Events.QUEUE_JOIN_CONFIRMED, {
                bg_key = settings.queue_selection,
                battleground_id = self._last_join_bg_id,
                status_summary = sensor.status_summary,
                popup = sensor.popup,
            })
        elseif self._join_confirm_deadline_ms > 0 and now_ms >= self._join_confirm_deadline_ms then
            self._join_dispatched = false
            self._join_confirmed = false
            self:_emit(Events.QUEUE_JOIN_NOT_CONFIRMED, {
                bg_key = settings.queue_selection,
                battleground_id = self._last_join_bg_id,
                status_summary = sensor.status_summary,
            })
        end
    end

    local accept_confirmed_this_tick = false
    if self._accept_dispatched then
        local confirm_reason = nil
        if sensor.in_bg then
            confirm_reason = "entered_bg"
        elseif self._accept_signal == "status_confirm" then
            if not sensor.any_confirm then
                confirm_reason = "status_not_confirm"
            end
        else
            if not sensor.popup then
                confirm_reason = "popup_cleared"
            elseif not sensor.any_confirm then
                confirm_reason = "status_not_confirm"
            end
        end

        if confirm_reason then
            self._accept_dispatched = false
            self._accept_scheduled = false
            self._accept_confirmed = true
            self._accept_confirm_reason = confirm_reason
            accept_confirmed_this_tick = true
            self._accept_method_last_confirmed = self._accept_method ~= "" and self._accept_method or self._accept_method_last_confirmed
            self._accept_signal = ""
            self._accept_method = ""
            self._accept_deadline_ms = 0
            self._next_retry_at_ms = 0
            self:_emit(Events.QUEUE_ACCEPT_CONFIRMED, {
                reason = confirm_reason,
                status_summary = sensor.status_summary,
                popup = sensor.popup,
            })
        elseif self._accept_confirm_deadline_ms > 0 and now_ms >= self._accept_confirm_deadline_ms then
            self._accept_dispatched = false
            self._accept_method = ""
            self._accept_unconfirmed_count = self._accept_unconfirmed_count + 1
            self:_emit_skip("accept_not_confirmed", {
                kind = self._accept_kind,
                attempts = self._accept_attempts,
                status_summary = sensor.status_summary,
                dependencies_ready = settings.dependencies_policy == "accept_anyway",
            })
            if self._accept_attempts >= settings.accept_max_attempts then
                self._accept_scheduled = false
                self._accept_deadline_ms = 0
            else
                self._accept_scheduled = true
                self._next_retry_at_ms = now_ms + math.max(100, settings.accept_retry_interval_ms)
                self._accept_confirmed = false
                self._accept_confirm_reason = ""
            end
        end
    end

    local has_accept_signal = sensor.popup or sensor.any_confirm
    if has_accept_signal then
        local signal_seq = sensor.popup and sensor.popup_seq or (100000 + self._status_confirm_seq)
        if signal_seq ~= self._active_signal_seq then
            self._active_signal_seq = signal_seq
            self._accept_scheduled = false
            self._accept_dispatched = false
            self._accept_confirmed = false
            self._accept_confirm_reason = ""
            self._accept_method = ""
            self._accept_method_attempted = ""
            self._accept_deadline_ms = 0
            self._next_retry_at_ms = 0
            self._accept_attempts = 0
            self._last_attempt_ok = nil
            self._last_skip_reason = ""
            self._last_skip_emit_key = ""
            self._last_infer_emit_key = ""
            self._last_infer_emit_seq = 0
            self._accept_signal = sensor.popup and "popup" or "status_confirm"
            self._accept_idx = sensor.popup_slot_idx or first_confirm_slot(sensor.status_slots)
            self._last_popup_seq = signal_seq
            self:_emit(Events.QUEUE_POPUP_DETECTED, {
                kind = sensor.popup_kind,
                source = sensor.popup_source,
                confidence = sensor.popup_confidence,
                seq = signal_seq,
                slot_idx = self._accept_idx,
                age_ms = sensor.popup_age_ms,
            })
        end

        local resolved_kind = sensor.popup_kind
        if resolved_kind ~= "pvp" and resolved_kind ~= "pve" then
            if sensor.any_confirm then
                resolved_kind = "pvp"
            else
                local bg_entry = Catalog[settings.queue_selection]
                if bg_entry then
                    resolved_kind = "pvp"
                end
            end
            local infer_key = tostring(signal_seq) .. "|" .. tostring(self._accept_idx or "nil")
            if resolved_kind == "pvp"
                and (self._last_infer_emit_seq ~= signal_seq or self._last_infer_emit_key ~= infer_key) then
                self._last_infer_emit_seq = signal_seq
                self._last_infer_emit_key = infer_key
                self:_emit(Events.QUEUE_KIND_INFERRED, {
                    inferred_kind = "pvp",
                    source_kind = sensor.popup_kind,
                    popup_idx = self._accept_idx,
                })
            end
        end
        self._accept_kind = resolved_kind

        if settings.accept_mode == "strict_pvp" and self._accept_kind ~= "pvp" then
            self._accept_scheduled = false
            self._accept_dispatched = false
            self:_emit_skip(self._accept_kind == "unknown" and "kind_unknown" or "kind_not_pvp", {
                kind = self._accept_kind,
                status_summary = sensor.status_summary,
                dependencies_ready = settings.dependencies_policy == "accept_anyway",
            })
        else
            if (not self._accept_scheduled) and (not self._accept_dispatched) then
                local delay_ms = math.floor(self:_random_between(settings.accept_delay_min_ms, settings.accept_delay_max_ms))
                self._accept_scheduled = true
                self._accept_deadline_ms = now_ms + math.max(0, delay_ms)
                self._next_retry_at_ms = self._accept_deadline_ms
                self._accept_confirmed = false
                self._accept_confirm_reason = ""
            end

            if self._accept_scheduled
                and (not self._accept_dispatched)
                and now_ms >= self._accept_deadline_ms
                and now_ms >= self._next_retry_at_ms then
                if self._accept_attempts < settings.accept_max_attempts then
                    self._accept_attempts = self._accept_attempts + 1
                    self:_emit(Events.QUEUE_ACCEPT_ATTEMPT, {
                        attempt = self._accept_attempts,
                        kind = self._accept_kind,
                        idx = self._accept_idx,
                    })
                    local dispatched = false
                    local method = nil
                    dispatched, method = self:_dispatch_accept(self._accept_kind, self._accept_idx, first_confirm_slot(sensor.status_slots))
                    self._last_attempt_ok = dispatched
                    if dispatched then
                        self._accept_dispatched = true
                        self._accept_dispatch_at_ms = now_ms
                        self._accept_confirm_deadline_ms = now_ms + math.max(500, settings.accept_confirm_timeout_ms)
                        self._next_retry_at_ms = now_ms + math.max(100, settings.accept_retry_interval_ms)
                        self._accept_method = method or self._accept_method
                    else
                        self._next_retry_at_ms = now_ms + math.max(100, settings.accept_retry_interval_ms)
                        if self._accept_attempts >= settings.accept_max_attempts then
                            self._accept_scheduled = false
                            self:_emit_skip("max_attempts", {
                                kind = self._accept_kind,
                                attempts = self._accept_attempts,
                                status_summary = sensor.status_summary,
                                dependencies_ready = settings.dependencies_policy == "accept_anyway",
                            })
                        end
                    end
                end
            end
        end
    else
        self._accept_scheduled = false
        self._accept_dispatched = false
        self._accept_method = ""
        self._accept_method_attempted = ""
        self._accept_deadline_ms = 0
        self._next_retry_at_ms = 0
        self._accept_signal = ""
        self._active_signal_seq = 0
        self._last_popup_seq = 0
        if accept_confirmed_this_tick then
            self._accept_signal = ""
        end
    end

    if sensor.in_bg then
        self._join_dispatched = false
        self._join_confirmed = true
    end

    local currently_queued = sensor.any_queued
    if self._stale_active_emitted then
        currently_queued = pending_or_confirm
    end

    if settings.auto_queue
        and (not sensor.in_bg)
        and (not sensor.popup)
        and (not currently_queued)
        and (not self._join_dispatched)
        and (now_ms - self._last_join_at_ms) >= math.max(1000, settings.join_interval_ms) then
        local bg_entry = Catalog[settings.queue_selection] or Catalog.AV
        local dispatched = self:_try_join(bg_entry and bg_entry.battleground_id or nil)
        self._last_join_at_ms = now_ms
        self._last_join_ok = dispatched
        self._last_join_bg_id = bg_entry and bg_entry.battleground_id or nil
        self._last_join_at_recorded_ms = now_ms
        self:_emit(Events.QUEUE_JOIN_DISPATCHED, {
            bg_key = settings.queue_selection,
            battleground_id = self._last_join_bg_id,
            dispatched = dispatched == true,
        })
        if dispatched then
            self._join_dispatched = true
            self._join_confirmed = nil
            self._join_confirm_deadline_ms = now_ms + math.max(1000, settings.join_confirm_timeout_ms)
        end
    end

    self:_publish_snapshot()
    return self:get_snapshot()
end

function QueueManager:get_snapshot()
    return {
        scheduled = self._accept_scheduled,
        next_attempt_at_ms = self._accept_dispatched and self._accept_confirm_deadline_ms or math.max(self._accept_deadline_ms, self._next_retry_at_ms),
        attempt_count = self._accept_attempts,
        last_attempt_ok = self._last_attempt_ok,
        skip_reason = self._last_skip_reason,
        accept_dispatched = self._accept_dispatched,
        accept_confirmed = self._accept_confirmed,
        accept_confirm_reason = self._accept_confirm_reason,
        accept_method = self._accept_method,
        accept_method_attempted = self._accept_method_attempted,
        accept_method_last_confirmed = self._accept_method_last_confirmed,
        accept_unconfirmed_count = self._accept_unconfirmed_count,
        accept_dispatch_at_ms = self._accept_dispatch_at_ms,
        last_join_ok = self._last_join_ok,
        last_join_bg_id = self._last_join_bg_id,
        last_join_at_ms = self._last_join_at_recorded_ms,
        join_dispatched = self._join_dispatched,
        join_confirmed = self._join_confirmed,
        status_summary = self._status_summary,
        status_slots = self._status_slots,
    }
end

return QueueManager
