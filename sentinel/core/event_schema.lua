--- Sentinel runtime event contract (ADR 09 §7.2, ADR 09a §1.5), schema version 1.
---
--- An event is:
---     { schema_version, seq, run_id, node_id, event, timestamp, state, data }
---
--- WHY THIS IS A MODULE AND NOT A TABLE LITERAL AT THE EMIT SITE
--- The questing execution log grew to ~30 emit sites, each handing `_log_event` a free-form
--- payload table that was flattened straight onto the entry. Nothing owned the shape, so a
--- payload key named `seq` or `state` silently overwrote the field of the same name, and the
--- log had no way to say which run or which graph node an entry belonged to. `build` is the
--- single construction point: producers supply a payload, the contract fields are stamped last,
--- and a payload key can no longer shadow one.
---
--- BACKWARD COMPATIBILITY IS A HARD REQUIREMENT, NOT A COURTESY
--- Three consumers already read these entries as FLAT tables: `runner_state.lua` (the cockpit
--- event list reads `e.msg` / `e.action_type` directly), the save file's `execution_history`,
--- and the `questing:log` bus topic. So the payload is kept flattened onto the entry *as well
--- as* nested under `data`. Nesting alone would blank the cockpit and break every save written
--- before this contract existed.
---
--- Pure module: nothing here touches the Sylvannas API at require time, so the contract is
--- constructible offline (tests, tooling) as well as in-game.

local EventSchema = {}

EventSchema.SCHEMA_VERSION = 1

--- Bumped per `new_run_id` call. `core.time()` is coarse and `math.random` is unseeded in the
--- sandbox, so two run ids minted inside one tick can agree on both — uniqueness has to come
--- from somewhere that cannot repeat.
local mint_counter = 0

--- Mint a run identity. Time-ordered prefix so ids sort by mint order, which is what a replay
--- or timeline wants; the tail only has to disambiguate.
function EventSchema.new_run_id()
    mint_counter = mint_counter + 1
    local now = 0
    if core and core.time then
        local ok, t = pcall(core.time)
        if ok and type(t) == "number" then now = t end
    end
    local ms = math.floor(now * 1000) % 0x100000000
    return string.format("%08x-%04x-%04x-%04x",
        ms,
        math.floor(mint_counter / 0x10000) % 0x10000,
        mint_counter % 0x10000,
        math.random(0, 0xFFFF))
end

--- Build a schema-v1 event.
---
--- @param spec table
---   event      string  -- required, the event name (`action_success`, `nav_started`, ...)
---   timestamp  number  -- required, `core.time()` at the emit site
---   state      string? -- executor state at emit time
---   seq        number  -- required, ABSOLUTE event index (survives ring-buffer eviction)
---   run_id     string  -- required, stable for the whole run
---   node_id    string? -- graph node when known, nil for profile-scoped events
---   legacy     table?  -- pre-v1 flat fields (e.g. `operation`) the payload may still override
---   data       table?  -- producer payload
--- @return table entry
function EventSchema.build(spec)
    local entry = {}

    -- Pre-v1 defaults first: several emit sites deliberately pass their own `operation`, and
    -- that override predates this contract.
    if type(spec.legacy) == "table" then
        for k, v in pairs(spec.legacy) do entry[k] = v end
    end

    -- The payload lands twice: flat for the pre-v1 consumers, nested as the v1 `data` field.
    -- The nested copy is a copy, not an alias — emit sites reuse payload tables in loops, and
    -- an aliased entry would let a later tick rewrite an event already in the log.
    local data = {}
    if type(spec.data) == "table" then
        for k, v in pairs(spec.data) do
            entry[k] = v
            data[k] = v
        end
    end

    -- Contract fields last, so no payload key can shadow one.
    entry.event = spec.event
    entry.timestamp = spec.timestamp
    entry.state = spec.state
    entry.seq = spec.seq
    entry.run_id = spec.run_id
    -- The Lua executor has no graph-node identity yet (it lands with the resolver), so today the
    -- only way an emit site can name one is through its payload. Promoting it here means those
    -- sites need no second pass over `_log_event` when they do.
    entry.node_id = spec.node_id or data.node_id
    entry.schema_version = EventSchema.SCHEMA_VERSION
    entry.data = data

    return entry
end

--- @return boolean ok, string? err
function EventSchema.validate(entry)
    if type(entry) ~= "table" then
        return false, "event must be a table"
    end
    if entry.schema_version ~= EventSchema.SCHEMA_VERSION then
        return false, "schema_version must be " .. tostring(EventSchema.SCHEMA_VERSION) ..
            ", got " .. tostring(entry.schema_version)
    end
    if type(entry.seq) ~= "number" or entry.seq < 1 or math.floor(entry.seq) ~= entry.seq then
        return false, "seq must be a positive integer, got " .. tostring(entry.seq)
    end
    if type(entry.run_id) ~= "string" or entry.run_id == "" then
        return false, "run_id must be a non-empty string"
    end
    if entry.node_id ~= nil and type(entry.node_id) ~= "string" then
        return false, "node_id must be a string or nil"
    end
    if type(entry.event) ~= "string" or entry.event == "" then
        return false, "event must be a non-empty string"
    end
    if type(entry.timestamp) ~= "number" then
        return false, "timestamp must be a number"
    end
    if entry.state ~= nil and type(entry.state) ~= "string" then
        return false, "state must be a string or nil"
    end
    if type(entry.data) ~= "table" then
        return false, "data must be a table"
    end
    return true
end

return EventSchema
