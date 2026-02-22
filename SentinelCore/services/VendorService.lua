local Helpers = require("lib/Helpers")
local Defaults = require("core/Defaults")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")
local FactionResolver = require("lib/FactionResolver")

---@class VendorService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _nav NavigationAdapter
---@field private _world WorldDataAdapter
---@field private _inventory InventoryService
---@field private _cfg table
---@field private _cache table
---@field private _state string
---@field private _last_error string|nil
---@field private _ctx table|nil
---@field private _candidates table[]
---@field private _reachable table[]
---@field private _started_at number
---@field private _interaction_started_at number
---@field private _active_candidate table|nil
---@field private _return_started_at number
---@field private _return_pending boolean
local VendorService = {}
VendorService.__index = VendorService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param navigation NavigationAdapter
---@param world_data WorldDataAdapter
---@param inventory InventoryService
---@param cfg table
---@param cache table
---@return VendorService
function VendorService:new(event_bus, blackboard, navigation, world_data, inventory, cfg, cache)
    local o = setmetatable({}, VendorService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav = navigation
    o._world = world_data
    o._inventory = inventory
    o._cfg = cfg or {}
    o._cache = cache and Defaults.copy(cache) or Defaults.copy(Defaults.vendor_cache)
    o._state = "idle"
    o._last_error = nil
    o._ctx = nil
    o._candidates = {}
    o._reachable = {}
    o._started_at = 0
    o._interaction_started_at = 0
    o._active_candidate = nil
    o._return_started_at = 0
    o._return_pending = false
    return o
end

---@return boolean
function VendorService:is_active()
    return self._state ~= "idle" and self._state ~= "completed" and self._state ~= "failed"
end

---@return string
function VendorService:get_state()
    return self._state
end

---@return string|nil
function VendorService:get_last_error()
    return self._last_error
end

---@return table
function VendorService:get_cache()
    return Defaults.copy(self._cache)
end

---@param cache table
function VendorService:set_cache(cache)
    self._cache = Defaults.copy(cache)
end

---@private
---@param vendor_id number
---@param map_id number
---@return table|nil
function VendorService:_cache_entry(vendor_id, map_id)
    local entries = self._cache.entries or {}
    for i = 1, #entries do
        local entry = entries[i]
        if tonumber(entry.vendor_id) == vendor_id and tonumber(entry.canonical_map_id) == map_id then
            return entry
        end
    end
    return nil
end

---@private
---@param vendor table
---@param result string
---@param path_cost number|nil
function VendorService:_update_cache(vendor, result, path_cost)
    local now = math.floor((core and core.time and core.time()) or 0)
    local vendor_id = tonumber(vendor.vendor_id) or 0
    local map_id = tonumber(vendor.map_id) or tonumber(self._ctx and self._ctx.map_id) or 0

    if not self._cache.entries then
        self._cache.entries = {}
    end

    local entry = self:_cache_entry(vendor_id, map_id)
    if not entry then
        entry = {
            vendor_id = vendor_id,
            canonical_map_id = map_id,
            last_result = "",
            failure_count = 0,
            blacklist_until_unix = 0,
            last_path_cost = 0,
            last_seen_unix = now,
        }
        self._cache.entries[#self._cache.entries + 1] = entry
    end

    entry.last_result = result
    entry.last_seen_unix = now
    if path_cost then
        entry.last_path_cost = path_cost
    end

    if result == "ok" then
        entry.failure_count = 0
        entry.blacklist_until_unix = 0
    else
        entry.failure_count = (tonumber(entry.failure_count) or 0) + 1
        local ttl = tonumber(self._cfg.candidate_blacklist_secs) or 90
        entry.blacklist_until_unix = now + ttl
    end

    local cap = tonumber(self._cfg.candidate_cache_max_entries) or 500
    if #self._cache.entries > cap then
        table.sort(self._cache.entries, function(a, b)
            return (tonumber(a.last_seen_unix) or 0) > (tonumber(b.last_seen_unix) or 0)
        end)
        while #self._cache.entries > cap do
            table.remove(self._cache.entries)
        end
    end

    self._cache.updated_at_unix = now
end

---@private
---@param vendor table
---@return boolean
function VendorService:_is_blacklisted(vendor)
    local now = math.floor((core and core.time and core.time()) or 0)
    local entry = self:_cache_entry(tonumber(vendor.vendor_id) or 0, tonumber(vendor.map_id) or 0)
    if not entry then
        return false
    end
    return (tonumber(entry.blacklist_until_unix) or 0) > now
end

---@private
---@param vendor table
---@return boolean
---@return string|nil
function VendorService:_candidate_allowed(vendor)
    if not vendor then
        return false, ErrorCodes.VENDOR_FETCH_FAILED
    end

    local vendor_map = tonumber(vendor.map_id)
    local ctx_map = tonumber(self._ctx and self._ctx.map_id)
    if vendor_map ~= ctx_map then
        return false, ErrorCodes.VENDOR_SAME_MAP_REQUIRED
    end

    if self._cfg.require_sell == true and vendor.can_sell == false then
        return false, ErrorCodes.VENDOR_CAPABILITY_MISSING
    end

    if self._cfg.require_repair == true and vendor.can_repair == false then
        return false, ErrorCodes.VENDOR_CAPABILITY_MISSING
    end

    local player_faction = tonumber(self._blackboard:get("player.faction_id", 0))
    local player_team = FactionResolver.resolve_team(player_faction)
    local faction_mask = tonumber(vendor.faction_mask or 0)
    if faction_mask ~= 0 then
        local team_allowed = FactionResolver.vendor_mask_allows_team(faction_mask, player_team)
        if team_allowed == false then
            return false, ErrorCodes.VENDOR_FACTION_MISMATCH
        end

        -- Backward compatibility fallback if team resolution is unavailable.
        if team_allowed == nil and player_faction ~= 0 then
            local bitlib = bit32 or bit
            if bitlib and bitlib.band and bitlib.band(faction_mask, player_faction) == 0 then
                return false, ErrorCodes.VENDOR_FACTION_MISMATCH
            end
        end
    end

    if self:_is_blacklisted(vendor) then
        return false, ErrorCodes.VENDOR_UNREACHABLE
    end

    return true, nil
end

---@private
---@param vendors table[]
---@return table[]
function VendorService:_filter_candidates(vendors)
    local filtered = {}
    for i = 1, #vendors do
        local vendor = vendors[i]
        local ok, _ = self:_candidate_allowed(vendor)
        if ok then
            filtered[#filtered + 1] = vendor
        end
    end
    return filtered
end

---@private
---@param callback fun(ok: boolean, error_code: string|nil)
function VendorService:_rank_candidates(callback)
    self._reachable = {}

    local player_pos = self._blackboard:get("player.position")
    if not player_pos then
        callback(false, ErrorCodes.CTX_UNRESOLVED)
        return
    end

    local index = 1
    local function process_next()
        if index > #self._candidates then
            if #self._reachable == 0 then
                callback(false, ErrorCodes.VENDOR_NONE_VIABLE)
                return
            end

            table.sort(self._reachable, function(a, b)
                return (a.path_cost or math.huge) < (b.path_cost or math.huge)
            end)
            callback(true, nil)
            return
        end

        local vendor = self._candidates[index]
        index = index + 1

        local pos = {
            x = tonumber(vendor.x) or 0,
            y = tonumber(vendor.y) or 0,
            z = tonumber(vendor.z) or 0,
        }

        self._nav:estimate_path_cost(player_pos, pos, function(ok, cost)
            if ok then
                vendor.path_cost = cost or math.huge
                self._reachable[#self._reachable + 1] = vendor
            else
                self:_update_cache(vendor, "unreachable", nil)
            end
            process_next()
        end)
    end

    process_next()
end

---@private
---@param vendor table
---@param callback fun(ok: boolean, error_code: string|nil)
function VendorService:_travel_to_vendor(vendor, callback)
    local dest = {
        x = tonumber(vendor.x) or 0,
        y = tonumber(vendor.y) or 0,
        z = tonumber(vendor.z) or 0,
    }

    self._nav:move_to(dest, function(ok, reason)
        if not ok then
            self:_update_cache(vendor, "move_failed", nil)
            callback(false, reason or ErrorCodes.VENDOR_UNREACHABLE)
            return
        end

        callback(true, nil)
    end)
end

---@private
---@param now number
---@param returned_to_anchor boolean
function VendorService:_complete_vendor(now, returned_to_anchor)
    self._state = "completed"
    self._return_pending = false
    self._return_started_at = 0
    self:_update_cache(self._active_candidate, "ok", self._active_candidate and self._active_candidate.path_cost or nil)

    self._event_bus:emit(Events.VENDOR_COMPLETED, {
        timestamp = now,
        vendor_id = self._active_candidate and self._active_candidate.vendor_id,
        path_cost = self._active_candidate and self._active_candidate.path_cost,
        returned_to_anchor = returned_to_anchor == true,
    })
end

---@private
---@param vendor table
---@return game_object|nil
function VendorService:_find_vendor_object(vendor)
    local objects = core and core.object_manager and core.object_manager.get_visible_objects and core.object_manager.get_visible_objects() or {}
    local target_npc_id = tonumber(vendor.npc_id) or 0

    local best = nil
    local best_dist = math.huge
    local player_pos = self._blackboard:get("player.position")

    for i = 1, #objects do
        local obj = objects[i]
        if obj and obj.is_valid and obj:is_valid() and obj.is_unit and obj:is_unit() then
            local npc_id = tonumber(obj.get_npc_id and obj:get_npc_id() or 0)
            if npc_id == target_npc_id then
                local dist = Helpers.distance_3d(player_pos, obj:get_position())
                if dist < best_dist then
                    best = obj
                    best_dist = dist
                end
            end
        end
    end

    return best
end

---@param canonical_ctx table
---@return boolean
---@return string|nil
function VendorService:start(canonical_ctx)
    if not canonical_ctx or not canonical_ctx.map_id then
        self._state = "failed"
        self._last_error = ErrorCodes.CTX_UNRESOLVED
        return false, self._last_error
    end

    self._ctx = canonical_ctx
    self._state = "fetching"
    self._last_error = nil
    self._candidates = {}
    self._reachable = {}
    self._active_candidate = nil
    self._started_at = (core and core.time and core.time()) or 0
    self._interaction_started_at = 0
    self._return_started_at = 0
    self._return_pending = false

    self._event_bus:emit(Events.VENDOR_STARTED, {
        timestamp = self._started_at,
        map_id = canonical_ctx.map_id,
        zone_id = canonical_ctx.zone_id,
        area_id = canonical_ctx.area_id,
    })

    local request_opts = {
        radius = tonumber(self._cfg.search_radius) or 250,
        require_sell = self._cfg.require_sell == true,
        require_repair = self._cfg.require_repair == true,
        faction = FactionResolver.resolve_team(self._blackboard:get("player.faction_id")),
        position = self._blackboard:get("player.position"),
    }

    self._world:get_nearby_vendors(canonical_ctx, request_opts, function(ok, vendors, error_code)
        if self._state ~= "fetching" then
            return
        end

        if not ok then
            self._state = "failed"
            self._last_error = error_code or ErrorCodes.VENDOR_FETCH_FAILED
            self._event_bus:emit(Events.VENDOR_FAILED, {
                timestamp = (core and core.time and core.time()) or 0,
                error_code = self._last_error,
            })
            return
        end

        self._candidates = self:_filter_candidates(vendors)
        if #self._candidates == 0 then
            self._state = "failed"
            self._last_error = ErrorCodes.VENDOR_NONE_VIABLE
            self._event_bus:emit(Events.VENDOR_FAILED, {
                timestamp = (core and core.time and core.time()) or 0,
                error_code = self._last_error,
                candidates = #vendors,
            })
            return
        end

        self._state = "ranking"
        self:_rank_candidates(function(rank_ok, rank_error)
            if self._state ~= "ranking" then
                return
            end

            if not rank_ok then
                self._state = "failed"
                self._last_error = rank_error or ErrorCodes.VENDOR_NONE_VIABLE
                self._event_bus:emit(Events.VENDOR_FAILED, {
                    timestamp = (core and core.time and core.time()) or 0,
                    error_code = self._last_error,
                })
                return
            end

            self._active_candidate = self._reachable[1]
            self._state = "travel"
            self:_travel_to_vendor(self._active_candidate, function(travel_ok, travel_error)
                if self._state ~= "travel" then
                    return
                end

                if not travel_ok then
                    self._state = "failed"
                    self._last_error = travel_error or ErrorCodes.VENDOR_UNREACHABLE
                    self._event_bus:emit(Events.VENDOR_FAILED, {
                        timestamp = (core and core.time and core.time()) or 0,
                        error_code = self._last_error,
                    })
                    return
                end

                self._state = "interact"
                self._interaction_started_at = (core and core.time and core.time()) or 0
            end)
        end)
    end)

    return true, nil
end

---@return boolean
---@return string|nil
function VendorService:update()
    if self._state == "idle" or self._state == "completed" then
        return true, nil
    end

    if self._state == "failed" then
        return false, self._last_error
    end

    if self._state == "returning" then
        local now = (core and core.time and core.time()) or 0
        local timeout = tonumber(self._cfg.return_timeout) or 25
        if self._return_started_at > 0 and (now - self._return_started_at) > timeout then
            self._state = "failed"
            self._last_error = ErrorCodes.VENDOR_UNREACHABLE
            if self._active_candidate then
                self:_update_cache(self._active_candidate, "return_timeout", self._active_candidate.path_cost)
            end
            self._event_bus:emit(Events.VENDOR_FAILED, {
                timestamp = now,
                error_code = self._last_error,
            })
            return false, self._last_error
        end
        return true, nil
    end

    if self._state ~= "interact" then
        return true, nil
    end

    local now = (core and core.time and core.time()) or 0
    local timeout = tonumber(self._cfg.interaction_timeout) or 10

    if now - self._interaction_started_at > timeout then
        self._state = "failed"
        self._last_error = ErrorCodes.VENDOR_INTERACTION_TIMEOUT
        if self._active_candidate then
            self:_update_cache(self._active_candidate, "interaction_timeout", self._active_candidate.path_cost)
        end
        self._event_bus:emit(Events.VENDOR_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end

    local vendor_obj = self._active_candidate and self:_find_vendor_object(self._active_candidate) or nil
    if not vendor_obj then
        return true, nil
    end

    if core and core.input and core.input.interact_with_object then
        core.input.interact_with_object(vendor_obj)
    elseif core and core.input and core.input.use_object then
        core.input.use_object(vendor_obj)
    end

    local return_enabled = self._cfg.return_to_anchor ~= false
    local anchor = self._blackboard:get("core.mode_anchor") or self._blackboard:get("grind.anchor")
    if return_enabled and anchor then
        self._state = "returning"
        self._return_started_at = now
        self._return_pending = true

        local return_dest = {
            x = tonumber(anchor.x) or 0,
            y = tonumber(anchor.y) or 0,
            z = tonumber(anchor.z) or 0,
        }

        self._nav:move_to(return_dest, function(ok, reason)
            self._return_pending = false
            if self._state ~= "returning" then
                return
            end

            if not ok then
                self._state = "failed"
                self._last_error = reason or ErrorCodes.VENDOR_UNREACHABLE
                if self._active_candidate then
                    self:_update_cache(self._active_candidate, "return_failed", self._active_candidate.path_cost)
                end
                self._event_bus:emit(Events.VENDOR_FAILED, {
                    timestamp = (core and core.time and core.time()) or 0,
                    error_code = self._last_error,
                })
                return
            end

            self:_complete_vendor((core and core.time and core.time()) or 0, true)
        end)
        return true, nil
    end

    -- Selling/repair operations are bounded by available Sylvannas APIs.
    -- We treat successful interaction as completion in this phase.
    self:_complete_vendor(now, false)

    return true, nil
end

function VendorService:reset()
    self._state = "idle"
    self._last_error = nil
    self._ctx = nil
    self._candidates = {}
    self._reachable = {}
    self._active_candidate = nil
    self._return_started_at = 0
    self._return_pending = false
end

return VendorService
