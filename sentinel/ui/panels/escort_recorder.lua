-- sentinel/ui/panels/escort_recorder.lua
-- Escort Quest Recorder (F15) for the Graph panel.
--
-- Standalone module that captures player positions during escort quests and generates
-- waypoint + Wait nodes from the recorded timeline. Driven by the GraphState bindings;
-- this module has no UI state — it feeds into GraphState's escort_timeline.

local EscortRecorder = {}
EscortRecorder.__index = EscortRecorder

-- ============================================================================
-- Construction
-- ============================================================================

function EscortRecorder.new(opts)
    opts = opts or {}
    return setmetatable({
        recording = false,
        start_time = nil,
        timeline = {},       -- { time, position, event_type }[]
        samples = 0,
        _last_position = nil,
        _sample_interval = opts.sample_interval or 1.0,  -- sample every second
        _last_sample_time = nil,
    }, EscortRecorder)
end

-- ============================================================================
-- Recording lifecycle
-- ============================================================================

---Start a new escort recording session.
function EscortRecorder:start()
    self.recording = true
    self.start_time = os.clock()
    self.timeline = {}
    self.samples = 0
    self._last_position = nil
    self._last_sample_time = nil  -- nil so the first tick always records
    return true
end

---Stop recording and return the recorded timeline.
---@return table timeline { time, position, event_type }[]
function EscortRecorder:stop()
    self.recording = false
    local result = self.timeline
    self.timeline = {}
    self.samples = 0
    self._last_position = nil
    self._last_sample_time = nil
    self.start_time = nil
    return result
end

---Tick the recorder: capture position if recording and enough time has passed.
---@param ctx table|nil { player_position }
function EscortRecorder:tick(ctx)
    if not self.recording then return end
    if not ctx or not ctx.player_position then return end

    local pos = ctx.player_position
    local now = os.clock()
    local elapsed = now - (self.start_time or now)

    -- Sample at the configured interval
    if self._last_sample_time and (now - self._last_sample_time) < self._sample_interval then
        return
    end
    self._last_sample_time = now

    local entry = {
        time = elapsed,
        position = { x = pos.x, y = pos.y, z = pos.z },
        event_type = "position",
    }
    table.insert(self.timeline, entry)
    self.samples = self.samples + 1
    self._last_position = pos
end

---Generate waypoint + Wait nodes from the recorded timeline.
---Returns an array of node descriptors suitable for GraphState.
---@return table generated { { type, intent }[] }
function EscortRecorder:generate_nodes()
    local generated = {}
    local entry_count = #self.timeline

    for i, entry in ipairs(self.timeline) do
        if entry.position then
            table.insert(generated, {
                type = "questing.Travel",
                intent = {
                    x = entry.position.x,
                    y = entry.position.y,
                    z = entry.position.z,
                    destination = string.format("WP_%d", i),
                    tolerance = 5,
                    allow_flight = false,
                    wait_time = 0,
                },
            })
        end
        -- Insert a Wait node every 5 entries as pacing waypoints
        if i % 5 == 0 and i < entry_count then
            table.insert(generated, {
                type = "questing.Wait",
                intent = { duration = 2 },
            })
        end
    end

    return generated
end

---Get the current recording state.
---@return table { recording, samples, elapsed }
function EscortRecorder:status()
    local elapsed = 0
    if self.recording and self.start_time then
        elapsed = os.clock() - self.start_time
    end
    return {
        recording = self.recording,
        samples = self.samples,
        elapsed = elapsed,
    }
end

return EscortRecorder
