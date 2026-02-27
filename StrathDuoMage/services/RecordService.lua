local RecordService = {}
RecordService.__index = RecordService

local function now_secs()
    if core and core.time then
        local ok, value = pcall(core.time)
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return os.time()
end

local function safe_method(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(obj[method], obj, ...)
    if ok then
        return value
    end
    return nil
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function copy_pos(pos)
    if type(pos) ~= "table" then
        return nil
    end
    local x = tonumber(pos.x)
    local y = tonumber(pos.y)
    local z = tonumber(pos.z)
    if not x or not y or not z then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function deep_copy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[deep_copy(k)] = deep_copy(x)
    end
    return out
end

local function read_text(path)
    if core and type(core.read_data_file) == "function" then
        local text = core.read_data_file(path)
        if text and text ~= "" then
            return text
        end
    end
    if io and io.open then
        local f = io.open(path, "r")
        if f then
            local text = f:read("*a")
            f:close()
            if text and text ~= "" then
                return text
            end
        end
    end
    return nil
end

local function write_text(path, text)
    if core and type(core.write_data_file) == "function" and type(core.create_data_file) == "function" then
        core.create_data_file(path)
        core.write_data_file(path, text)
        return true
    end
    if io and io.open then
        local f = io.open(path, "w")
        if f then
            f:write(text)
            f:close()
            return true
        end
    end
    return false
end

local function split_parent(path)
    local p = tostring(path or "")
    local idx = p:match("^.*()[/\\]")
    if idx then
        return string.sub(p, 1, idx - 1)
    end
    return nil
end

local function ensure_parent_folder(path)
    local folder = split_parent(path)
    if not folder or folder == "" then
        return
    end

    if core and type(core.create_data_folder) == "function" then
        local normalized = string.gsub(folder, "\\", "/")
        local parts = {}
        for part in string.gmatch(normalized, "[^/]+") do
            parts[#parts + 1] = part
        end
        local cur = ""
        for i = 1, #parts do
            if i > 1 then
                cur = cur .. "/"
            end
            cur = cur .. parts[i]
            pcall(core.create_data_folder, cur)
        end
    end
end

local function make_segment_id(index)
    return string.format("segment_%02d", tonumber(index) or 1)
end

local function to_rfc3339_utc(ts)
    local value = tonumber(ts) or 0
    if value <= 0 then
        value = os.time()
    end
    local utc = os.date("!*t", value)
    return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",
        tonumber(utc.year) or 1970,
        tonumber(utc.month) or 1,
        tonumber(utc.day) or 1,
        tonumber(utc.hour) or 0,
        tonumber(utc.min) or 0,
        tonumber(utc.sec) or 0)
end

---@class RecordService
function RecordService:new(bb, cfg, logger)
    local o = setmetatable({}, RecordService)
    o._bb = bb
    o._cfg = cfg or {}
    o._log = logger
    o._json_ok, o._json = pcall(require, "lib/JSON")
    o._active = false
    o._dirty = false
    o._profile = nil
    o._profile_path = nil
    o._session_id = nil
    o._segment_index = 1
    o._history = {}
    o._last_message = ""
    o._last_error = nil
    o._last_save_at = 0
    o._last_capture = nil
    o._session_started_at = nil
    o._session_map_id = nil
    return o
end

function RecordService:_record_cfg()
    return self._cfg.record or {}
end

function RecordService:_set_status(message, is_error)
    local msg = tostring(message or "")
    self._last_message = msg
    self._last_error = is_error and msg or nil
    self._bb:set("record.last_message", msg)
    self._bb:set("record.last_error", self._last_error)
end

function RecordService:_profile_or_new()
    if type(self._profile) == "table" then
        return self._profile
    end
    return {
        role = tostring(self._cfg.role or "leader"),
        profile = {
            name = "strath_duo_recorded",
        },
        route = {
            schema_version = "strath_route.v1",
            loop = true,
            segments = {},
        },
        record_meta = {
            recorder_version = "record.v1",
        },
    }
end

function RecordService:_ensure_route(profile)
    profile.route = profile.route or {}
    profile.route.schema_version = profile.route.schema_version or "strath_route.v1"
    profile.route.loop = profile.route.loop ~= false
    profile.route.segments = profile.route.segments or {}
    if type(profile.route.segments) ~= "table" then
        profile.route.segments = {}
    end
end

function RecordService:_ensure_record_meta(profile)
    profile.record_meta = profile.record_meta or {}
    if type(profile.record_meta) ~= "table" then
        profile.record_meta = {}
    end
    profile.record_meta.recorder_version = tostring(profile.record_meta.recorder_version or "record.v1")
end

function RecordService:_current_segment()
    if type(self._profile) ~= "table" then
        return nil
    end
    self:_ensure_route(self._profile)
    local segments = self._profile.route.segments
    local count = #segments
    if count <= 0 then
        return nil
    end
    if self._segment_index < 1 then
        self._segment_index = 1
    elseif self._segment_index > count then
        self._segment_index = count
    end
    return segments[self._segment_index]
end

function RecordService:_current_map_id()
    local player = self._bb:get("player.object")
    if not player and core and core.object_manager and core.object_manager.get_local_player then
        player = core.object_manager.get_local_player()
    end
    if not player then
        return nil
    end
    local map = tonumber(safe_method(player, "get_map_id"))
    if map and map > 0 then
        return map
    end
    map = tonumber(safe_method(player, "get_zone_id"))
    if map and map > 0 then
        return map
    end
    map = tonumber(safe_method(player, "get_area_id"))
    if map and map > 0 then
        return map
    end
    return nil
end

function RecordService:_validate_map_consistency()
    local current = self:_current_map_id()
    local locked = tonumber(self._session_map_id)
    if not locked or not current then
        return true
    end
    return tonumber(current) == locked
end

function RecordService:_player_position()
    local bb_pos = copy_pos(self._bb:get("player.position"))
    if bb_pos then
        return bb_pos
    end

    if core and core.object_manager and core.object_manager.get_local_player then
        local player = core.object_manager.get_local_player()
        local pos = copy_pos(safe_method(player, "get_position"))
        if pos then
            return pos
        end
    end
    return nil
end

function RecordService:_push_history(action)
    if type(action) ~= "table" then
        return
    end
    self._history[#self._history + 1] = action
end

function RecordService:_mark_dirty(message)
    self._dirty = true
    self._last_capture = now_secs()
    if type(self._profile) == "table" then
        self:_ensure_record_meta(self._profile)
        self._profile.record_meta.last_operation_at = to_rfc3339_utc(self._last_capture)
        self._profile.record_meta.last_operation = tostring(message or "")
    end
    self:_set_status(message, false)
end

function RecordService:_decode_profile(text)
    if not self._json_ok or not self._json or type(self._json.decode) ~= "function" then
        return nil, "JSON decoder unavailable"
    end
    local parsed, err = self._json.decode(text)
    if type(parsed) ~= "table" then
        return nil, tostring(err or "profile parse failed")
    end
    return parsed, nil
end

function RecordService:_encode_profile(profile)
    if not self._json_ok or not self._json or type(self._json.encode) ~= "function" then
        return nil, "JSON encoder unavailable"
    end
    local encoded = self._json.encode(profile, true)
    if type(encoded) ~= "string" or encoded == "" then
        return nil, "profile encode failed"
    end
    return encoded, nil
end

function RecordService:_ensure_default_segment()
    local profile = self:_profile_or_new()
    self:_ensure_route(profile)
    local segments = profile.route.segments
    if #segments == 0 then
        segments[1] = {
            id = make_segment_id(1),
            focus_radius = tonumber(self:_record_cfg().default_focus_radius) or 18.0,
            pull_points = {},
            blizzard = {
                strategy = "cluster_centroid",
                clamp_to_lane = true,
            },
        }
        self._segment_index = 1
        self._profile = profile
        self:_mark_dirty("Created default segment")
    end
end

---@param path string
---@return boolean
---@return string|nil
function RecordService:load_profile(path)
    local profile_path = tostring(path or "")
    if profile_path == "" then
        return false, "profile path required"
    end

    local text = read_text(profile_path)
    local profile = nil
    local err = nil
    local fallback_reason = nil
    if text and text ~= "" then
        profile, err = self:_decode_profile(text)
        if not profile then
            fallback_reason = tostring(err or "unknown parse failure")
            profile = self:_profile_or_new()
        end
    else
        profile = self:_profile_or_new()
        fallback_reason = "profile file missing"
    end

    self:_ensure_route(profile)
    self:_ensure_record_meta(profile)
    self._profile = profile
    self._profile_path = profile_path
    self._segment_index = 1
    self:_ensure_default_segment()
    self._dirty = fallback_reason ~= nil
    self._history = {}
    if fallback_reason then
        self:_set_status("Profile fallback active: " .. fallback_reason .. " (" .. profile_path .. ")", false)
    else
        self:_set_status("Profile loaded: " .. profile_path, false)
    end
    return true, nil
end

---@param path? string
---@return boolean
---@return string|nil
function RecordService:save_profile(path)
    local profile = self:_profile_or_new()
    self:_ensure_route(profile)
    self:_ensure_record_meta(profile)
    profile.record_meta.updated_at = to_rfc3339_utc(now_secs())
    profile.record_meta.last_saved_session_id = self._session_id
    if type(profile.profile) ~= "table" then
        profile.profile = {}
    end
    profile.profile.updated_at = profile.record_meta.updated_at
    local out_path = tostring(path or self._profile_path or self:_record_cfg().default_profile_path or "")
    if out_path == "" then
        return false, "save path required"
    end

    local encoded, err = self:_encode_profile(profile)
    if not encoded then
        self:_set_status("Save failed: " .. tostring(err), true)
        return false, err
    end

    ensure_parent_folder(out_path)
    if not write_text(out_path, encoded) then
        self:_set_status("Save failed: write error", true)
        return false, "write error"
    end

    self._profile = profile
    self._profile_path = out_path
    self._dirty = false
    self._last_save_at = now_secs()
    self:_set_status("Profile saved: " .. out_path, false)
    return true, nil
end

---@param path? string
---@return boolean
---@return string|nil
function RecordService:start(path)
    if self._active then
        return true, nil
    end

    local profile_path = tostring(path or self._profile_path or self:_record_cfg().default_profile_path or "")
    if profile_path == "" then
        profile_path = "StrathDuoMage/profiles/strath_duo_default.json"
    end

    local ok, err = self:load_profile(profile_path)
    if not ok then
        return false, err
    end

    self._active = true
    self._session_id = tostring(math.floor(now_secs() * 1000)) .. "-" .. tostring(math.random(1000, 9999))
    self._session_started_at = now_secs()
    self._session_map_id = self:_current_map_id()
    self._last_capture = nil
    self:_ensure_record_meta(self._profile)
    self._profile.record_meta.active_session_id = self._session_id
    self._profile.record_meta.active_session_started_at = to_rfc3339_utc(self._session_started_at)
    self._profile.record_meta.active_session_map_id = self._session_map_id
    self:_set_status("Record mode active", false)
    return true, nil
end

---@param save_changes boolean
---@return boolean
---@return string|nil
function RecordService:stop(save_changes)
    if not self._active then
        return true, nil
    end

    if save_changes and self._dirty then
        local ok, err = self:save_profile(self._profile_path)
        if not ok then
            return false, err
        end
    end

    if type(self._profile) == "table" then
        self:_ensure_record_meta(self._profile)
        self._profile.record_meta.active_session_id = nil
        self._profile.record_meta.active_session_started_at = nil
        self._profile.record_meta.active_session_map_id = nil
        self._profile.record_meta.last_session_id = self._session_id
        self._profile.record_meta.last_session_ended_at = to_rfc3339_utc(now_secs())
    end

    self._active = false
    self._session_id = nil
    self._session_started_at = nil
    self._session_map_id = nil
    self._history = {}
    self:_set_status(save_changes and "Record mode stopped and saved" or "Record mode stopped", false)
    return true, nil
end

---@return boolean
function RecordService:is_active()
    return self._active == true
end

---@return table
function RecordService:get_state()
    local segment = self:_current_segment()
    local segments = {}
    local pull_count = 0
    local seg_id = nil

    if type(self._profile) == "table" and type(self._profile.route) == "table" and type(self._profile.route.segments) == "table" then
        segments = self._profile.route.segments
    end

    if type(segment) == "table" then
        pull_count = type(segment.pull_points) == "table" and #segment.pull_points or 0
        seg_id = tostring(segment.id or "")
    end

    return {
        active = self._active == true,
        dirty = self._dirty == true,
        profile_path = tostring(self._profile_path or ""),
        session_id = self._session_id,
        session_map_id = self._session_map_id,
        segment_index = self._segment_index,
        segment_count = #segments,
        segment_id = seg_id,
        pull_point_count = pull_count,
        last_message = self._last_message,
        last_error = self._last_error,
        last_capture_at = self._last_capture,
        last_save_at = self._last_save_at,
    }
end

function RecordService:_sanitize_point(point, focus_radius)
    local pos = copy_pos(point)
    if not pos then
        return nil
    end
    local out = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
    }
    if tonumber(focus_radius) then
        out.focus_radius = tonumber(focus_radius)
    end
    out.captured_at = to_rfc3339_utc(now_secs())
    return out
end

function RecordService:new_segment(id)
    if type(self._profile) ~= "table" then
        return false, "profile not loaded"
    end

    self:_ensure_route(self._profile)
    local segments = self._profile.route.segments
    local next_idx = #segments + 1
    local sid = tostring(id or "")
    if sid == "" then
        sid = make_segment_id(next_idx)
    end

    local segment = {
        id = sid,
        focus_radius = tonumber(self:_record_cfg().default_focus_radius) or 18.0,
        pull_points = {},
        blizzard = {
            strategy = "cluster_centroid",
            clamp_to_lane = true,
        },
    }
    segments[next_idx] = segment
    self._segment_index = next_idx
    self:_push_history({
        type = "add_segment",
        index = next_idx,
    })
    self:_mark_dirty("Added segment " .. sid)
    return true, sid
end

function RecordService:next_segment()
    if type(self._profile) ~= "table" then
        return false, "profile not loaded"
    end
    self:_ensure_route(self._profile)
    local segments = self._profile.route.segments
    if #segments <= 0 then
        return self:new_segment()
    end
    if self._segment_index < #segments then
        self._segment_index = self._segment_index + 1
        self:_set_status("Selected segment " .. tostring(segments[self._segment_index].id or self._segment_index), false)
        return true, nil
    end
    return self:new_segment()
end

function RecordService:prev_segment()
    if type(self._profile) ~= "table" then
        return false, "profile not loaded"
    end
    self:_ensure_route(self._profile)
    if self._segment_index > 1 then
        self._segment_index = self._segment_index - 1
    end
    local seg = self:_current_segment()
    self:_set_status("Selected segment " .. tostring(seg and seg.id or self._segment_index), false)
    return true, nil
end

function RecordService:clear_pull_points()
    local segment = self:_current_segment()
    if type(segment) ~= "table" then
        return false, "segment unavailable"
    end
    local old = deep_copy(segment.pull_points or {})
    segment.pull_points = {}
    self:_push_history({
        type = "set_pull_points",
        segment_index = self._segment_index,
        old = old,
    })
    self:_mark_dirty("Cleared pull points")
    return true, nil
end

function RecordService:capture_pull_point(focus_radius)
    if not self._active then
        return false, "record mode inactive"
    end

    local segment = self:_current_segment()
    if type(segment) ~= "table" then
        return false, "segment unavailable"
    end
    segment.pull_points = segment.pull_points or {}

    local pos = self:_player_position()
    if not pos then
        return false, "player position unavailable"
    end
    if not self:_validate_map_consistency() then
        return false, "map mismatch: moved outside recording map"
    end

    local min_spacing = tonumber(self:_record_cfg().min_point_spacing) or 1.5
    local last = segment.pull_points[#segment.pull_points]
    if last and distance(last, pos) < min_spacing then
        return false, "point too close to previous capture"
    end

    local point = self:_sanitize_point(pos, focus_radius)
    if not point then
        return false, "invalid point"
    end
    segment.pull_points[#segment.pull_points + 1] = point
    self:_push_history({
        type = "append_pull_point",
        segment_index = self._segment_index,
        point = deep_copy(point),
    })
    self:_mark_dirty(string.format("Captured pull point #%d", #segment.pull_points))
    return true, deep_copy(point)
end

local function assign_blizzard_table(segment)
    segment.blizzard = segment.blizzard or {}
    if type(segment.blizzard) ~= "table" then
        segment.blizzard = {}
    end
end

function RecordService:capture_gather_anchor()
    if not self._active then
        return false, "record mode inactive"
    end
    local segment = self:_current_segment()
    if type(segment) ~= "table" then
        return false, "segment unavailable"
    end
    local pos = self:_player_position()
    if not pos then
        return false, "player position unavailable"
    end
    if not self:_validate_map_consistency() then
        return false, "map mismatch: moved outside recording map"
    end
    pos.captured_at = to_rfc3339_utc(now_secs())

    local prev = deep_copy(segment.gather_anchor)
    segment.gather_anchor = pos
    self:_push_history({
        type = "set_field",
        segment_index = self._segment_index,
        field = "gather_anchor",
        old = prev,
    })
    self:_mark_dirty("Captured gather anchor")
    return true, deep_copy(pos)
end

function RecordService:capture_lane_start()
    if not self._active then
        return false, "record mode inactive"
    end
    local segment = self:_current_segment()
    if type(segment) ~= "table" then
        return false, "segment unavailable"
    end
    local pos = self:_player_position()
    if not pos then
        return false, "player position unavailable"
    end
    if not self:_validate_map_consistency() then
        return false, "map mismatch: moved outside recording map"
    end
    pos.captured_at = to_rfc3339_utc(now_secs())
    assign_blizzard_table(segment)
    local prev = deep_copy(segment.blizzard.lane_start)
    segment.blizzard.lane_start = pos
    self:_push_history({
        type = "set_nested_field",
        segment_index = self._segment_index,
        parent = "blizzard",
        field = "lane_start",
        old = prev,
    })
    self:_mark_dirty("Captured lane start")
    return true, deep_copy(pos)
end

function RecordService:capture_lane_end()
    if not self._active then
        return false, "record mode inactive"
    end
    local segment = self:_current_segment()
    if type(segment) ~= "table" then
        return false, "segment unavailable"
    end
    local pos = self:_player_position()
    if not pos then
        return false, "player position unavailable"
    end
    if not self:_validate_map_consistency() then
        return false, "map mismatch: moved outside recording map"
    end
    pos.captured_at = to_rfc3339_utc(now_secs())
    assign_blizzard_table(segment)
    local prev = deep_copy(segment.blizzard.lane_end)
    segment.blizzard.lane_end = pos
    self:_push_history({
        type = "set_nested_field",
        segment_index = self._segment_index,
        parent = "blizzard",
        field = "lane_end",
        old = prev,
    })
    self:_mark_dirty("Captured lane end")
    return true, deep_copy(pos)
end

function RecordService:toggle_strategy()
    local segment = self:_current_segment()
    if type(segment) ~= "table" then
        return false, "segment unavailable"
    end
    assign_blizzard_table(segment)
    local prev = tostring(segment.blizzard.strategy or "cluster_centroid")
    local next_value = (prev == "cluster_centroid") and "lane_midpoint" or "cluster_centroid"
    segment.blizzard.strategy = next_value
    self:_push_history({
        type = "set_nested_field",
        segment_index = self._segment_index,
        parent = "blizzard",
        field = "strategy",
        old = prev,
    })
    self:_mark_dirty("Blizzard strategy: " .. next_value)
    return true, next_value
end

function RecordService:_resolve_segment_by_index(index)
    if type(self._profile) ~= "table" then
        return nil
    end
    self:_ensure_route(self._profile)
    local segments = self._profile.route.segments
    local idx = tonumber(index) or 0
    if idx < 1 or idx > #segments then
        return nil
    end
    return segments[idx]
end

function RecordService:undo_last()
    local action = self._history[#self._history]
    if type(action) ~= "table" then
        return false, "nothing to undo"
    end
    self._history[#self._history] = nil

    if action.type == "append_pull_point" then
        local segment = self:_resolve_segment_by_index(action.segment_index)
        if segment and type(segment.pull_points) == "table" and #segment.pull_points > 0 then
            segment.pull_points[#segment.pull_points] = nil
        end
    elseif action.type == "set_field" then
        local segment = self:_resolve_segment_by_index(action.segment_index)
        if segment then
            segment[action.field] = deep_copy(action.old)
        end
    elseif action.type == "set_nested_field" then
        local segment = self:_resolve_segment_by_index(action.segment_index)
        if segment then
            segment[action.parent] = segment[action.parent] or {}
            segment[action.parent][action.field] = deep_copy(action.old)
        end
    elseif action.type == "set_pull_points" then
        local segment = self:_resolve_segment_by_index(action.segment_index)
        if segment then
            segment.pull_points = deep_copy(action.old) or {}
        end
    elseif action.type == "add_segment" then
        local segments = self._profile and self._profile.route and self._profile.route.segments
        if type(segments) == "table" and tonumber(action.index) == #segments then
            segments[#segments] = nil
            if self._segment_index > #segments then
                self._segment_index = math.max(1, #segments)
            end
        end
    end

    self:_mark_dirty("Undid last record action")
    return true, nil
end

function RecordService:_publish_state()
    local state = self:get_state()
    self._bb:set("record.state", state)
    self._bb:set("record.active", state.active == true)
end

---@param now number
function RecordService:update(now)
    if self._active and self._dirty then
        local autosave_secs = tonumber(self:_record_cfg().autosave_secs) or 0
        if autosave_secs > 0 and ((tonumber(now) or 0) - (tonumber(self._last_save_at) or 0)) >= autosave_secs then
            self:save_profile(self._profile_path)
        end
    end
    self:_publish_state()
end

return RecordService
