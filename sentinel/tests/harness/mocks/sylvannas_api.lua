-- sentinel/tests/harness/mocks/sylvannas_api.lua
-- Mocks for documented Sylvannas API surface (core.object_manager, core.input,
-- core.log/core.log_error, _G.SentinelNavClient) plus a game_object-shaped mock
-- unit/player factory. Does NOT mock core.player / core.unit / core.spell /
-- core.spell_queue — those namespaces do not exist in the real Sylvannas API
-- (see docs/SylvannasAPI/dev/api/{object-manager,game-object,spellbook,
-- spellbook-helper}.md); real per-unit state is read via colon methods on the
-- game_object itself (e.g. unit:get_health()), and spell state via
-- core.spell_book.* / common/utility/spell_helper.
-- Used by out-of-game test harness

local Mock = {}

-- Core game time
Mock._game_time = 0
Mock._frame_count = 0

function Mock.advance_time(ms)
    Mock._game_time = Mock._game_time + ms
    Mock._frame_count = Mock._frame_count + 1
    -- One tick of game time is also one tick of the network (see `Mock.http_advance` below), so a
    -- suite that already drives the clock resolves its held HTTP callbacks without new plumbing.
    if Mock.http_advance then Mock.http_advance(1) end
end

function Mock.reset_time()
    Mock._game_time = 0
    Mock._frame_count = 0
end

-- ============================================================================
-- core.game_time
-- ============================================================================
Mock.core = Mock.core or {}
Mock.core.game_time = function()
    return Mock._game_time
end

-- ============================================================================
-- core.object_manager
-- ============================================================================
Mock.core.object_manager = Mock.core.object_manager or {}

local _objects = {}
local _local_player = nil
local _target = nil

function Mock.core.object_manager.get_local_player()
    return _local_player
end

function Mock.core.object_manager.get_target()
    return _target
end

function Mock.core.object_manager.get_all_objects()
    local result = {}
    for _, obj in pairs(_objects) do
        table.insert(result, obj)
    end
    return result
end

function Mock.core.object_manager.get_objects_in_range(x, y, z, range)
    local result = {}
    for _, obj in pairs(_objects) do
        if obj.get_position then
            local ok, pos = pcall(obj.get_position, obj)
            if ok and pos then
                local dx = pos.x - x
                local dy = pos.y - y
                local dz = pos.z - z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                if dist <= range then
                    table.insert(result, obj)
                end
            end
        end
    end
    return result
end

function Mock.set_local_player(player)
    _local_player = player
end

function Mock.set_target(unit)
    _target = unit
end

function Mock.add_object(guid, obj)
    _objects[guid] = obj
end

function Mock.remove_object(guid)
    _objects[guid] = nil
end

function Mock.clear_objects()
    _objects = {}
end

-- ============================================================================
-- core.input
-- ============================================================================
Mock.core.input = Mock.core.input or {}

function Mock.core.input.cast_spell(spell_id, target)
    print(string.format("[MOCK] CastSpell(%d, %s)", spell_id, target and target:get_guid() or "nil"))
    return true
end

function Mock.core.input.cast_spell_at(spell_id, x, y, z)
    print(string.format("[MOCK] CastSpellAt(%d, %.1f, %.1f, %.1f)", spell_id, x, y, z))
    return true
end

function Mock.core.input.interact(unit)
    print(string.format("[MOCK] Interact(%s)", unit and unit:get_guid() or "nil"))
    return true
end

function Mock.core.input.move_forward_start()
    print("[MOCK] MoveForwardStart")
    return true
end

function Mock.core.input.move_forward_stop()
    print("[MOCK] MoveForwardStop")
    return true
end

function Mock.core.input.turn_left_start()
    print("[MOCK] TurnLeftStart")
    return true
end

function Mock.core.input.turn_left_stop()
    print("[MOCK] TurnLeftStop")
    return true
end

function Mock.core.input.turn_right_start()
    print("[MOCK] TurnRightStart")
    return true
end

function Mock.core.input.turn_right_stop()
    print("[MOCK] TurnRightStop")
    return true
end

function Mock.core.input.jump()
    print("[MOCK] Jump")
    return true
end

-- ============================================================================
-- core.log / core.log_error
-- ============================================================================
Mock.core.log = function(message)
    print("[LOG] " .. tostring(message))
end

Mock.core.log_error = function(message)
    print("[ERROR] " .. tostring(message))
end

-- ============================================================================
-- core.http_get  (the ASYNC signature the injector actually has)
-- ============================================================================
--
-- The live `core.http_get(url, callback)` returns BEFORE the server answers; the callback lands
-- some ticks later, which is why `QueryClient:_get` answers `(nil, true)` first and the panels have
-- to poll. This mock had no `http_get` at all, so every offline suite exercised only the
-- resolves-immediately path -- the mechanical reason a whole cycle of panels shipped green while
-- freezing on their first pending fetch in-game.
--
-- `Mock.http.pending_ticks` is how many harness ticks a request waits before its callback fires;
-- 2 is the default because the interesting shape is "at least one tick answered nothing".
-- `Mock.http_advance()` is that tick, and `Mock.advance_time` calls it, so a suite that already
-- drives the clock gets the resolution for free.
Mock.http = {
    pending_ticks = 2,
    routes = {},     -- { { match = "/npc/567", body = "...", status = 200 } }
    requests = {},   -- every url asked for, in order
    posts = {},      -- { { url, headers, body } } — the request half of every POST
    _inflight = {},  -- { { url, callback, remaining } }
}

