-- CoordClient.lua — HTTP polling client for the SentinelDuoCoordServer.
-- Uses core.http_get (async, callback-based). Never blocks.

local helpers      = require("lib/helpers")
local PartnerState = require("coordination/PartnerState")
local JSON         = require("lib/json")

---@class CoordClient
---@field _server_url string
---@field _poll_interval_ms number
---@field _http_timeout_ms number
---@field _pending boolean
---@field _pending_since_ms number
---@field _last_poll_ms number
---@field _session table|nil
---@field _my_client_id string|nil
---@field _connected boolean
---@field _barrier_results table<string, table>
local CoordClient = {}
CoordClient.__index = CoordClient

---@param config table
---@return CoordClient
function CoordClient:new(config)
    return setmetatable({
        _server_url       = config.coord_server_url or "http://127.0.0.1:7300",
        _poll_interval_ms = config.poll_interval_ms or 100,
        _http_timeout_ms  = config.http_timeout_ms  or 2000,
        _pending          = false,
        _pending_since_ms = 0,
        _last_poll_ms     = 0,
        _backoff_until_ms = 0,   -- retry not before this timestamp (ms)
        _session          = nil,
        _my_client_id     = nil,
        _connected        = false,
        _barrier_results  = {},
        _barrier_pending  = {},
        _last_warn_ms     = 0,   -- throttle repeated warnings to every 5s
    }, CoordClient)
end

local WARN_INTERVAL_MS = 5000

-- Build the phase string for the heartbeat from the blackboard.
local PHASE_MAP = {
    INIT                  = "initializing",
    COORD_CONNECT         = "initializing",
    BUFFING               = "buffing",
    TRAVEL_TO_INSTANCE    = "traveling_to_instance",
    ENTERING              = "entering_instance",
    INSIDE_BUFF           = "entering_instance",
    FARM_POSITIONING      = "positioning",
    FARM_PULL_RUNNING     = "pull_running",
    FARM_PULL_ICEBLOCK    = "pull_ice_block",
    FARM_AOE_OPENING      = "aoe_opening",
    FARM_ICE_BLOCK_CANCEL = "aoe_opening",
    FARM_AOE_BOTH         = "aoe_both",
    FARM_LOOTING          = "looting",
    EXITING               = "exiting_instance",
    RESETTING             = "resetting",
    WAITING_LOCKOUT       = "waiting_lockout",
    TRAVEL_TO_VENDOR      = "traveling_to_vendor",
    VENDORING             = "vendoring",
    TRAVEL_RETURN         = "returning_to_instance",
    DEAD                  = "dead",
    PAUSED                = "paused",
    ERROR                 = "error",
}

local function get_phase_string(bb)
    local state = bb:get("duo.current_state", "initializing")
    -- When inside the farm sub-FSM, read the sub-state from blackboard
    if state == "FARMING" then
        return bb:get("duo.farm_sub_state", "positioning")
    end
    return PHASE_MAP[state] or "initializing"
end

--- Main tick — dispatches heartbeat when interval elapsed and no pending request.
---@param blackboard Blackboard
---@param game_time_ms number
function CoordClient:tick(blackboard, game_time_ms)
    -- Check for timed-out pending request
    if self._pending then
        if game_time_ms - self._pending_since_ms > self._http_timeout_ms then
            if game_time_ms - self._last_warn_ms > WARN_INTERVAL_MS then
                helpers.log_warn("[COORD] HTTP request timed out, clearing pending")
                self._last_warn_ms = game_time_ms
            end
            self._pending         = false
            self._connected       = false
            self._backoff_until_ms = game_time_ms + 2000
            blackboard:set("duo.coord_connected", false)
        end
        return
    end

    -- Backoff after failure — wait at least 2s before retrying
    if game_time_ms < self._backoff_until_ms then
        return
    end

    -- Throttle to poll_interval_ms
    if game_time_ms - self._last_poll_ms < self._poll_interval_ms then
        return
    end

    self._last_poll_ms = game_time_ms
    self:_send_heartbeat(blackboard, game_time_ms)
