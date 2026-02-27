local Config = require("core/Config")
local Blackboard = require("core/Blackboard")
local EventBus = require("core/EventBus")
local Logger = require("core/Logger")
local StateMachine = require("core/StateMachine")

local SensorService = require("services/SensorService")
local DuoSyncService = require("services/DuoSyncService")
local RouteService = require("services/RouteService")
local TargetService = require("services/TargetService")
local MovementService = require("services/MovementService")
local CombatService = require("services/CombatService")
local FarmService = require("services/FarmService")
local LootService = require("services/LootService")
local VendorService = require("services/VendorService")
local TelemetryService = require("services/TelemetryService")
local RecordService = require("services/RecordService")

---@class StrathDuoBot
local Bot = {}
Bot.__index = Bot

local function now_secs()
    if core and core.time then
        local ok, value = pcall(core.time)
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return os.time()
end

local function make_bot_id()
    local stamp = math.floor(now_secs() * 1000)
    local rnd = math.random(1000, 9999)
    return tostring(stamp) .. "-" .. tostring(rnd)
end

---@param opts? table
---@return StrathDuoBot
function Bot:new(opts)
    local o = setmetatable({}, Bot)

    o._cfg = Config:build(opts)
    o._bb = Blackboard:new()
    o._bus = EventBus:new()
    o._log = Logger:new("StrathDuoMage")
    o._state = StateMachine:new()
    o._menu_open = false
    o._last_tick = 0
    o._bot_id = make_bot_id()

    o._bb:set("duo.role", tostring(o._cfg.role or "leader"))
    o._bb:set("bot.id", o._bot_id)

    o._movement = MovementService:new(o._cfg, Logger:new("Movement"))
    o._sensors = SensorService:new(o._bb, o._cfg, Logger:new("Sensors"))
    o._duo_sync = DuoSyncService:new(o._bb, o._cfg, Logger:new("DuoSync"), o._bot_id)
    o._route = RouteService:new(o._bb, o._cfg, o._movement, Logger:new("Route"))
    o._targeting = TargetService:new(o._bb, o._cfg, Logger:new("Targeting"))
    o._combat = CombatService:new(o._bb, o._cfg, o._movement, Logger:new("Combat"))
    o._vendor = VendorService:new(o._bb, o._cfg, Logger:new("Vendor"))
    o._loot = LootService:new(o._bb, o._cfg, Logger:new("Loot"))
    o._telemetry = TelemetryService:new(o._bb, o._cfg, Logger:new("Telemetry"))
    o._record = RecordService:new(o._bb, o._cfg, Logger:new("Record"))
    o._farm = FarmService:new(o._bb, o._cfg, {
        route = o._route,
        movement = o._movement,
        targeting = o._targeting,
        combat = o._combat,
    }, Logger:new("Farm"))

    o._services = {
        o._sensors,
        o._vendor,
        o._duo_sync,
        o._route,
        o._targeting,
        o._farm,
        o._loot,
        o._telemetry,
        o._record,
    }

    o._log:info("bot initialized id=%s role=%s", o._bot_id, o._bb:get("duo.role"))
    return o
end

---@return boolean
function Bot:is_running()
    return self._state:is_running()
end

---@return string
function Bot:get_state()
    return self._state:get_state()
end

function Bot:toggle_menu()
    self._menu_open = not self._menu_open
end

function Bot:toggle_role()
    local role = tostring(self._bb:get("duo.role", "leader"))
    if role == "leader" then
        role = "follower"
    else
        role = "leader"
    end
    self._bb:set("duo.role", role)
    self._cfg.role = role
    self._log:info("role switched to %s", role)
end

---@param profile_path? string
---@return boolean
---@return string|nil
function Bot:load_profile(profile_path)
    if not profile_path or profile_path == "" then
        return false, "profile path required"
    end

    local ok, err = Config:load_profile_file(self._cfg, profile_path)
    if not ok then
        self._log:error("profile load failed: %s", tostring(err))
        return false, err
    end

    self._log:info("profile loaded: %s", tostring(profile_path))
    return true, nil
end

---@return boolean
---@return string|nil
function Bot:start()
    if self._state:is_running() then
        return true, nil
    end

    self._state:start()
    self._bb:set("runtime.started_at", now_secs())
    self._log:info("started")
    return true, nil
end

---@param reason? string
function Bot:stop(reason)
    self._state:stop()
    self._movement:stop()
    self._bb:set("runtime.stop_reason", tostring(reason or "manual"))
    self._log:info("stopped reason=%s", tostring(reason or "manual"))
end

function Bot:pause()
    self._state:pause()
end

function Bot:resume()
    self._state:resume()
end

