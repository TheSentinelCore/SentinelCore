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
--- TWO VERB FAMILIES, AND THE REASON THEY DIFFER
--- ---------------------------------------------
--- The Sylvannas SDK has exactly two HTTP verbs, `core.http_get` and `core.http_post`
--- (docs/SylvannasAPI/dev/api/core.md:872,932), and BOTH are asynchronous. Nothing here can answer
--- "the server accepted this" in the frame the request is issued, so the client does not pretend to:
---
---   POLLED (`list_campaigns`, `load_campaign`, `create_campaign`, `validate`, `compile`)
---     Answer exactly what `QueryClient:_get` answers -- `data` | `(nil, true)` pending |
---     `(nil, nil)` resolved-to-nothing -- so a caller can drive them straight through
---     `ui/async_slot.lua` with no adapter. `create_campaign` is here rather than below because
---     its answer is what the caller needs next: opening a campaign before the editor finished
---     creating it reads as a 404, and a 404 is cached.
---
---   DISPATCHED (`add_nodes`, `update_node`, `save_graph`)
---     Answer `true` when the request left, or `(false, reason)` when it could not be built or sent
---     AT ALL. A refusal from a live editor arrives ticks later and is queued; the caller drains it
---     with `take_error()` on a tick and shows it. A mutation NEVER reports the server's verdict
---     inline, because inline it does not exist yet.
---
--- Callers must not treat a dispatched `true` as "the graph now contains this". Re-read the campaign
--- (`load_campaign` after `invalidate`) and render what the server returned.

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

local HEX = "0123456789abcdef"

-- A PRIVATE LCG, not `math.random`, for the two reasons `modules/questing/recorder.lua` already
-- writes down and this file has to obey for the same stack:
--   1. LuaJIT's global generator is unseeded, so every session would mint the SAME id sequence and
--      two campaigns authored on two days would collide on ids that must never be reused.
--   2. Seeding the global generator to fix (1) silently changes the draws every other module and
--      every offline suite gets -- a very wide blast radius for an id helper.
-- Uniqueness and opacity are all these ids need; they are not secrets.
local rng_state = nil

local function next_draw(modulo)
    if not rng_state then
        local seconds = 0
        if type(core) == "table" and type(core.time) == "function" then
            local ok, t = pcall(core.time)
            if ok then seconds = tonumber(t) or 0 end
        end
        if seconds == 0 and type(os) == "table" and os.time then seconds = os.time() end
        rng_state = (math.floor(seconds * 1000) % 2147483647) + 1
    end
    rng_state = (1103515245 * rng_state + 12345) % 2147483648
    -- Middle bits: an LCG's low bits cycle with a very short period.
    return (math.floor(rng_state / 65536) % modulo) + 1
end

local function hex_digits(count)
    local out = {}
    for i = 1, count do
        local pick = next_draw(16)
        out[i] = HEX:sub(pick, pick)
    end
    return table.concat(out)
end

--- A v4-shaped UUID string.
---
--- `platform::Node.id`, `Graph.id` and `Edge.id` are `Uuid`, not strings, so a node carrying the
--- Explorer's authoring id ("q1234_accept") is rejected by serde with a 400 the operator would read
--- as "the editor is broken". The authoring id is not thrown away -- it rides along in the node's
--- `context`, the field the platform model keeps precisely for provenance it must not interpret.
function EditorClient.uuid4()
    -- One draw used for both bounds: two independent draws produce a slice of the wrong length
    -- (or an empty one), which silently emits a malformed uuid nobody validates downstream.
    local variant_index = next_draw(4)
    local variant = ("89ab"):sub(variant_index, variant_index)
    return table.concat({
        hex_digits(8), "-",
        hex_digits(4), "-",
        "4" .. hex_digits(3), "-",
        variant .. hex_digits(3), "-",
        hex_digits(12),
    })
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