---Answer any url CONTAINING `fragment` with `body` (a JSON string, or a table this encodes).
function Mock.set_http_response(fragment, body, status)
    if type(body) == "table" then
        local ok, json = pcall(require, "core/JSON")
        if not (ok and type(json) == "table" and json.encode) then
            error("set_http_response was given a table but core/JSON is unavailable to encode it", 2)
        end
        body = json.encode(body)
    end
    Mock.http.routes[#Mock.http.routes + 1] =
        { match = tostring(fragment), body = body, status = tonumber(status) or 200 }
end

local function http_route_for(url)
    -- Last registration wins, so a test can override a fixture the suite set up.
    for i = #Mock.http.routes, 1, -1 do
        local route = Mock.http.routes[i]
        if string.find(url, route.match, 1, true) then return route end
    end
    return nil
end

function Mock.core.http_get(url, callback)
    url = tostring(url)
    Mock.http.requests[#Mock.http.requests + 1] = url
    if type(callback) ~= "function" then
        -- The live SDK raises "function expected" on the one-argument form. Reproducing that is the
        -- point: a caller that regresses to the synchronous shape must fail HERE, not in-game.
        error("core.http_get expects (url, callback)", 2)
    end

    local wait = tonumber(Mock.http.pending_ticks) or 0
    local route = http_route_for(url)
    local entry = {
        url = url,
        callback = callback,
        remaining = wait,
        status = route and route.status or 404,
        body = route and route.body or nil,
    }
    if wait <= 0 then
        callback(entry.status, "application/json", entry.body)
        return
    end
    Mock.http._inflight[#Mock.http._inflight + 1] = entry
end

-- ============================================================================
-- core.http_post  (the ASYNC signature the injector actually has)
-- ============================================================================
--
-- `(url, [headers,] body, callback)` per docs/SylvannasAPI/dev/api/core.md, with the SAME pending
-- model as `http_get` above: the callback lands `Mock.http.pending_ticks` harness ticks later, so a
-- caller that assumes a synchronous answer fails here rather than in the injector.
--
-- Bodies are recorded in `Mock.http.posts` because for a POST the request IS the interesting half:
-- a route estimate is only honest if the segments that were sent are the segments the operator can
-- see. Routing reuses `set_http_response`, so one registration answers a GET or a POST alike.
function Mock.core.http_post(url, headers, body, callback)
    -- The three-argument form `(url, body, callback)` is the documented fallback the query client
    -- tries when the headers form is rejected; accepting both keeps the mock honest about which one
    -- the caller actually used.
    if type(body) == "function" and callback == nil then
        callback, body, headers = body, headers, nil
    end
    url = tostring(url)
    Mock.http.requests[#Mock.http.requests + 1] = url
    Mock.http.posts[#Mock.http.posts + 1] = { url = url, headers = headers, body = body }
    if type(callback) ~= "function" then
        error("core.http_post expects (url, [headers,] body, callback)", 2)
    end

    local route = http_route_for(url)
    local entry = {
        url = url,
        callback = callback,
        remaining = tonumber(Mock.http.pending_ticks) or 0,
        status = route and route.status or 404,
        body = route and route.body or nil,
    }
    if entry.remaining <= 0 then
        callback(entry.status, "application/json", entry.body)
        return
    end
    Mock.http._inflight[#Mock.http._inflight + 1] = entry
end

---The body of the most recent POST, decoded, or nil when nothing was posted.
function Mock.last_post_body()
    local last = Mock.http.posts[#Mock.http.posts]
    if not last or type(last.body) ~= "string" then return nil end
    local ok, json = pcall(require, "core/JSON")
    if not (ok and type(json) == "table" and json.decode) then return nil end
    local decoded = json.decode(last.body)
    return decoded
end

---One harness tick of the network: fire every request whose wait has run out.
function Mock.http_advance(ticks)
    for _ = 1, (tonumber(ticks) or 1) do
        local still_waiting = {}
        local due = {}
        for _, entry in ipairs(Mock.http._inflight) do
            entry.remaining = entry.remaining - 1
            if entry.remaining <= 0 then due[#due + 1] = entry else still_waiting[#still_waiting + 1] = entry end
        end
        Mock.http._inflight = still_waiting
        for _, entry in ipairs(due) do
            entry.callback(entry.status, "application/json", entry.body)
        end
    end
end

function Mock.reset_http()
    Mock.http.pending_ticks = 2
    Mock.http.routes = {}
    Mock.http.requests = {}
    Mock.http.posts = {}
    Mock.http._inflight = {}
end

-- ============================================================================
-- _G.SentinelNavClient
-- ============================================================================
Mock.SentinelNavClient = Mock.SentinelNavClient or {}
Mock.SentinelNavClient.client = Mock.SentinelNavClient.client or {}

local _nav_path = {}
local _nav_state = "IDLE"

function Mock.SentinelNavClient.client.request_path(start_x, start_y, start_z, end_x, end_y, end_z)
    _nav_path = {
        { x = start_x, y = start_y, z = start_z },
        { x = end_x, y = end_y, z = end_z }
    }
    _nav_state = "COMPLETE"
    return true
end

function Mock.SentinelNavClient.client.get_path()
    return _nav_path
end

function Mock.SentinelNavClient.client.get_state()
    return _nav_state
end

function Mock.SentinelNavClient.client.raycast(x, y, z, dx, dy, dz, distance)
    return false, x + dx * distance, y + dy * distance, z + dz * distance
end

function Mock.SentinelNavClient.client.random_point_near(x, y, z, radius)
    return x + math.random(-radius, radius), y + math.random(-radius, radius), z
end

function Mock.set_nav_path(path)
    _nav_path = path
end

function Mock.set_nav_state(state)
    _nav_state = state
end

-- ============================================================================
-- Mock Unit Factory
-- ============================================================================
function Mock.create_mock_unit(guid, data)
    data = data or {}
    local unit = {
        _guid = guid,
        _position = data.position or { x = 0, y = 0, z = 0 },
        _health = data.health or 100,
        _max_health = data.max_health or 100,
        _power = data.power or 100,
        _max_power = data.max_power or 100,
        _power_type = data.power_type or 0,
        _level = data.level or 1,
        _name = data.name or "MockUnit",
        _creature_type = data.creature_type or "Humanoid",
        _faction = data.faction or 0,
        _reaction = data.reaction or 4,
        _is_enemy = data.is_enemy ~= false,
        _is_friendly = data.is_friendly == true,
        _is_dead = data.is_dead == true,
        _target = data.target,
        _casting_spell = data.casting_spell,
        _channeling_spell = data.channeling_spell,
        _auras = data.auras or {},
    }

    function unit:get_guid() return self._guid end
    function unit:get_position() return self._position end
    function unit:get_health() return self._health end
    function unit:get_max_health() return self._max_health end
    function unit:get_power() return self._power end
    function unit:get_max_power() return self._max_power end
    function unit:get_power_type() return self._power_type end
    function unit:get_level() return self._level end
    function unit:get_name() return self._name end
    function unit:get_creature_type() return self._creature_type end
    function unit:get_faction() return self._faction end
    function unit:get_reaction() return self._reaction end
    function unit:is_enemy() return self._is_enemy end
    function unit:is_friendly() return self._is_friendly end
    function unit:is_dead() return self._is_dead end
    function unit:get_target() return self._target end
    function unit:get_casting_spell() return self._casting_spell end
    function unit:get_channeling_spell() return self._channeling_spell end
    function unit:get_aura(spell_id) return self._auras[spell_id] end
    function unit:get_all_auras() return self._auras end
    function unit:get_distance()
        local player = Mock.core.object_manager.get_local_player()
        if not player or not player.get_position then
            return 0
        end
        local player_pos = player:get_position()
        local unit_pos = self:get_position()
        local dx = unit_pos.x - player_pos.x
        local dy = unit_pos.y - player_pos.y
        local dz = unit_pos.z - player_pos.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    function unit:get_casting_time_left() return 0 end
    function unit:get_channeling_time_left() return 0 end

    return unit
end

function Mock.create_mock_player(data)
    local unit = Mock.create_mock_unit("Player-1234", data)
    unit._class = data.class or 8 -- Mage
    unit._is_moving = data.is_moving or false
    unit._in_combat = data.in_combat or false
    unit._is_mounted = data.is_mounted or false
    unit._is_dead = data.is_dead or false
    unit._is_ghost = data.is_ghost or false
    unit._is_casting = data.is_casting or false
    unit._is_channeling = data.is_channeling or false

    function unit:get_class() return self._class end
    function unit:is_moving() return self._is_moving end
    function unit:in_combat() return self._in_combat end
    function unit:is_mounted() return self._is_mounted end
    function unit:is_dead() return self._is_dead end
    function unit:is_ghost() return self._is_ghost end
    function unit:is_casting() return self._is_casting end
    function unit:is_channeling() return self._is_channeling end

    return unit
end

-- ============================================================================
-- Global Setup / Teardown
-- ============================================================================
function Mock.setup_globals()
    _G.core = Mock.core
    _G.SentinelNavClient = Mock.SentinelNavClient
    _G.SentinelNavClient.client = Mock.SentinelNavClient.client
end

function Mock.teardown_globals()
    _G.core = nil
    _G.SentinelNavClient = nil
end

function Mock.reset()
    Mock.reset_time()
    Mock.reset_http()
    Mock.clear_objects()
    _nav_path = {}
    _nav_state = "IDLE"
    _local_player = nil
    _target = nil
end

return Mock