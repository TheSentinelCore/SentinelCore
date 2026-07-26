-- kernel/plugin_registry.lua
-- The plugin lifecycle state machine, and the load-time diagnostic report.
--
-- ADR 08 §8.3:
--
--   DISCOVERED -> VALIDATED -> LOADED -> ELIGIBLE -> ACTIVE <-> SUSPENDED -> UNLOADED
--                      |                    |
--                      +-> REJECTED         +-> QUARANTINED (3 faults)
--
-- ================================================================================
-- WHY ELIGIBLE IS SEPARATE FROM ACTIVE
-- ================================================================================
-- §8.3: "`ELIGIBLE` is separate from `ACTIVE` because `applies_to` is evaluated against LIVE STATE
-- -- a Mage rotation is eligible but inactive until you are actually on the Mage."
--
-- ELIGIBILITY IS NOT RE-EVALUATED EVERY TICK. `applies_to` reads class, spec and level, which are
-- cold-tier (§7: "bags, quest log, talents, reputation, gear -- on demand, cached, POLL-ONLY").
-- ADR §13 risk 6 is the cautionary tale from the other direction: RXPGuides caches gate results in
-- a table that is never invalidated and reads playerLevel INSIDE the cached computation, so
-- level-conditional content freezes at whatever level the player first had.
--
-- SO: BOTH A THROTTLE AND A SIGNAL, and here is why neither alone is enough.
--   * Throttle alone (re-check every N ticks) leaves a rotation ineligible for up to N ticks after
--     a level-up -- with no measured cadence (§13 q7) we cannot even say how long that is.
--   * Signal alone is unsound because §7 records that there ARE no quest events and cold state is
--     poll-only; there is no dependable "your level changed" callback to hang it on.
-- The throttle is the floor that guarantees eventual correctness; `invalidate_eligibility()` is the
-- fast path a caller uses when it has reason to believe live state moved.
--
-- ================================================================================
-- STRANGLER FIG
-- ================================================================================
-- This lives ALONGSIDE runtime/module_registry.lua, which still drives combat and questing. Both
-- paths work. Phase 4 migrates the first real consumer; nothing is deleted before then, because
-- deleting the working path while this one has no consumer would leave nothing running.

local Manifest = require("kernel/manifest")
local Capabilities = require("kernel/capabilities")
local FaultTracker = require("kernel/fault_tracker")
local Status = require("kernel/status")

local PluginRegistry = {}
PluginRegistry.__index = PluginRegistry

PluginRegistry.STATES = {
    DISCOVERED = "DISCOVERED",
    VALIDATED = "VALIDATED",
    REJECTED = "REJECTED",
    LOADED = "LOADED",
    ELIGIBLE = "ELIGIBLE",
    ACTIVE = "ACTIVE",
    SUSPENDED = "SUSPENDED",
    QUARANTINED = "QUARANTINED",
    UNLOADED = "UNLOADED",
}
local S = PluginRegistry.STATES

--- Re-check `applies_to` at most this often. 60 ticks is roughly a second at any plausible cadence
--- and cheap against a cold-tier read.
PluginRegistry.DEFAULT_ELIGIBILITY_INTERVAL_TICKS = 60

---@param opts table { api_version, kernel_provides, event_bus, config, eligibility_interval_ticks }
function PluginRegistry:new(opts)
    opts = opts or {}
    local o = setmetatable({}, PluginRegistry)
    o._api_version = opts.api_version or "1.0.0"
    o._kernel_provides = opts.kernel_provides or {}
    o._event_bus = opts.event_bus
    o._config = opts.config
    o._eligibility_interval = opts.eligibility_interval_ticks
        or PluginRegistry.DEFAULT_ELIGIBILITY_INTERVAL_TICKS

    o._entries = {}          -- id -> { manifest, state, reason, priority, tree }
    o._discovery_order = {}
    o._order = {}            -- resolved load order
    o._faults = FaultTracker:new()
    o._last_eligibility_tick = nil
    o._eligibility_dirty = true
    o._resolved = false
    return o
end

function PluginRegistry:_publish(event, payload)
    if not self._event_bus then return end
    pcall(function() self._event_bus:publish(event, payload) end)
end

function PluginRegistry:_set_state(id, state, reason)
    local entry = self._entries[id]
    if not entry then return end
    entry.state = state
    entry.reason = reason
    self:_publish("plugin:state_changed", { id = id, state = state, reason = reason })
