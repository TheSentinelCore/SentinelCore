-- kernel/log.lua
-- `Sentinel.log` -- diagnostics with the author's name already on them (ADR 08 §10).
--
-- ================================================================================
-- WHY THIS EXISTS AT ALL: THE CAPABILITY WAS ALREADY BEING CLAIMED
-- ================================================================================
-- `kernel/api.lua` has listed `["log"] = true` in KERNEL_CAPABILITIES since Phase 3, while the
-- published surface had no `log` field. A manifest declaring `requires = { "log" }` was
-- therefore ADMITTED and then failed at its first call -- which is precisely the failure that
-- file's own header says the capability list exists to prevent ("claiming it would admit
-- plugins that then fail at first use"). This closes that gap.
--
-- ================================================================================
-- LOGGING IS NOT AN INTENT
-- ================================================================================
-- Every game-affecting action leaves a plugin as an intent, because it needs arbitration,
-- banding and a lease. A log line affects nothing in the world: it contends for no channel,
-- there is no lease that could authorise it, and there is nothing for the commit stage to gate.
-- Routing it through the IntentQueue would put a diagnostic behind a generation check, so a
-- plugin whose lease had just been revoked would lose exactly the log line explaining why.
--
-- ================================================================================
-- AUTO-ATTRIBUTION, AND WHY IT IS NOT A PARAMETER
-- ================================================================================
-- §10 specifies "(auto-attributed)". The obvious alternative -- `Sentinel.log:info(id, msg)` --
-- attributes whatever the caller TYPES, which is a field that goes stale on the first
-- copy-paste between plugins and is never noticed, because a wrong name in a log line looks
-- exactly like a right one.
--
-- So attribution is derived from the CALL SITE via `debug.getinfo`, and a caller cannot
-- override it. The plugin id is read off the source path, which is the same mapping
-- tests/kernel/audit_scope.lua uses to decide which package a file belongs to.
--
-- HONEST ABOUT THE SANDBOX. `debug` is not documented in the Sylvannas API surface, and this
-- repo has already been bitten by assuming a standard library is present (no `io`, no `load`,
-- no JSON). So its absence is a DEGRADATION, not an error: attribution falls back to
-- "unattributed" and the line still gets written. A logger that throws because it could not
-- work out who was calling is worse than one that admits it does not know.
-- Logged in 08a_API_GAPS.md so a live client can settle it.

local Log = {}
Log.__index = Log

Log.LEVELS = { "debug", "info", "warn", "error" }

--- What a call site maps to when `debug` is unavailable or the path matches no known package.
Log.UNATTRIBUTED = "unattributed"

-- ---------------------------------------------------------------------------
-- Attribution
-- ---------------------------------------------------------------------------

--- Source path -> plugin id. Ordered: the first match wins, so the more specific `rotations`
--- and `modules` patterns are tried before the kernel catch-all.
local ATTRIBUTION = {
    { pattern = "sentinel/rotations/([%w_]+)/", prefix = "rotations." },
    { pattern = "sentinel/modules/([%w_]+)/",   prefix = "modules."   },
    { pattern = "sentinel/kernel/",             literal = "kernel"    },
    { pattern = "sentinel/runtime/",            literal = "runtime"   },
}

---Derive a plugin id from a `debug.getinfo` source string.
---@param source string|nil e.g. "@sentinel/rotations/mage_frost/frost_tbc.lua"
---@return string
function Log.attribute(source)
    if type(source) ~= "string" then return Log.UNATTRIBUTED end
    local path = source:gsub("^@", "")
    for _, rule in ipairs(ATTRIBUTION) do
        local captured = path:match(rule.pattern)
        if captured then
            if rule.literal then return rule.literal end
            return rule.prefix .. captured
        end
    end
    return Log.UNATTRIBUTED
end

--- This file's own path, as it appears in a `debug.getinfo` source string.
---
--- The caller is found by WALKING PAST our own frames rather than by indexing a fixed level.
--- A constant would have to count: the level method, `write`, `caller_source`, and the `pcall`
--- wrapping `getinfo` -- which occupies a frame of its own. That count was wrong on the first
--- attempt and would go wrong again the moment anyone adds or removes a helper here, silently
--- mislabelling every log line in the process. Walking is self-correcting.
local SELF = "kernel/log.lua"

--- Bound the walk. A stack deeper than this without leaving log.lua means something is wrong
--- with the assumption, and an unbounded loop in a logger is not the place to find out.
local MAX_WALK = 8

local function caller_source(getinfo)
    if type(getinfo) ~= "function" then return nil end
    for level = 2, MAX_WALK do
        local ok, info = pcall(getinfo, level, "S")
        if not ok or type(info) ~= "table" then return nil end
        local source = info.source
        if type(source) == "string" and not source:find(SELF, 1, true) then
            return source
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The logger
-- ---------------------------------------------------------------------------

---@param opts table|nil { sink, getinfo }
---   sink    -- function(line); defaults to `core.log`
---   getinfo -- function(level, what); defaults to `debug.getinfo` when the sandbox has it
function Log.new(opts)
    opts = opts or {}
    local o = setmetatable({}, Log)
    o._sink = opts.sink
    if opts.getinfo ~= nil then
        o._getinfo = opts.getinfo
    else
        o._getinfo = type(debug) == "table" and debug.getinfo or nil
    end
    return o
end

function Log:_resolve_sink()
    if self._sink ~= nil then return self._sink end
    if core and type(core.log) == "function" then return core.log end
    return nil
end

---Write one line. Never throws: a diagnostic that can crash the tick is a liability, and this
---runs inside plugin code the ErrorBoundary would then blame for the logger's fault.
---@return boolean written, string|nil reason
function Log:write(level, message)
    local sink = self:_resolve_sink()
    if sink == nil then return false, "no_sink" end

    local owner = Log.attribute(caller_source(self._getinfo))
    local line = string.format("[%s][%s] %s", owner, level, tostring(message))
    local ok = pcall(sink, line)
    if not ok then return false, "sink_error" end
    return true
end

-- Colon convention, matching every other `common/` and kernel surface. Generated rather than
-- written out four times so a fifth level cannot arrive with a different shape.
for _, level in ipairs(Log.LEVELS) do
    Log[level] = function(self, message) return self:write(level, message) end
end

return Log
