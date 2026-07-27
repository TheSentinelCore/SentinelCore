--- Sentinel Editor Client
--- HTTP client for the sentinel-editor campaign API (default port 3031).
---
--- WHY THIS FILE EXISTS
--- -------------------
--- The Rust CRUD at :3031 has been complete since the baseline landed and had ZERO Lua callers
--- (obs #225). Every authoring command in the IDE -- add-to-profile, add-chain, edit-intent,
--- add-as-kill, validate, compile -- answered a success string and wrote nothing. This is the
--- transport those commands were missing.
---
--- READS ANSWER THE PENDING CONTRACT
--- --------------------------------
--- The Sylvannas SDK has exactly two HTTP verbs, `core.http_get` and `core.http_post`
--- (docs/SylvannasAPI/dev/api/core.md:872,932), and BOTH are asynchronous. So every read here
--- answers exactly what `QueryClient:_get` answers -- `data` | `(nil, true)` pending |
--- `(nil, nil)` resolved-to-nothing -- and a caller drives it straight through `ui/async_slot.lua`
--- with no adapter.

local QueryClient = require("shared/query_client")

local JsonLib = (function()
    local ok, mod = pcall(require, "core/JSON")
    if ok and type(mod) == "table" and mod.encode then return mod end
    return nil
end)()

local EditorClient = {}
EditorClient.__index = EditorClient

--- Every campaign path shares this prefix, which is also the cache-invalidation unit: any write to
--- any campaign drops every cached campaign read, because a write can change the list as well as
--- the graph it targeted.
local ROOT = "/editor/campaigns"

-- ---------------------------------------------------------------------------
-- Ids
-- ---------------------------------------------------------------------------

local _seeded = false

--- A v4 UUID string.
---
--- `platform::Node.id`, `Graph.id` and `Edge.id` are `Uuid`, not strings, so a node carrying the
--- Explorer's authoring id ("q1234_accept") is rejected by serde with a 400 the operator would read
--- as "the editor is broken". The authoring id is not thrown away -- it rides along in the node's
--- `context`, the field the platform model keeps precisely for provenance it must not interpret.
function EditorClient.uuid4()
    if not _seeded then
        _seeded = true
        local seed = 0
        if type(core) == "table" and type(core.time) == "function" then
            local ok, t = pcall(core.time)
            if ok then seed = tonumber(t) or 0 end
        end
        if seed == 0 then seed = tonumber(tostring(os.time())) or 1 end
        math.randomseed(seed)
    end
    local function hex(n)
        local out = {}
        for _ = 1, n do out[#out + 1] = string.format("%x", math.random(0, 15)) end
        return table.concat(out)
    end
    -- Version 4, variant 10xx -- the bits `Uuid::parse_str` will not complain about and every other
    -- tool in the stack expects to see.
    return string.format("%s-%s-4%s-%s%s-%s",
        hex(8), hex(4), hex(3), string.format("%x", math.random(8, 11)), hex(3), hex(12))
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

---@param host string|nil defaults to 127.0.0.1
---@param port number|nil defaults to 3031 (SENTINEL_EDITOR_PORT)
function EditorClient:new(host, port)
    local o = setmetatable({}, EditorClient)
    o._qc = QueryClient:new(host or "127.0.0.1", port or 3031)
    -- Refusals that arrived after their dispatch returned. Drained, not overwritten: two writes in
    -- one tick that both fail must both be sayable.
    o._errors = {}
    -- Poll state for the POSTs whose ANSWER is the point (validate, compile), keyed by request.
    o._posts = {}
    return o
end

---The underlying QueryClient, exposed so a host can share cache accounting or a test can inspect it.
function EditorClient:query_client() return self._qc end

--- Pop the oldest queued server refusal, or nil when there is nothing to report.
---@return string|nil
function EditorClient:take_error()
    if #self._errors == 0 then return nil end
    return table.remove(self._errors, 1)
end

function EditorClient:_record_error(what, http_code, body)
    local detail
    if http_code == 0 then
        -- The only way to tell "the editor is not running" from "the editor said no".
        detail = "the editor at " .. self._qc._host .. ":" .. tostring(self._qc._port) .. " did not answer"
    else
        detail = "HTTP " .. tostring(http_code)
        if type(body) == "string" and body ~= "" then
            detail = detail .. ": " .. body:sub(1, 160)
        end
    end
    self._errors[#self._errors + 1] = what .. " failed: " .. detail
end

-- ---------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------

--- `core/JSON` exports plain FUNCTIONS, not methods: its module table is
--- `{ decode = f, encode = f, new = f }` and `encode(value, pretty)` takes the value first. Calling
--- it colon-style encodes the module table with the real payload read as `pretty`, and the result is
--- still a string -- so the mistake produces a well-formed request carrying the wrong document and
--- nothing raises. `query_client.lua` uses the same dot form for the same reason.
local function encode(value)
    if not JsonLib then return nil, "core/JSON is unavailable in this sandbox" end
    local ok, body = pcall(JsonLib.encode, value)
    if not ok or type(body) ~= "string" then return nil, "could not encode the request body" end
    return body
end

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

--- `GET /editor/campaigns` -> `Vec<CampaignSummary{name, id, updated_at, node_count, edge_count}>`
---@return table|nil summaries, boolean|nil pending
function EditorClient:list_campaigns()
    return self._qc:_get(ROOT)
end

--- `GET /editor/campaigns/{name}` -> the whole `Campaign` (schema_version, id, name, graphs[...]).
---@return table|nil campaign, boolean|nil pending
function EditorClient:load_campaign(name)
    name = tostring(name or "")
    if name == "" then return nil end
    return self._qc:_get(ROOT .. "/" .. name)
end

--- The id of the graph a write should land in, read from the cached campaign.
---
---@return string|nil graph_id, string|nil reason  reason is set only when there is no id to give
function EditorClient:graph_id_for(name)
    local campaign, pending = self:load_campaign(name)
    if pending then return nil, "campaign '" .. tostring(name) .. "' is still loading" end
    if type(campaign) ~= "table" then
        return nil, "campaign '" .. tostring(name) .. "' could not be read from the editor"
    end
    local graphs = campaign.graphs
    if type(graphs) ~= "table" or #graphs == 0 then return nil, nil end
    return tostring(graphs[1].id or ""), nil
end

return EditorClient