end

-- ---------------------------------------------------------------------------
-- DISCOVERED -> VALIDATED | REJECTED
-- ---------------------------------------------------------------------------

---Offer a manifest to the kernel.
---@return boolean accepted, string|nil reason
function PluginRegistry:discover(manifest)
    local id = type(manifest) == "table" and manifest.id or nil

    if type(id) ~= "string" or id == "" then
        -- Nowhere to file it, so it cannot even be REJECTED by id.
        return false, "missing_field:id"
    end
    if self._entries[id] then
        return false, "duplicate_id"
    end

    self._entries[id] = { manifest = manifest, state = S.DISCOVERED }
    self._discovery_order[#self._discovery_order + 1] = id

    local ok, reason = Manifest.validate(manifest, { api_version = self._api_version })
    if not ok then
        self:_set_state(id, S.REJECTED, reason)
        return false, reason
    end

    self._entries[id].priority = Manifest.resolved_priority(manifest)
    self:_set_state(id, S.VALIDATED)

    -- A late arrival invalidates the previous resolution: its capabilities may satisfy something
    -- that was rejected, and its conflicts may unseat something that loaded.
    self._resolved = false

    if self._config and manifest.config then
        self._config:declare(id, manifest.config)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- VALIDATED -> LOADED | REJECTED
-- ---------------------------------------------------------------------------

---Resolve capabilities over every VALIDATED manifest and establish the load order.
---@return table result the Capabilities.resolve result
function PluginRegistry:resolve()
    local validated = {}
    for _, id in ipairs(self._discovery_order) do
        local entry = self._entries[id]
        if entry and (entry.state == S.VALIDATED or entry.state == S.LOADED
            or entry.state == S.ELIGIBLE or entry.state == S.ACTIVE) then
            validated[#validated + 1] = entry.manifest
        end
    end

    local result = Capabilities.resolve(validated, { kernel_provides = self._kernel_provides })

    for _, rejection in ipairs(result.rejected) do
        local entry = self._entries[rejection.id]
        if entry then
            -- The reason carries the detail, because "requires_unmet" without the capability name
            -- is the anonymous refusal ADR §12 warns about.
            self:_set_state(rejection.id, S.REJECTED,
                rejection.reason .. ":" .. tostring(rejection.detail))
        end
    end

    for _, id in ipairs(result.order) do
        local entry = self._entries[id]
        if entry and entry.state == S.VALIDATED then
            self:_set_state(id, S.LOADED)
        end
    end

    self._order = result.order
    self._resolution = result
    self._resolved = true
    self._eligibility_dirty = true
    return result
end

-- ---------------------------------------------------------------------------
-- LOADED <-> ELIGIBLE  (applies_to, against live state)
-- ---------------------------------------------------------------------------

---Does `applies_to` match the snapshot? Absent means "always".
local function applies(manifest, snapshot)
    local rules = manifest.applies_to
    if rules == nil then return true end
    if snapshot == nil then return false, "no_snapshot" end

    if rules.class ~= nil and snapshot:get("player.class") ~= rules.class then
        return false, "class"
    end
    if rules.spec ~= nil and snapshot:get("player.spec") ~= rules.spec then
        return false, "spec"
    end
    local level = snapshot:get("player.level")
    if rules.min_level ~= nil then
        if type(level) ~= "number" then return false, "level_unavailable" end
        if level < rules.min_level then return false, "min_level" end
    end
    if rules.max_level ~= nil then
        if type(level) ~= "number" then return false, "level_unavailable" end
        if level > rules.max_level then return false, "max_level" end
    end
    return true
end

---Mark eligibility as stale, so the next `refresh_eligibility` re-reads regardless of the throttle.
---This is the fast path for a caller that knows live state moved (a level-up, a spec change).
function PluginRegistry:invalidate_eligibility()
    self._eligibility_dirty = true
end

---Re-evaluate `applies_to`, subject to the throttle. See the header for why both exist.
---@param snapshot table the tick's frozen snapshot
---@param tick_index number
---@return boolean evaluated whether this call actually did the work
function PluginRegistry:refresh_eligibility(snapshot, tick_index)
    local due = self._eligibility_dirty
        or self._last_eligibility_tick == nil
        or (tick_index - self._last_eligibility_tick) >= self._eligibility_interval
    if not due then
        return false
    end
    self._last_eligibility_tick = tick_index
    self._eligibility_dirty = false

    for _, id in ipairs(self._order) do
        local entry = self._entries[id]
        if entry then
            local eligible, why = applies(entry.manifest, snapshot)
            if entry.state == S.LOADED and eligible then
                self:_set_state(id, S.ELIGIBLE)
            elseif entry.state == S.ELIGIBLE and not eligible then
                self:_set_state(id, S.LOADED, "applies_to:" .. tostring(why))
            elseif entry.state == S.ACTIVE and not eligible then
                -- Live state moved out from under an active plugin.
                self:_set_state(id, S.LOADED, "applies_to:" .. tostring(why))
            elseif entry.state == S.LOADED and not eligible then
                -- Already LOADED and still ineligible: no state CHANGE, but the reason must still
                -- be recorded. Without this, a plugin that never becomes eligible shows a blank
                -- reason in the diagnostic report -- the anonymous refusal ADR §12 warns about,
                -- reached by a different route. Set directly rather than through _set_state so a
                -- steady state does not publish a state-changed event every throttle interval.
                entry.reason = "applies_to:" .. tostring(why)
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- ELIGIBLE -> ACTIVE, and the preflight veto
-- ---------------------------------------------------------------------------

---Activate an eligible plugin. `preflight` may veto (§8.2).
---@return boolean activated, string|nil reason
function PluginRegistry:activate(id, ctx)
    local entry = self._entries[id]
    if not entry then return false, "unknown_plugin" end
    if self._faults:is_quarantined(id) then return false, "quarantined" end
    if entry.state == S.ACTIVE then return true end
    if entry.state ~= S.ELIGIBLE and entry.state ~= S.SUSPENDED then
        return false, "not_eligible:" .. entry.state
    end

    local manifest = entry.manifest
    if type(manifest.preflight) == "function" then
        local ok, verdict, why = pcall(manifest.preflight, ctx)
        if not ok then
            -- A preflight that throws is a veto, not a pass: it was asked whether it can run and
            -- it failed to answer.
            self:_set_state(id, S.ELIGIBLE, "preflight_error:" .. tostring(verdict))
            return false, "preflight_error"
        end
        if verdict == false then
            self:_set_state(id, S.ELIGIBLE, "preflight_vetoed:" .. tostring(why or "unspecified"))
            return false, "preflight_vetoed"
        end
    end

    -- `build` is the declarative path (§8.2, preferred). Its tree is kept for the host to drive.
    if type(manifest.build) == "function" then
        local ok, tree = pcall(manifest.build, ctx)
        if not ok then
            self:_set_state(id, S.ELIGIBLE, "build_error:" .. tostring(tree))
            return false, "build_error"
        end
        entry.tree = tree
    end

    self:_set_state(id, S.ACTIVE)
    return true
end

function PluginRegistry:suspend(id, reason)
    local entry = self._entries[id]
    if not entry or entry.state ~= S.ACTIVE then return false end
    self:_set_state(id, S.SUSPENDED, reason)
    return true
end

function PluginRegistry:unload(id, reason)
    local entry = self._entries[id]
    if not entry then return false end
    self:_set_state(id, S.UNLOADED, reason)
    return true
end

-- ---------------------------------------------------------------------------
-- Ticking, and the return-value rule (ADR 08 §8.3)
-- ---------------------------------------------------------------------------

---Tick one ACTIVE plugin.
---
---"Every entry point returns a status to the host" (§2.10/§8.3), and "a `tick` returning `nil` is a
---MANIFEST VALIDATION ERROR, NOT A DEFAULT". A nil return is therefore a fault -- treating it as
---DONE would recreate LazyBot's void tier, where the scheduler learns nothing from having run the
---plugin.
---@return string|nil status, string|nil reason
function PluginRegistry:tick(id, ctx)
    local entry = self._entries[id]
    if not entry then return nil, "unknown_plugin" end
    -- Quarantine is checked BEFORE the state check. A quarantined plugin is also not ACTIVE, so
    -- the reverse order reports `not_active:QUARANTINED` -- true but useless, since it describes
    -- the symptom rather than the cause the operator needs to act on.
    if self._faults:is_quarantined(id) then return nil, "quarantined" end
    if entry.state ~= S.ACTIVE then return nil, "not_active:" .. entry.state end

    local manifest = entry.manifest
    if type(manifest.tick) ~= "function" then
        -- A declarative plugin has no tick; the host drives its tree instead.
        return nil, "no_tick"
    end

    local ok, raw, raw_reason = pcall(manifest.tick, ctx)
    if not ok then
        return nil, self:_record_fault(id, raw)
    end

    local status, reason = Status.normalize(raw, raw_reason)
    if status == nil then
        -- The nil / invalid return is itself the fault.
        return nil, self:_record_fault(id, reason)
    end

    self._faults:success(id)
    entry.last_status = status
    entry.last_reason = reason
    return status, reason
end

function PluginRegistry:_record_fault(id, err)
    local quarantined_now, streak = self._faults:fault(id, err)
    self:_publish("plugin:fault", { id = id, error = tostring(err), count = streak })
    if quarantined_now then
        self:_set_state(id, S.QUARANTINED, "faults:" .. streak .. ":" .. tostring(err))
        self:_publish("plugin:quarantined", { id = id, faults = streak, error = tostring(err) })
    end
    return tostring(err)
end

-- ---------------------------------------------------------------------------
-- Queries + the load-time diagnostic report
-- ---------------------------------------------------------------------------

function PluginRegistry:state(id)
    local entry = self._entries[id]
    return entry and entry.state or nil
end

function PluginRegistry:reason(id)
    local entry = self._entries[id]
    return entry and entry.reason or nil
end

function PluginRegistry:order()
    local out = {}
    for i, id in ipairs(self._order) do out[i] = id end
    return out
end

function PluginRegistry:manifest(id)
    local entry = self._entries[id]
    return entry and entry.manifest or nil
end

---The tree `activate` built via the manifest's declarative `build` (§8.2), or nil.
function PluginRegistry:tree(id)
    local entry = self._entries[id]
    return entry and entry.tree or nil
end

---Whether capability resolution is current. `discover` clears this on every late arrival, so a
---caller that drains a pending queue can re-resolve exactly when something actually landed.
function PluginRegistry:is_resolved()
    return self._resolved == true
end

function PluginRegistry:ids_in_state(state)
    local out = {}
    for _, id in ipairs(self._discovery_order) do
        if self._entries[id].state == state then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

---One structured report listing every plugin and WHY it is in its current state.
---
---ADR §12 requires this in Phase 3: "Add to Phase 3, not later: a manifest validator and a
---LOAD-TIME DIAGNOSTIC REPORT. RXPGuides ships without one -- an unresolved `#completewith foo`
---silently never fires."
---@return table { api_version, counts, plugins = {…}, providers, order }
function PluginRegistry:report()
    local report = {
        api_version = self._api_version,
        resolved = self._resolved,
        order = self:order(),
        counts = {},
        plugins = {},
        providers = self._resolution and self._resolution.providers or {},
        kernel_provides = {},
    }
    for capability in pairs(self._kernel_provides) do
        report.kernel_provides[#report.kernel_provides + 1] = capability
    end
    table.sort(report.kernel_provides)

    for _, id in ipairs(self._discovery_order) do
        local entry = self._entries[id]
        local fault = self._faults:record(id)
        report.plugins[#report.plugins + 1] = {
            id = id,
            kind = entry.manifest and entry.manifest.kind or nil,
            version = entry.manifest and entry.manifest.version or nil,
            api = entry.manifest and entry.manifest.api or nil,
            state = entry.state,
            reason = entry.reason,
            priority = entry.priority,
            last_status = entry.last_status,
            last_reason = entry.last_reason,
            faults = fault and fault.count or 0,
            last_error = fault and fault.last_error or nil,
            quarantined = self._faults:is_quarantined(id),
        }
        report.counts[entry.state] = (report.counts[entry.state] or 0) + 1
    end
    -- Sorted so two runs over the same set produce byte-identical reports.
    table.sort(report.plugins, function(a, b) return a.id < b.id end)
    return report
end

---Human-readable form, for the log at load time.
function PluginRegistry:report_lines()
    local report = self:report()
    local lines = { ("[Sentinel] plugin report -- API %s, %d plugin(s)")
        :format(report.api_version, #report.plugins) }
    for _, p in ipairs(report.plugins) do
        lines[#lines + 1] = ("  %-40s %-11s %s"):format(
            p.id, p.state, p.reason and ("(" .. p.reason .. ")") or "")
    end
    return lines
end

return PluginRegistry
