-- App.lua — Top-level orchestrator for SentinelDuoFarm.
-- Owns all subsystems and drives the master FSM.

local Config      = require("core/Config")
local Blackboard  = require("core/Blackboard")
local EventBus    = require("core/EventBus")
local StateMachine = require("core/StateMachine")
local CoordClient = require("coordination/CoordClient")
local NavAdapter  = require("navigation/NavAdapter")
local DuoNav      = require("navigation/DuoNav")
local SpellCatalog = require("spells/SpellCatalog")
local spell_data  = require("spells/spell_data")
local helpers     = require("lib/helpers")

-- Master FSM states (loaded lazily so missing modules only fail on initialize)
local function load_states()
    return {
        require("states/StateInit"),
        require("states/StateCoordConnect"),
        require("states/StateBuffing"),
        require("states/StateTravelToInstance"),
        require("states/StateEntering"),
        require("states/StateInsideBuff"),
        require("states/StateFarming"),
        require("states/StateExiting"),
        require("states/StateResetting"),
        require("states/StateWaitingLockout"),
        require("states/StateTravelToVendor"),
        require("states/StateVendoring"),
        require("states/StateTravelReturn"),
        require("states/StateDead"),
        require("states/StatePaused"),
        require("states/StateError"),
    }
end

-- Bag scanning per design doc §8.3
local BAG_SLOT_COUNTS = { [-2] = 0, [0] = 16, [1] = 16, [2] = 16, [3] = 16, [4] = 16 }
local FULL_THRESHOLD  = 4  -- free slots <= this → bags full

local function count_free_bag_slots()
    local free = 0
    for bag_id = 0, 4 do
        local ok, items = pcall(core.inventory.get_items_in_bag, bag_id)
        if ok and type(items) == "table" then
            -- Determine capacity: use API if available, else fall back to config.
            local ok_cap, capacity = pcall(core.inventory.get_num_bag_slots, bag_id)
            if not ok_cap or type(capacity) ~= "number" or capacity <= 0 then
                capacity = BAG_SLOT_COUNTS[bag_id] or 16
            end
            local used = 0
            for _, slot_entry in ipairs(items) do
                local obj = slot_entry and slot_entry.object
                if obj then
                    local ok_id, item_id = pcall(obj.get_item_id, obj)
                    if ok_id and item_id and item_id ~= 0 then
                        used = used + 1
                    end
                end
            end
            free = free + math.max(0, capacity - used)
        end
    end
    return free
end

---@class App
local App = {}
App.__index = App

---@return App
function App:new()
    return setmetatable({
        _bb            = nil,
        _event_bus     = nil,
        _coord_client  = nil,
        _nav_adapter   = nil,
        _duo_nav       = nil,
        _spell_catalog = nil,
        _fsm           = nil,
        _profile       = nil,
        _ui            = nil,
        _initialized   = false,
    }, App)
end