end

function CoordClient:_send_heartbeat(blackboard, game_time_ms)
    local client_id  = self._my_client_id or ""
    local phase      = get_phase_string(blackboard)
    local hp         = math.floor((blackboard:get("player.hp_pct", 1.0)) * 100)
    local mp         = math.floor((blackboard:get("player.mp_pct", 1.0)) * 100)
    local bags_full  = blackboard:get("duo.bags_full_local", false) and 1 or 0
    local is_dead    = blackboard:get("player.is_dead", false) and 1 or 0
    local in_instance = blackboard:get("player.in_instance", false) and 1 or 0

    local url = string.format(
        "%s/api/v1/heartbeat?client_id=%s&phase=%s&hp=%d&mp=%d&bags_full=%d&is_dead=%d&in_instance=%d",
        self._server_url, client_id, phase, hp, mp, bags_full, is_dead, in_instance
    )

    self._pending = true
    self._pending_since_ms = game_time_ms

    local ok = pcall(core.http_get, url, function(code, _content_type, data, _headers)
        self._pending = false
        -- Use fresh time inside the callback — game_time_ms is stale (dispatch time).
        local now_ms = helpers.game_time_ms()
        if code ~= 200 then
            self._connected        = false
            self._backoff_until_ms = now_ms + 2000
            blackboard:set("duo.coord_connected", false)
            if now_ms - self._last_warn_ms > WARN_INTERVAL_MS then
                helpers.log_warn("[COORD] heartbeat HTTP " .. tostring(code))
                self._last_warn_ms = now_ms
            end
            return
        end

        local parsed = JSON.decode(data)
        if type(parsed) ~= "table" then
            if now_ms - self._last_warn_ms > WARN_INTERVAL_MS then
                helpers.log_warn("[COORD] heartbeat parse error — raw: " .. tostring(data):sub(1, 80))
                self._last_warn_ms = now_ms
            end
            return
        end

        self._connected = true
        self._session = parsed

        -- Store our assigned client ID
        local acid = parsed.assigned_client_id
        if not self._id_logged then
            self._id_logged = true
            helpers.log("[COORD] first response — assigned_client_id=" .. tostring(acid)
                .. " puller_id=" .. tostring(parsed.puller_id))
        end
        if acid and acid ~= "" then
            self._my_client_id = acid
            blackboard:set("duo.my_client_id", parsed.assigned_client_id)
            local is_puller = (parsed.puller_id == parsed.assigned_client_id)
            blackboard:set("duo.is_puller", is_puller)
        end

        -- Update coordination blackboard keys
        blackboard:set("duo.coord_connected", true)
        blackboard:set("duo.coord_last_poll_ms", now_ms)
        blackboard:set("duo.session_phase", parsed.session_phase)
        blackboard:set("duo.pull_index", parsed.pull_index or 0)
        blackboard:set("duo.puller_id", parsed.puller_id or "mage_a")
        blackboard:set("duo.vendor_break_active", parsed.vendor_break_requested or false)

        -- Lockout info
        local lockout = parsed.lockout or {}
        blackboard:set("duo.lockout.reset_count", lockout.reset_count or 0)
        blackboard:set("duo.lockout.near_limit",  lockout.near_limit  or false)
        blackboard:set("duo.lockout.wait_secs",   lockout.next_window_reset_secs or 0)

        -- Partner state
        local my_id      = blackboard:get("duo.my_client_id", "mage_a")
        local partner_key = (my_id == "mage_a") and "mage_b" or "mage_a"
        local partner_data = parsed[partner_key] or {}

        blackboard:set("duo.partner_phase",      partner_data.phase       or "offline")
        blackboard:set("duo.partner_health_pct", (partner_data.health_pct or 0) / 100.0)
        blackboard:set("duo.partner_mana_pct",   (partner_data.mana_pct   or 0) / 100.0)
        blackboard:set("duo.partner_connected",  partner_data.connected   or false)
        blackboard:set("duo.partner_bags_full",  partner_data.bags_full   or false)
    end)

    if not ok then
        self._pending = false
        self._connected = false
        blackboard:set("duo.coord_connected", false)
    end
