local MountManager = {}
MountManager.__index = MountManager

local function num(value)
    return tonumber(value) or 0
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function safe_call(owner, method, ...)
    if not owner or type(owner[method]) ~= "function" then
        return false, nil
    end
    local fn = owner[method]
    local ok, value = pcall(fn, owner, ...)
    if ok then
        return true, value
    end
    return pcall(fn, ...)
end

local function invoke_bool(owner, method, ...)
    if not owner or type(owner[method]) ~= "function" then
        return false
    end
    local fn = owner[method]
    local ok, value = pcall(fn, ...)
    if not ok then
        ok, value = pcall(fn, owner, ...)
    end
    if not ok then
        return false
    end
    return value == nil or value == true or value == 1
end

local function is_true(value)
    return value == true or value == 1
end

local function is_player_unit(unit)
    if not unit then
        return false
    end
    local ok, result = safe_call(unit, "is_player")
    if ok then
        return result == true
    end
    return false
end

function MountManager:new(event_bus, blackboard, nav_adapter)
    local o = setmetatable({}, MountManager)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav_adapter = nav_adapter
    local ok, unit_helper = pcall(require, "common/utility/unit_helper")
    o._unit_helper = ok and unit_helper or nil
    o._pending = false
    o._cast_dispatched = false
    o._settle_until_ms = 0
    o._confirm_until_ms = 0
    o._pending_since_ms = 0
    o._last_attempt_ms = 0
    o._state = "idle"
    return o
end

function MountManager:initialize()
    self:reset("initialize")
end

function MountManager:_set(key, value)
    self._blackboard:set(key, value)
end

function MountManager:_set_state(state, block_reason)
    self._state = state
    self:_set("bg.mount.state", state)
    self:_set("bg.mount.block_reason", block_reason or "")
    self:_set("bg.mount.pending", state == "mount_requested" or state == "mount_pending")
end

function MountManager:reset(reason)
    self._pending = false
    self._cast_dispatched = false
    self._settle_until_ms = 0
    self._confirm_until_ms = 0
    self._pending_since_ms = 0
    self:_set("bg.mount.enabled", self._blackboard:get("module.bg.auto_mount", true) == true)
    self:_set("bg.mount.block_reason", reason or "")
    self:_set("bg.mount.pending", false)
    self:_set("bg.mount.last_attempt_ok", nil)
    self:_set("bg.mount.last_attempt_method", nil)
    self:_set("bg.mount.selected_mount_id", nil)
    self:_set("bg.mount.selected_mount_spell_id", nil)
    self:_set("bg.mount.selected_mount_name", nil)
    self:_set("bg.mount.selected_mount_strategy", nil)
    self:_set("bg.mount.preferred_mount_id", num(self._blackboard:get("module.bg.preferred_mount_id", 184865)))
    self:_set("bg.mount.distance_to_target", 0)
    self:_set_state("idle", reason or "")
end

function MountManager:_player()
    return self._blackboard:get("player.object")
end

function MountManager:_now_ms()
    return num(self._blackboard:get("system.now_ms", 0))
end

function MountManager:_enemy_player_nearby(radius)
    local player_pos = self._blackboard:get("player.position")
    if not self._unit_helper or not player_pos or type(self._unit_helper.get_enemy_list_around) ~= "function" then
        return false
    end

    local ok, list = pcall(self._unit_helper.get_enemy_list_around, self._unit_helper, player_pos, radius, true, false)
    if not ok or type(list) ~= "table" then
        return false
    end

    for _, unit in ipairs(list) do
        if is_player_unit(unit) then
            return true
        end
    end
    return false
end

function MountManager:_dispatch_preferred_item(preferred_mount_id)
    if preferred_mount_id <= 0 then
        return false
    end
    if not core or not core.input or type(core.input.use_item) ~= "function" then
        return false
    end
    local ok = invoke_bool(core.input, "use_item", preferred_mount_id)
    self:_set("bg.mount.last_attempt_method", "use_item")
    self:_set("bg.mount.selected_mount_id", preferred_mount_id)
    self:_set("bg.mount.selected_mount_spell_id", nil)
    self:_set("bg.mount.selected_mount_name", "Reawakened Phase-Hunter")
    self:_set("bg.mount.selected_mount_strategy", "preferred_item")
    self:_set("bg.mount.last_attempt_ok", ok)
    return ok
end

