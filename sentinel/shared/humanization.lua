local Humanization = {}
Humanization.__index = Humanization

local function num(v)
    return tonumber(v) or 0
end

local function now_s()
    if core and core.time and type(core.time) == "function" then
        local ok, v = pcall(core.time)
        if ok and tonumber(v) then
            return tonumber(v)
        end
    end
    return 0
end

local function seeded_random_seed()
    local seed = 0

    if core then
        if type(core.time) == "function" then
            local ok, v = pcall(core.time)
            if ok then
                seed = seed + math.floor(num(v) * 1000000)
            end
        end

        if type(core.game_time) == "function" then
            local ok, v = pcall(core.game_time)
            if ok then
                seed = seed + math.floor(num(v) * 1000)
            end
        end

        if type(core.get_ping) == "function" then
            local ok, v = pcall(core.get_ping)
            if ok then
                seed = seed + (num(v) * 131)
            end
        end

        if type(core.get_map_id) == "function" then
            local ok, v = pcall(core.get_map_id)
            if ok then
                seed = seed + (num(v) * 37)
            end
        end

        if type(core.get_instance_id) == "function" then
            local ok, v = pcall(core.get_instance_id)
            if ok then
                seed = seed + (num(v) * 977)
            end
        end

        if core.object_manager and type(core.object_manager.get_local_player) == "function" then
            local okp, player = pcall(core.object_manager.get_local_player)
            if okp and player and type(player.get_position) == "function" then
                local okpos, pos = pcall(player.get_position, player)
                if okpos and type(pos) == "table" then
                    seed = seed + math.floor((num(pos.x) + num(pos.y) + num(pos.z)) * 10)
                end
            end
        end
    end

    local t = now_s()
    if t > 0 then
        seed = seed + math.floor(t * 1000)
    end

    if seed == 0 then
        seed = 13371337
    end
    seed = math.abs(math.floor(seed)) % 2147483647
    if seed == 0 then
        seed = 1
    end

    math.randomseed(seed)
end

seeded_random_seed()

function Humanization.new()
    local self = setmetatable({}, Humanization)
    self._timers = {}
    return self
end

function Humanization:random_between(min_v, max_v)
    local a = tonumber(min_v) or 0
    local b = tonumber(max_v) or a
    if b < a then
        a, b = b, a
    end
    if b == a then
        return a
    end
    return a + (math.random() * (b - a))
end

function Humanization:get_or_schedule(key, min_delay, max_delay)
    local k = tostring(key or "default")
    local current = now_s()
    local deadline = self._timers[k]
    if not deadline then
        deadline = current + self:random_between(min_delay, max_delay)
        self._timers[k] = deadline
    end
    return deadline
end

function Humanization:is_ready(key, min_delay, max_delay)
    local k = tostring(key or "default")
    local current = now_s()
    local deadline = self:get_or_schedule(k, min_delay, max_delay)
    if current >= deadline then
        self._timers[k] = nil
        return true
    end
    return false
end

function Humanization:jitter_point(pos, amount)
    if type(pos) ~= "table" then
        return pos
    end
    local a = tonumber(amount) or 0
    if a <= 0 then
        return { x = pos.x, y = pos.y, z = pos.z }
    end
    return {
        x = (tonumber(pos.x) or 0) + self:random_between(-a, a),
        y = (tonumber(pos.y) or 0) + self:random_between(-a, a),
        z = tonumber(pos.z) or 0,
    }
end

return Humanization