end

--- Enter a named sync barrier (async — check poll_barrier for result).
---@param name string
function CoordClient:enter_barrier(name)
    if not self._my_client_id then return end
    local url = string.format("%s/api/v1/barrier/enter?client_id=%s&name=%s",
        self._server_url, self._my_client_id, name)
    pcall(core.http_get, url, function(code, _, data)
        if code == 200 then
            local parsed = JSON.decode(data)
            if type(parsed) == "table" then
                self._barrier_results[name] = parsed
            end
        end
    end)
end

--- Poll a barrier. Returns true if both_ready, "timeout" if partner_disconnected, false otherwise.
---@param name string
---@return boolean|string
function CoordClient:poll_barrier(name)
    -- Check cached result first
    local cached = self._barrier_results[name]
    if cached then
        if cached.both_ready then return true end
        if cached.partner_disconnected then return "timeout" end
    end

    -- Dispatch a fresh poll
    if not self._barrier_pending[name] then
        self._barrier_pending[name] = true
        local url = string.format("%s/api/v1/barrier/poll?client_id=%s&name=%s",
            self._server_url, self._my_client_id or "", name)
        pcall(core.http_get, url, function(code, _, data)
            self._barrier_pending[name] = false
            if code == 200 then
                local parsed = JSON.decode(data)
                if type(parsed) == "table" then
                    self._barrier_results[name] = parsed
                end
            end
        end)
    end

    return false
end

--- Release from a barrier.
---@param name string
function CoordClient:release_barrier(name)
    self._barrier_results[name] = nil
    self._barrier_pending[name] = nil
    if not self._my_client_id then return end
    local url = string.format("%s/api/v1/barrier/release?client_id=%s&name=%s",
        self._server_url, self._my_client_id, name)
    pcall(core.http_get, url, function() end)
end

--- Signal pull advance (called after loot complete).
function CoordClient:advance_pull()
    if not self._my_client_id then return end
    local url = string.format("%s/api/v1/pull/advance?client_id=%s",
        self._server_url, self._my_client_id)
    pcall(core.http_get, url, function(code, _, data)
        if code == 200 then
            local parsed = JSON.decode(data)
            if type(parsed) == "table" then
                helpers.log("[COORD] pull advanced: index=" .. tostring(parsed.new_pull_index) ..
                    " puller=" .. tostring(parsed.new_puller_id))
            end
        end
    end)
end

--- Signal bags full / need vendor break.
function CoordClient:request_vendor_break()
    if not self._my_client_id then return end
    local url = string.format("%s/api/v1/vendor/request?client_id=%s",
        self._server_url, self._my_client_id)
    pcall(core.http_get, url, function() end)
end

--- Record an instance lockout reset.
function CoordClient:record_reset()
    if not self._my_client_id then return end
    local url = string.format("%s/api/v1/lockout/record?client_id=%s",
        self._server_url, self._my_client_id)
    pcall(core.http_get, url, function(code, _, data)
        if code == 200 then
            local parsed = JSON.decode(data)
            if type(parsed) == "table" then
                helpers.log("[COORD] reset recorded: count=" .. tostring(parsed.reset_count) ..
                    " near_limit=" .. tostring(parsed.near_limit) ..
                    " must_wait=" .. tostring(parsed.must_wait))
            end
        end
    end)
end

--- Get the last received session state table.
---@return table|nil
function CoordClient:get_session()
    return self._session
end

--- Returns true if coord server is reachable.
---@return boolean
function CoordClient:is_connected()
    return self._connected
end

return CoordClient