function MountManager:_select_fallback_mount(preferred_epic)
    if not core or not core.spell_book or type(core.spell_book.get_mount_count) ~= "function" then
        return nil
    end

    local ok_count, count = safe_call(core.spell_book, "get_mount_count")
    count = ok_count and math.max(0, math.floor(num(count))) or 0
    if count <= 0 then
        return nil
    end

    local best = nil
    for index = 1, count do
        local ok_info, info = safe_call(core.spell_book, "get_mount_info", index)
        if ok_info and type(info) == "table" and info.is_usable ~= false then
            local score = 0
            if preferred_epic and num(info.mount_type) >= 2 then
                score = score + 100
            end
            if info.is_active == true then
                score = score + 5
            end
            score = score - (index * 0.001)
            if not best or score > best.score then
                best = {
                    score = score,
                    index = index,
                    spell_id = num(info.spell_id) > 0 and num(info.spell_id) or nil,
                    mount_id = num(info.mount_id) > 0 and num(info.mount_id) or nil,
                    name = tostring(info.mount_name or ""),
                }
            end
        end
    end

    return best
end

function MountManager:_dispatch_fallback_mount()
    if not core or not core.input or type(core.input.mount) ~= "function" then
        return false
    end

    local selected = self:_select_fallback_mount(self._blackboard:get("module.bg.mount_prefer_epic", true) == true)
    if not selected then
        self:_set("bg.mount.last_attempt_method", "mount_default")
        local ok = invoke_bool(core.input, "mount")
        self:_set("bg.mount.last_attempt_ok", ok)
        self:_set("bg.mount.selected_mount_id", nil)
        self:_set("bg.mount.selected_mount_spell_id", nil)
        self:_set("bg.mount.selected_mount_name", "default_mount")
        self:_set("bg.mount.selected_mount_strategy", "default")
        return ok
    end

    self:_set("bg.mount.selected_mount_id", selected.mount_id)
    self:_set("bg.mount.selected_mount_spell_id", selected.spell_id)
    self:_set("bg.mount.selected_mount_name", selected.name ~= "" and selected.name or "fallback_mount")
    self:_set("bg.mount.selected_mount_strategy", "spellbook_fallback")
    self:_set("bg.mount.last_attempt_method", "mount_index")

    local ok = invoke_bool(core.input, "mount", selected.index)
    if not ok and selected.index > 0 then
        ok = invoke_bool(core.input, "mount", selected.index - 1)
    end
    if not ok then
        ok = invoke_bool(core.input, "mount")
    end
    self:_set("bg.mount.last_attempt_ok", ok)
    return ok
end

function MountManager:_capture_hold_active(now_ms)
    local hold_until = num(self._blackboard:get("bg.capture_hold_until_ms", 0))
    return hold_until > now_ms
end

function MountManager:_eligible_block_reason(target_pos)
    local now_ms = self:_now_ms()
    local player = self:_player()
    if self._blackboard:get("module.bg.enabled", true) ~= true then
        return "bg_disabled"
    end
    if self._blackboard:get("module.bg.auto_mount", true) ~= true then
        return "auto_mount_disabled"
    end
    if self._blackboard:get("player.is_dead", false) == true then
        return "dead"
    end
    if self._blackboard:get("player.is_ghost", false) == true then
        return "ghost"
    end
    if self._blackboard:get("player.in_combat", false) == true then
        return "in_combat"
    end
    if self:_capture_hold_active(now_ms) then
        return "capture_hold"
    end
    if self._blackboard:get("module.bg.mount_require_outdoors", true) == true
        and self._blackboard:get("player.is_outdoors", true) == false then
        return "indoors"
    end
    if type(target_pos) ~= "table" then
        return "no_target"
    end
    if self._blackboard:get("bg.sensor.in_prep", false) == true then
        if self._blackboard:get("module.bg.pregame_mount_early", true) ~= true then
            return "pregame_mount_disabled"
        end
    end

    local threat_radius = num(self._blackboard:get("module.bg.player_threat_scan_radius", 35))
    if threat_radius > 0 and self:_enemy_player_nearby(threat_radius) then
        return "enemy_player_threat"
    end

    local target_distance = distance(self._blackboard:get("player.position"), target_pos)
    self:_set("bg.mount.distance_to_target", target_distance)
    if target_distance < num(self._blackboard:get("module.bg.mount_distance_threshold", 45)) then
        return "target_too_close"
    end

    local objective_center = self._blackboard:get("bg.objective_center")
    local objective_type = tostring(self._blackboard:get("bg.objective_type", ""))
    local capture_objective = objective_type == "GRAVEYARD"
        or objective_type == "TOWER"
        or objective_type == "NODE"
        or objective_type == "FLAG"
    if capture_objective and objective_center and distance(self._blackboard:get("player.position"), objective_center) <= num(self._blackboard:get("module.bg.capture_radius", 12)) then
        return "inside_capture_radius"
    end

    local ok_mounted, mounted = safe_call(player, "is_mounted")
    if ok_mounted and mounted == true then
        return "already_mounted"
    end

    return nil
