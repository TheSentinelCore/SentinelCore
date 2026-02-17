local BlackspotManager = {}
BlackspotManager.__index = BlackspotManager
local vec3 = require("common/geometry/vector_3")

local DATA_FOLDER = "grindbuddy"
local DATA_FILE = "grindbuddy/blackspots.csv"

local function now_time()
    return core.time()
end

local function to_number_or_nil(v)
    local n = tonumber(v)
    if not n then
        return nil
    end
    return n
end

local function split_csv_line(line)
    local cols = {}
    local from = 1
    while true do
        local i = string.find(line, ",", from, true)
        if not i then
            cols[#cols + 1] = string.sub(line, from)
            break
        end
        cols[#cols + 1] = string.sub(line, from, i - 1)
        from = i + 1
    end
    return cols
end

local function sanitize_reason(reason)
    if type(reason) ~= "string" or reason == "" then
        return "unknown"
    end
    return reason:gsub(",", ";"):gsub("[\r\n]", " ")
end

local function copy_vec3(pos)
    return vec3.new(pos.x, pos.y, pos.z)
end

function BlackspotManager:new(config)
    local instance = setmetatable({}, BlackspotManager)
    instance._spots = {}
    instance._config = {
        default_radius = (config and config.default_radius) or 10.0,
        max_entries = (config and config.max_entries) or 400,
    }
    return instance
end

function BlackspotManager:load()
    core.create_data_folder(DATA_FOLDER)

    local raw = core.read_data_file(DATA_FILE)
    if not raw or raw == "" then
        core.create_data_file(DATA_FILE)
        return
    end

    local spots = {}
    for line in raw:gmatch("[^\r\n]+") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local cols = split_csv_line(line)
            if #cols >= 8 then
                local x = to_number_or_nil(cols[1])
                local y = to_number_or_nil(cols[2])
                local z = to_number_or_nil(cols[3])
                local map_id = to_number_or_nil(cols[4])
                local radius = to_number_or_nil(cols[5]) or self._config.default_radius
                local created_at = to_number_or_nil(cols[6]) or 0
                local expires_at = to_number_or_nil(cols[7])
                local reason = cols[8] or "unknown"

                if x and y and z and map_id then
                    spots[#spots + 1] = {
                        pos = vec3.new(x, y, z),
                        map_id = map_id,
                        radius = radius,
                        created_at = created_at,
                        expires_at = expires_at,
                        reason = reason,
                    }
                end
            end
        end
    end

    self._spots = spots
    self:prune_expired(now_time())
end

function BlackspotManager:save()
    core.create_data_folder(DATA_FOLDER)
    core.create_data_file(DATA_FILE)

    local lines = {
        "# x,y,z,map_id,radius,created_at,expires_at,reason",
    }

    for _, spot in ipairs(self._spots) do
        lines[#lines + 1] = string.format(
            "%.3f,%.3f,%.3f,%d,%.2f,%.3f,%s,%s",
            spot.pos.x,
            spot.pos.y,
            spot.pos.z,
            spot.map_id,
            spot.radius,
            spot.created_at or 0,
            spot.expires_at and string.format("%.3f", spot.expires_at) or "",
            sanitize_reason(spot.reason)
        )
    end

    core.write_data_file(DATA_FILE, table.concat(lines, "\n"))
end

function BlackspotManager:prune_expired(now)
    local kept = {}
    for _, spot in ipairs(self._spots) do
        local expires_at = spot.expires_at
        if not expires_at or expires_at <= 0 or expires_at > now then
            kept[#kept + 1] = spot
        end
    end
    self._spots = kept
end

function BlackspotManager:add(pos, map_id, radius, reason, ttl)
    if not pos or not map_id then
        return false
    end

    local now = now_time()
    self:prune_expired(now)

    local r = tonumber(radius) or self._config.default_radius
    local expires_at = nil
    if ttl and ttl > 0 then
        expires_at = now + ttl
    end

    self._spots[#self._spots + 1] = {
        pos = copy_vec3(pos),
        map_id = map_id,
        radius = r,
        created_at = now,
        expires_at = expires_at,
        reason = sanitize_reason(reason),
    }

    local max_entries = self._config.max_entries
    if #self._spots > max_entries then
        local drop = #self._spots - max_entries
        for _ = 1, drop do
            table.remove(self._spots, 1)
        end
    end

    self:save()
    return true
end

function BlackspotManager:is_blackspotted(pos, map_id)
    if not pos or not map_id then
        return false
    end

    local now = now_time()
    self:prune_expired(now)

    for _, spot in ipairs(self._spots) do
        if spot.map_id == map_id and spot.pos and pos:dist_to(spot.pos) <= spot.radius then
            return true
        end
    end

    return false
end

function BlackspotManager:get_count()
    return #self._spots
end

return BlackspotManager