function App:initialize()
    if self._initialized then return end
    self._initialized = true

    self._bb           = Blackboard:new()
    self._event_bus    = EventBus:new()
    self._coord_client = CoordClient:new(Config)
    self._nav_adapter  = NavAdapter:new()
    self._duo_nav      = DuoNav:new(self._nav_adapter, self._bb)
    self._spell_catalog = SpellCatalog:new(spell_data)

    -- Shared context passed into each state factory
    local ctx = {
        bb            = self._bb,
        event_bus     = self._event_bus,
        coord_client  = self._coord_client,
        duo_nav       = self._duo_nav,
        spell_catalog = self._spell_catalog,
        config        = Config,
    }

    -- Attempt to load profile.
    -- Priority: 1) active JSON profile from scripts_data, 2) Lua require fallback.
    local ProfileManager = require("core/ProfileManager")
    ProfileManager.init()
    local profile = nil
    local active_name = ProfileManager.get_active_name()
    if active_name and active_name ~= "" then
        local p, err = ProfileManager.load(active_name)
        if p then
            profile = p
            helpers.log("[App] loaded JSON profile: " .. active_name)
        else
            helpers.log_warn("[App] JSON profile load failed (" .. tostring(err) .. "), falling back")
        end
    end
    if not profile then
        local profile_ok, prof = pcall(require, "profiles/stratholme_se")
        if profile_ok and type(prof) == "table" then
            profile = prof
        end
    end
    if profile then
        self._profile = profile
        ctx.profile   = profile
        self._bb:set("duo.profile_id",    profile.id           or "stratholme_se")
        self._bb:set("duo.dungeon_name",  profile.dungeon_name or "Unknown")
    else
        helpers.log_warn("[App] profile not loaded — running without profile")
    end

    -- Build master FSM states table
    local state_modules_ok, state_mods = pcall(load_states)
    local states_table = {}

    if state_modules_ok then
        for _, mod in ipairs(state_mods) do
            if type(mod) == "table" and mod.name and mod.create then
                states_table[mod.name] = mod:create(ctx)
            end
        end
    else
        helpers.log_warn("[App] some state modules failed to load: " .. tostring(state_mods))
    end

    -- Ensure at minimum INIT state exists
    if not states_table["INIT"] then
        states_table["INIT"] = {
            update = function(_bb)
                helpers.log_warn("[App] INIT state is a stub — states not fully loaded")
                return nil
            end,
        }
    end

    self._fsm = StateMachine:new("Master", states_table, "INIT")

    -- Load UI (optional — fails gracefully if not yet created)
    local ui_ok, ui_mod = pcall(require, "ui/DuoWindow")
    if ui_ok and type(ui_mod) == "table" then
        self._ui = ui_mod:new(self._bb)
        if self._ui.initialize then
            pcall(self._ui.initialize, self._ui)
        end
    end

    -- Create menu tree node element (must be created at load time, not in callback)
    local ok_tree, tree = pcall(core.menu.tree_node)
    self._menu_tree = ok_tree and tree or nil

    -- Initialize blackboard defaults
    self._bb:set("duo.current_state",    "INIT")
    self._bb:set("duo.bot_running",      true)
    self._bb:set("duo.user_paused",      false)
    self._bb:set("duo.coord_connected",  false)
    self._bb:set("duo.session_start_ms", helpers.game_time_ms())
    self._bb:set("duo.runs_completed",   0)
    self._bb:set("duo.deaths_this_session", 0)

    helpers.log("[App] initialized")
end

--- Safety guard — called before main update.
function App:on_pre_tick()
    -- guard intentionally empty; core handles nil player
end