function Bot:update()
    local now = now_secs()
    local interval = tonumber(self._cfg.loop_interval) or 0.05
    if (now - self._last_tick) < interval then
        return
    end
    self._last_tick = now

    if not self._state:is_running() then
        local passive = { self._sensors, self._record }
        for i = 1, #passive do
            local service = passive[i]
            if service and type(service.update) == "function" then
                local ok, err = pcall(service.update, service, now)
                if not ok then
                    self._log:error("passive service crash idx=%d err=%s", i, tostring(err))
                end
            end
        end
        self._bb:set("farm.phase", "idle")
        return
    end

    for i = 1, #self._services do
        local service = self._services[i]
        if service and type(service.update) == "function" then
            local ok, err = pcall(service.update, service, now)
            if not ok then
                self._log:error("service crash at index=%d err=%s", i, tostring(err))
                self._state:fail("service_crash")
                return
            end
        end
    end

    self._bb:set("farm.phase", self._farm and self._farm:get_phase() or "idle")
end

function Bot:render()
    if not self._menu_open then
        return
    end

    local snapshot = self._bb:get("telemetry.snapshot") or {}
    local role = tostring(self._bb:get("duo.role", "leader"))
    local phase = tostring(self._bb:get("farm.phase", "idle"))
    local partner = self._bb:get("duo.partner")
    local partner_state = partner and "online" or "offline"

    local lines = {
        "StrathDuoMage",
        "State: " .. tostring(self._state:get_state()),
        "Role: " .. role,
        "Phase: " .. phase,
        "Partner: " .. partner_state,
        string.format("Kills: %d", tonumber(snapshot.kills) or 0),
        string.format("GPH(copper): %.0f", tonumber(snapshot.gold_per_hour_copper) or 0),
    }

    if core and core.graphics and type(core.graphics.text_2d) == "function" then
        for i = 1, #lines do
            pcall(core.graphics.text_2d, lines[i], 30, 220 + (i * 16), 16)
        end
    end
end

---@return table
function Bot:get_snapshot()
    local telemetry = self._bb:get("telemetry.snapshot") or {}
    local partner = self._bb:get("duo.partner")
    local route_segment = self._bb:get("route.segment")
    local record_state = self._record and self._record.get_state and self._record:get_state() or {}

    return {
        state = self._state:get_state(),
        role = tostring(self._bb:get("duo.role", "leader")),
        phase = tostring(self._bb:get("farm.phase", "idle")),
        in_combat = self._bb:get("player.in_combat", false) == true,
        partner_online = partner ~= nil,
        enemy_count = tonumber(self._bb:get("combat.enemy_count", 0)) or 0,
        route = {
            segment_index = tonumber(self._bb:get("route.segment_index", 0)) or 0,
            pull_index = tonumber(self._bb:get("route.pull_index", 0)) or 0,
            collecting = self._bb:get("route.collecting", false) == true,
            segment_id = route_segment and tostring(route_segment.id or "") or "",
        },
        telemetry = telemetry,
        record = record_state,
    }
end

---@param profile_path? string
---@return boolean
---@return string|nil
function Bot:record_start(profile_path)
    if not self._record then
        return false, "record service unavailable"
    end
    local ok, err = self._record:start(profile_path)
    if ok then
        self._log:info("record mode started path=%s", tostring(profile_path or "default"))
    else
        self._log:error("record mode start failed err=%s", tostring(err))
    end
    return ok, err
end

---@param save_changes boolean
---@return boolean
---@return string|nil
function Bot:record_stop(save_changes)
    if not self._record then
        return false, "record service unavailable"
    end
    local ok, err = self._record:stop(save_changes == true)
    if ok then
        self._log:info("record mode stopped save=%s", tostring(save_changes == true))
        if save_changes == true then
            local state = self._record:get_state()
            local path = state and state.profile_path
            if path and path ~= "" then
                self:load_profile(path)
            end
        end
    else
        self._log:error("record mode stop failed err=%s", tostring(err))
    end
    return ok, err
end

---@return boolean
---@return any
function Bot:record_capture_pull_point()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:capture_pull_point()
end

---@return boolean
---@return any
function Bot:record_capture_gather_anchor()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:capture_gather_anchor()
end

---@return boolean
---@return any
function Bot:record_capture_lane_start()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:capture_lane_start()
end

---@return boolean
---@return any
function Bot:record_capture_lane_end()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:capture_lane_end()
end

---@return boolean
---@return any
function Bot:record_undo()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:undo_last()
end

---@return boolean
---@return any
function Bot:record_next_segment()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:next_segment()
end

---@return boolean
---@return any
function Bot:record_prev_segment()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:prev_segment()
end

---@return boolean
---@return any
function Bot:record_clear_pull_points()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:clear_pull_points()
end

---@return boolean
---@return any
function Bot:record_toggle_strategy()
    if not self._record then
        return false, "record service unavailable"
    end
    return self._record:toggle_strategy()
end

---@param path? string
---@return boolean
---@return string|nil
function Bot:record_save(path)
    if not self._record then
        return false, "record service unavailable"
    end
    local ok, err = self._record:save_profile(path)
    if ok then
        local state = self._record:get_state()
        local profile_path = state and state.profile_path
        if profile_path and profile_path ~= "" then
            self:load_profile(profile_path)
        end
    end
    return ok, err
end

function Bot:destroy()
    self:stop("destroy")
    if self._bus then
        self._bus:off_owner(self)
    end
end

return Bot