end

function MountManager:_attempt_mount(preferred_mount_id)
    local dispatched = self:_dispatch_preferred_item(preferred_mount_id)
    if not dispatched then
        dispatched = self:_dispatch_fallback_mount()
    end
    return dispatched
end

function MountManager:update(target_pos, _context)
    local player = self:_player()
    local now_ms = self:_now_ms()
    local preferred_mount_id = num(self._blackboard:get("module.bg.preferred_mount_id", 184865))

    self:_set("bg.mount.enabled", self._blackboard:get("module.bg.auto_mount", true) == true)
    self:_set("bg.mount.preferred_mount_id", preferred_mount_id)

    if not player then
        self:_set_state("idle", "no_player")
        return self._state
    end

    if self._pending then
        local ok_mounted, mounted = safe_call(player, "is_mounted")
        if ok_mounted and mounted == true then
            self._pending = false
            self._cast_dispatched = false
            self._settle_until_ms = 0
            self._confirm_until_ms = 0
            self._pending_since_ms = 0
            self:_set_state("mounted", "")
            return self._state
        end

        if self._cast_dispatched ~= true then
            if now_ms < self._settle_until_ms then
                self:_set_state("mount_pending", "")
                return self._state
            end

            local dispatched = self:_attempt_mount(preferred_mount_id)
            if not dispatched then
                self._pending = false
                self._cast_dispatched = false
                self._settle_until_ms = 0
                self._confirm_until_ms = 0
                self._pending_since_ms = 0
                self:_set_state("idle", "mount_dispatch_failed")
                return self._state
            end

            local no_cast_grace_ms = math.floor((tonumber(self._blackboard:get("module.bg.mount_no_cast_grace_s", 3.0)) or 3.0) * 1000)
            self._last_attempt_ms = now_ms
            self._cast_dispatched = true
            self._confirm_until_ms = now_ms + math.max(1000, no_cast_grace_ms)
            self:_set_state("mount_requested", "")
            return self._state
        end

        if now_ms < self._confirm_until_ms then
            self:_set_state("mount_requested", "")
            return self._state
        end

        self._pending = false
        self._cast_dispatched = false
        self._settle_until_ms = 0
        self._confirm_until_ms = 0
        self._pending_since_ms = 0
        self:_set_state("idle", "mount_not_confirmed")
        return self._state
    end

    local block_reason = self:_eligible_block_reason(target_pos)
    if block_reason then
        if block_reason == "already_mounted" then
            self:_set_state("mounted", "")
        else
            self:_set_state("idle", block_reason)
        end
        return self._state
    end

    local micro_stop_ms = math.floor((tonumber(self._blackboard:get("module.bg.mount_micro_stop_for_cast_s", 0.45)) or 0.45) * 1000)
    local settle_before_cast_ms = math.floor((tonumber(self._blackboard:get("module.bg.mount_settle_before_cast_s", 0.25)) or 0.25) * 1000)
    if micro_stop_ms < 0 then
        micro_stop_ms = 0
    end
    if settle_before_cast_ms < 0 then
        settle_before_cast_ms = 0
    end

    self._nav_adapter:stop("mount_prepare")
    self._pending = true
    self._cast_dispatched = false
    self._pending_since_ms = now_ms
    self._settle_until_ms = now_ms + math.max(250, micro_stop_ms, settle_before_cast_ms)
    self._confirm_until_ms = 0
    self:_set_state("mount_pending", "")
    return self._state
end

function MountManager:request_dismount_for_combat()
    local player = self:_player()
    local ok_mounted, mounted = safe_call(player, "is_mounted")
    if not ok_mounted or mounted ~= true then
        return false
    end
    if not core or not core.input or type(core.input.dismount) ~= "function" then
        return false
    end
    local ok = invoke_bool(core.input, "dismount")
    self:_set("bg.mount.last_attempt_method", "dismount")
    self:_set("bg.mount.last_attempt_ok", ok)
    if ok then
        self._pending = false
        self._cast_dispatched = false
        self._settle_until_ms = 0
        self._confirm_until_ms = 0
        self._pending_since_ms = 0
        self:_set_state("idle", "dismount_for_combat")
    end
    return ok
end

function MountManager:get_snapshot()
    return {
        state = self._state,
        pending = self._pending,
    }
end

return MountManager