--- Fire a mutation. Returns `true` once the request is on the wire.
---@return boolean ok, string|nil reason
function EditorClient:_mutate(what, path, payload)
    local body, why = encode(payload)
    if not body then return false, what .. " failed: " .. why end

    local client = self
    local sent, reason = self._qc:post(path, body, function(http_code, response)
        if http_code < 200 or http_code >= 300 then
            client:_record_error(what, http_code, response)
            return
        end
        -- A write invalidates every campaign read, not just this campaign's: creating one changes
        -- the LIST, and adding a node changes a graph another panel may already be showing.
        client._qc:invalidate(ROOT)
    end)
    if not sent then return false, what .. " failed: " .. tostring(reason) end
    -- Optimism is not permitted about the answer, only about the send. The cache is dropped here as
    -- well as in the callback so a poll issued before the answer lands cannot serve pre-write data.
    self._qc:invalidate(ROOT)
    return true
end

--- Fire a POST whose ANSWER is the point, and poll it like a GET.
---
--- `QueryClient:_get` cannot be reused here: it caches by path, and a POST's answer depends on the
--- body it carried. This keeps its own one-slot-per-key state instead.
---@param invalidates string|nil a cache prefix to drop once the answer is known, for the asks that
---       also CHANGE something (create). Dropped on resolution rather than on dispatch so a poll
---       that is already in flight is not abandoned for an answer that has not arrived.
---@return any data, boolean|nil pending
function EditorClient:_ask(key, path, payload, invalidates)
    local slot = self._posts[key]
    if slot and slot.done then
        return slot.value
    end
    if slot and slot.inflight then
        return nil, true
    end

    local body, why = encode(payload or {})
    if not body then
        self._errors[#self._errors + 1] = key .. " failed: " .. why
        return nil
    end

    slot = { inflight = true, done = false, value = nil }
    self._posts[key] = slot

    local client = self
    local sent, reason = self._qc:post(path, body, function(http_code, response)
        slot.inflight = false
        slot.done = true
        if http_code < 200 or http_code >= 300 then
            client:_record_error(key, http_code, response)
            slot.value = nil
            return
        end
        if invalidates then client._qc:invalidate(invalidates) end
        if type(response) ~= "string" or response == "" then
            -- A 2xx with no body is a real answer: "nothing to report".
            slot.value = {}
            return
        end
        local decoded
        if JsonLib and JsonLib.decode then
            local ok, v = pcall(JsonLib.decode, response)
            if ok then decoded = v end
        end
        slot.value = decoded
    end)
    if not sent then
        self._posts[key] = nil
        self._errors[#self._errors + 1] = key .. " failed: " .. tostring(reason)
        return nil
    end
    if slot.done then return slot.value end
    return nil, true
end

--- Forget a polled POST so the next call asks again. Validate and compile are ACTIONS: asking twice
--- must mean asking twice, or the second click after an edit would replay the first answer.
function EditorClient:forget(key)
    self._posts[key] = nil
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

-- ---------------------------------------------------------------------------
-- Writes
-- ---------------------------------------------------------------------------

--- `POST /editor/campaigns` with `{name}` -> the new `CampaignSummary`.
---
--- NOTE the shape: the spec described `POST /editor/campaigns/{name}`, but the mounted route takes
--- the name in the BODY (`campaign_handlers.rs::mount`). This client speaks the route that exists.
---
--- POLLED rather than dispatched, unlike the other writes, because its answer is the thing the
--- caller needs next: opening the campaign before the editor has finished creating it reads as a
--- 404, and a 404 is cached. Waiting for the 201 removes the race instead of racing it.
---@return table|nil summary, boolean|nil pending
function EditorClient:create_campaign(name)
    name = tostring(name or "")
    if name == "" then return nil end
    return self:_ask(EditorClient.create_key(name), ROOT, { name = name }, ROOT)
end

---The `_ask` key `create_campaign` stores its answer under.
function EditorClient.create_key(name)
    return "create campaign '" .. tostring(name or "") .. "'"
end

---Drop a create's remembered answer, so a caller never has to know the key's spelling.
function EditorClient:forget_create(name)
    self:forget(EditorClient.create_key(name))
end

--- Convert one authoring node descriptor into the platform `Node` the editor deserializes.
---@return table|nil node, string|nil reason
function EditorClient.to_platform_node(node)
    if type(node) ~= "table" then return nil, "a node must be a table" end
    local node_type = tostring(node.type or "")
    if node_type == "" then return nil, "a node must carry a type" end

    local intent = node.intent
    if type(intent) ~= "table" then return nil, node_type .. " has no intent" end
    if next(intent) == nil then
        -- `Intent` is a map and an empty Lua table encodes as `[]`, which serde rejects with a 400
        -- the operator would read as "the editor is broken". Refuse here, where the reason is
        -- still in scope.
        return nil, node_type .. " has an empty intent, which encodes as a JSON array, not an object"
    end

    return {
        id = EditorClient.uuid4(),
        type = node_type,
        intent = intent,
        -- `context` is raw JSON the platform model carries through untouched. The authoring id lives
        -- here so a duplicate add is still recognisable after the editor mints real UUIDs.
        context = { authoring_id = tostring(node.id or ""), preview = tostring(node.preview or "") },
    }
end

--- Add nodes (and optionally edges) to a campaign's first graph.
---
--- A freshly created campaign has ZERO graphs (`Campaign::new`), and `POST .../nodes` 400s with
--- "Graph not found" against one. When `edges` is supplied and there is no graph yet, the whole
--- subgraph is written in one `save_graph` call. When a graph already exists, edges are ignored for
--- now -- wiring them would require a round-trip to map authoring ids to server UUIDs.
---@param name string campaign name
---@param nodes table array of `{ type, intent, id?, preview? }`
---@param edges table|nil array of `{ from = authoring_id, to = authoring_id }`
---@return boolean ok, string|nil reason
function EditorClient:add_nodes(name, nodes, edges)
    name = tostring(name or "")
    if name == "" then return false, "add nodes failed: no campaign was named" end
    if type(nodes) ~= "table" or #nodes == 0 then
        return false, "add nodes failed: there were no nodes to add"
    end

    local platform = {}
    local authoring_to_uuid = {}
    for i, node in ipairs(nodes) do
        local converted, why = EditorClient.to_platform_node(node)
        if not converted then
            return false, "add nodes failed: node " .. i .. " " .. tostring(why)
        end
        platform[#platform + 1] = converted
        if node.id then
            authoring_to_uuid[tostring(node.id)] = converted.id
        end
    end

    local graph_id, blocked = self:graph_id_for(name)
    if blocked then return false, "add nodes failed: " .. blocked end

    if not graph_id or graph_id == "" then
        -- No graph yet: one request that both creates the graph and carries the nodes AND edges.
        local platform_edges = {}
        for _, e in ipairs(edges or {}) do
            local from_uuid = authoring_to_uuid[tostring(e.from)]
            local to_uuid = authoring_to_uuid[tostring(e.to)]
            if from_uuid and to_uuid then
                platform_edges[#platform_edges + 1] = {
                    id = EditorClient.uuid4(),
                    from = from_uuid,
                    to = to_uuid,
                }
            end
        end
        return self:save_graph(name, platform, platform_edges)
    end

    local what = string.format("add %d node(s) to '%s'", #platform, name)
    for _, node in ipairs(platform) do
        local ok, why = self:_mutate(what, ROOT .. "/" .. name .. "/nodes",
            { graph_id = graph_id, node = node })
        if not ok then return false, why end
    end
    return true
end

--- `POST /editor/campaigns/{name}/graphs` with a whole graph.
---
--- `entry_node` is required and is the id of the first node, so a graph saved with no nodes still
--- has to name one; a nil UUID is the honest "there is no entry yet".
function EditorClient:save_graph(name, nodes, edges, graph_name)
    name = tostring(name or "")
    if name == "" then return false, "save graph failed: no campaign was named" end
    nodes = nodes or {}
    local entry = (nodes[1] and nodes[1].id) or "00000000-0000-0000-0000-000000000000"
    return self:_mutate("save graph in '" .. name .. "'", ROOT .. "/" .. name .. "/graphs", {
        graph = {
            id = EditorClient.uuid4(),
            name = tostring(graph_name or "main"),
            entry_node = entry,
            nodes = nodes,
            edges = edges or {},
        },
    })
end

--- Replace one node.
---
--- The mounted route is `PUT|POST /editor/campaigns/{name}/nodes/{node_id}`. POST is not a
--- stylistic choice: the Sylvannas SDK has `http_get` and `http_post` and NOTHING else, so a
--- PUT-only route is unreachable from in-game Lua. The alias was added for exactly this call.
---@param name string campaign
---@param node_id string the server's UUID for the node
---@param node table the full replacement node `{ id, type, intent, ... }`
---@param graph_id string the graph the node lives in
function EditorClient:update_node(name, node_id, node, graph_id)
    name = tostring(name or "")
    node_id = tostring(node_id or "")
    if name == "" or node_id == "" then
        return false, "update node failed: the campaign and node must both be named"
    end
    if type(node) ~= "table" or type(node.intent) ~= "table" or next(node.intent) == nil then
        return false, "update node failed: node " .. node_id .. " has no intent to write"
    end
    graph_id = tostring(graph_id or "")
    if graph_id == "" then
        local resolved, blocked = self:graph_id_for(name)
        if blocked then return false, "update node failed: " .. blocked end
        if not resolved or resolved == "" then
            return false, "update node failed: campaign '" .. name .. "' has no graph"
        end
        graph_id = resolved
    end

    return self:_mutate("update node " .. node_id, ROOT .. "/" .. name .. "/nodes/" .. node_id, {
        graph_id = graph_id,
        node = {
            id = node_id,
            type = tostring(node.type or ""),
            intent = node.intent,
            context = node.context,
        },
    })
end

--- Remove one node.
---
--- Uses the POST alias because the Sylvannas SDK has no DELETE verb.
---@param name string campaign
---@param node_id string the server's UUID for the node
---@param graph_id string the graph the node lives in
function EditorClient:delete_node(name, node_id, graph_id)
    name = tostring(name or "")
    node_id = tostring(node_id or "")
    if name == "" or node_id == "" then
        return false, "delete node failed: the campaign and node must both be named"
    end
    graph_id = tostring(graph_id or "")
    if graph_id == "" then
        local resolved, blocked = self:graph_id_for(name)
        if blocked then return false, "delete node failed: " .. blocked end
        if not resolved or resolved == "" then
            return false, "delete node failed: campaign '" .. name .. "' has no graph"
        end
        graph_id = resolved
    end

    return self:_mutate("delete node " .. node_id,
        ROOT .. "/" .. name .. "/nodes/" .. node_id .. "/remove",
        { graph_id = graph_id })
end

-- ---------------------------------------------------------------------------
-- Validate / compile — POSTs whose answer is the point
-- ---------------------------------------------------------------------------

--- `POST /editor/campaigns/{name}/validate` -> `Vec<Diagnostic{code, message, node_id?}>`.
---@return table|nil diagnostics, boolean|nil pending
function EditorClient:validate(name)
    name = tostring(name or "")
    if name == "" then return nil end
    return self:_ask("validate '" .. name .. "'", ROOT .. "/" .. name .. "/validate")
end

--- `POST /editor/campaigns/{name}/compile` -> a compile result object.
---@return table|nil result, boolean|nil pending
function EditorClient:compile(name)
    name = tostring(name or "")
    if name == "" then return nil end
    return self:_ask("compile '" .. name .. "'", ROOT .. "/" .. name .. "/compile")
end

return EditorClient