--- Main game loop — called every frame.
function App:on_update()
    if not self._initialized then return end
    if not self._bb:get("duo.bot_running", true) then return end

    -- 1. Player sensor guard
    local ok_player, player = pcall(core.object_manager.get_local_player)
    if not ok_player or not player then return end

    -- 2. Refresh sensors
    local function safe_get(method, ...)
        local ok, v = pcall(method, ...)
        return ok and v or nil
    end

    local pos = safe_get(player.get_position, player)
    if pos then self._bb:set("player.position", pos) end

    local hp_max = tonumber(safe_get(player.get_max_health, player)) or 1
    local hp_cur = tonumber(safe_get(player.get_health,     player)) or 0
    self._bb:set("player.hp_pct", hp_cur / math.max(hp_max, 1))

    local mp_max = tonumber(safe_get(player.get_max_power, player, 0)) or 1
    local mp_cur = tonumber(safe_get(player.get_power,     player, 0)) or 0
    self._bb:set("player.mp_pct", mp_cur / math.max(mp_max, 1))

    local is_dead = safe_get(player.is_dead, player)
    self._bb:set("player.is_dead", is_dead == true)

    local is_ghost = safe_get(player.is_ghost, player)
    self._bb:set("player.is_ghost", is_ghost == true)

    local is_casting = safe_get(player.is_casting, player) or safe_get(player.is_channeling, player)
    self._bb:set("player.is_casting", is_casting == true)

    -- Instance detection: exact match against profile.instance_map_id only.
    -- Do NOT use outdoor_map_id fallback — graveyard maps (1415, 1423 etc.) are
    -- also non-zero but are NOT the instance.
    local profile = self._profile
    if profile then
        local ok_map, map_id = pcall(core.get_map_id)
        local cur_map = (ok_map and type(map_id) == "number") and map_id or 0
        local in_inst = (profile.instance_map_id ~= nil) and (cur_map == profile.instance_map_id)

        local prev_map = self._bb:get("player.map_id", -1)
        if cur_map ~= prev_map then
            helpers.log(string.format("[App] map_id changed: %s → %s  in_instance=%s",
                tostring(prev_map), tostring(cur_map), tostring(in_inst)))
        end
        self._bb:set("player.in_instance", in_inst)
        self._bb:set("player.map_id", cur_map)
    end

    -- 3. Bag check
    local free = count_free_bag_slots()
    local bags_full = (free <= FULL_THRESHOLD)
    self._bb:set("duo.free_bag_slots",  free)
    self._bb:set("duo.bags_full_local", bags_full)
    if bags_full and self._coord_client:is_connected() then
        self._coord_client:request_vendor_break()
    end

    -- 4. Coordination heartbeat
    local gt = helpers.game_time_ms()
    self._coord_client:tick(self._bb, gt)

    -- 5. Navigation poll
    self._duo_nav:poll()

    -- Escalate persistent stuck to ERROR so the bot doesn't spin forever.
    if self._bb:get("duo.nav_stuck_escalated", false) then
        local cs = self._fsm:get_current_state()
        local skip = { ERROR=true, PAUSED=true, DEAD=true, INIT=true,
                       COORD_CONNECT=true, WAITING_LOCKOUT=true }
        if not skip[cs] then
            helpers.log_err("[App] nav_stuck_escalated in state " .. cs .. " — ERROR")
            self._bb:set("duo.error_reason", "nav_stuck_escalated in " .. cs)
            self._bb:set("duo.nav_stuck_escalated", false)
            self._fsm:transition_to("ERROR", self._bb)
        end
    end

    -- 6. Master FSM
    self._fsm:tick(self._bb)

    -- Sync current_state key for coord heartbeat phase mapping
    self._bb:set("duo.current_state", self._fsm:get_current_state())

    -- 7. UI sync
    if self._ui and self._ui.sync then
        pcall(self._ui.sync, self._ui, self._bb)
    end
end

--- 3D overlay rendering + SentinelUI floating window.
function App:on_render()
    if not self._initialized then return end

    -- SentinelUI canvas window
    if self._ui and self._ui.on_render then
        pcall(self._ui.on_render, self._ui)
    end

    if not self._bb:get("duo.show_overlay", false) then return end

    local profile = self._profile
    if not profile or type(profile.pulls) ~= "table" then return end

    for _, pull in ipairs(profile.pulls) do
        -- Draw pull path (blue)
        if type(pull.pull_path) == "table" then
            for i = 1, #pull.pull_path - 1 do
                local a = pull.pull_path[i]
                local b = pull.pull_path[i + 1]
                if a and b then
                    pcall(core.graphics.line_3d, a, b, 0x660000FF, 2.0)
                end
            end
        end

        -- Draw Blizzard circle (purple)
        if pull.blizzard_center then
            pcall(core.graphics.circle_3d, pull.blizzard_center, 10.0, 0x66AA00FF, 2.0)
        end

        -- Draw Ice Block position (yellow dot label)
        if pull.ice_block_position then
            pcall(core.graphics.circle_3d, pull.ice_block_position, 1.5, 0x66FFFF00, 2.0)
        end

        -- Draw safe position (green)
        if pull.safe_position then
            pcall(core.graphics.circle_3d, pull.safe_position, 2.0, 0x6600FF00, 2.0)
        end
    end
end

--- PS menu integration.
function App:on_render_menu()
    if not self._initialized then return end
    if not self._menu_tree then return end

    self._menu_tree:render("SentinelDuoFarm", function()
        if self._ui and self._ui.render_menu then
            pcall(self._ui.render_menu, self._ui)
        end
    end)
end

return App
