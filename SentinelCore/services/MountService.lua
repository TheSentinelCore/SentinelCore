local get_now = require("lib/TimeHelper").get_now
local Events = require("events/Events")

-- Class-specific mount spell IDs (TBC)
-- Ordered highest-level first so we try the best mount available.
local CLASS_MOUNT_SPELLS = {
    [2] = { 34769, 13819 },   -- Paladin: Charger (L60), Warhorse (L40)
    [9] = { 23161, 5784 },    -- Warlock: Dreadsteed (L60), Felsteed (L40)
}

---@class MountService
local MountService = {}
MountService.__index = MountService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table|nil
---@param logger table|nil
---@return MountService
function MountService:new(event_bus, blackboard, cfg, logger)
    local o = setmetatable({}, MountService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._log = logger or { debug=function()end, info=function()end, warn=function()end, error=function()end }
    o._mount_attempt_at = 0
    o._mount_cooldown = 2.0

    -- Dismount when a pull starts or a target is acquired
    event_bus:on(Events.PULL_STARTED, function()
        o:try_dismount()
    end, { owner = o })

    event_bus:on(Events.TARGET_ACQUIRED, function()
        o:try_dismount()
    end, { owner = o })

    return o
end

function MountService:reset()
    self._mount_attempt_at = 0
end

---@return boolean
function MountService:should_mount()
    -- Must not be in combat
    if self._blackboard:get("player.in_combat", false) == true then
        return false
    end

    -- Must not already be mounted
    local is_mounted = false
    local player = nil
    if core and core.object_manager and core.object_manager.get_local_player then
        local ok_p, p = pcall(core.object_manager.get_local_player)
        if ok_p and p then
            player = p
        end
    end

    if player and type(player.is_mounted) == "function" then
        local ok_m, mounted = pcall(player.is_mounted, player)
        if ok_m then
            is_mounted = mounted == true
        else
            is_mounted = self._blackboard:get("player.is_mounted", false) == true
        end
    else
        is_mounted = self._blackboard:get("player.is_mounted", false) == true
    end

    if is_mounted then
        return false
    end

    -- Must be level 40+
    local min_level = tonumber(self._cfg.min_level) or 40
    local player_level = tonumber(self._blackboard:get("player.level", 1)) or 1
    if player_level < min_level then
        return false
    end

    -- Cooldown
    if get_now() < (self._mount_attempt_at + self._mount_cooldown) then
        return false
    end

    return true
end

function MountService:try_mount()
    if not self:should_mount() then
        return
    end

    local bb = self._blackboard
    local class_id = tonumber(bb:get("player.class_id", 0)) or 0

    self._mount_attempt_at = get_now()

    -- Try class-specific mounts first (highest level first)
    local spells = CLASS_MOUNT_SPELLS[class_id]
    if type(spells) == "table" then
        for i = 1, #spells do
            local spell_id = spells[i]
            local known = false
            if core and core.spell_book and type(core.spell_book.is_spell_learned) == "function" then
                local ok_k, k_val = pcall(core.spell_book.is_spell_learned, spell_id)
                if ok_k then
                    known = k_val == true
                end
            end

            if known then
                self._log:info("mounting with spell %d (class %d)", spell_id, class_id)
                if core and core.input and type(core.input.cast_spell_self) == "function" then
                    pcall(core.input.cast_spell_self, spell_id)
                end
                bb:set("player.is_mounted", true)
                return
            end
        end
    end

    self._log:debug("try_mount: no usable mount for class_id=%d level=%d",
        class_id,
        tonumber(bb:get("player.level", 0)) or 0)
end

function MountService:try_dismount()
    -- Check if currently mounted
    local is_mounted = false
    local player = nil
    if core and core.object_manager and core.object_manager.get_local_player then
        local ok_p, p = pcall(core.object_manager.get_local_player)
        if ok_p and p then
            player = p
        end
    end

    if player and type(player.is_mounted) == "function" then
        local ok_m, mounted = pcall(player.is_mounted, player)
        if ok_m then
            is_mounted = mounted == true
        else
            is_mounted = self._blackboard:get("player.is_mounted", false) == true
        end
    else
        is_mounted = self._blackboard:get("player.is_mounted", false) == true
    end

    if not is_mounted then
        return
    end

    self._log:info("dismounting")

    -- Try dismount API first, fall back to casting spell ID 0
    if core and core.input then
        if type(core.input.dismount) == "function" then
            pcall(core.input.dismount)
        elseif type(core.input.cast_spell_self) == "function" then
            pcall(core.input.cast_spell_self, 0)
        end
    end

    self._blackboard:set("player.is_mounted", false)
end

function MountService:update()
    -- Passive service: mount/dismount driven by events and explicit callers.
    -- update() is a no-op so the service can be included in the update order
    -- without side-effects on every tick.
    return true, nil
end

return MountService
