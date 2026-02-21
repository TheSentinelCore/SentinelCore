local RotationRegistry = require("rotations/RotationRegistry")
local Providers = require("rotations/Providers")
local ErrorCodes = require("events/ErrorCodes")
local Events = require("events/Events")
local Helpers = require("lib/Helpers")

local OBJECT_UNWRAP_KEYS = {
    "object",
    "raw_object",
    "game_object",
}
---@private
---@param registry RotationRegistry
---@param provider table|nil
local function register_provider(registry, provider)
    if not registry or not provider then
        return
    end

    local class_id = nil
    if provider.class_id then
        class_id = tonumber(provider:class_id())
    elseif provider.CLASS_ID then
        class_id = tonumber(provider.CLASS_ID)
    end

    local spec_id = 0
    if provider.spec_id then
        spec_id = tonumber(provider:spec_id()) or 0
    elseif provider.SPEC_ID then
        spec_id = tonumber(provider.SPEC_ID) or 0
    end

    if class_id ~= nil then
        registry:register(class_id, spec_id, provider)
    end
end

---@class RotationEngine
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _registry RotationRegistry
---@field private _queue table|nil
---@field private _spell_helper table|nil
---@field private _unit_helper table|nil
---@field private _enums table|nil
---@field private _last_cast_at number
local RotationEngine = {}
RotationEngine.__index = RotationEngine

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@return RotationEngine
function RotationEngine:new(event_bus, blackboard, cfg)
    local o = setmetatable({}, RotationEngine)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._registry = RotationRegistry:new()
    o._queue = nil
    o._spell_helper = nil
    o._unit_helper = nil
    o._enums = nil
    o._last_cast_at = 0

    for i = 1, #Providers do
        register_provider(o._registry, Providers[i])
    end

    local ok, queue = pcall(require, "common/modules/spell_queue")
    if ok and queue then
        o._queue = queue
    end

    local sh_ok, spell_helper = pcall(require, "common/utility/spell_helper")
    if sh_ok and spell_helper then
        o._spell_helper = spell_helper
    end

    local uh_ok, unit_helper = pcall(require, "common/utility/unit_helper")
    if uh_ok and unit_helper then
        o._unit_helper = unit_helper
    end

    local enums_ok, enums = pcall(require, "common/enums")
    if enums_ok and enums then
        o._enums = enums
    end

    return o
end

---@private
---@param value any
---@return any
local function unwrap_game_object(value)
    if type(value) ~= "table" then
        return value
    end

    for i = 1, #OBJECT_UNWRAP_KEYS do
        local candidate = rawget(value, OBJECT_UNWRAP_KEYS[i])
        if type(candidate) == "userdata" then
            return candidate
        end
    end

    return value
end

---@private
---@param value any
---@return boolean
local function is_native_game_object(value)
    return type(value) == "userdata"
end

---@private
---@return table
function RotationEngine:_build_context()
    local player = self._blackboard:get("player.object")
    local target = self._blackboard:get("combat.target")
    local player_pos = self._blackboard:get("player.position")
    local target_pos = target and target.get_position and target:get_position() or nil
    local player_health_pct = nil
    local target_health_pct = nil
    local player_mana_pct = nil

    if player and self._unit_helper and self._unit_helper.get_health_percentage then
        local ok, pct = pcall(self._unit_helper.get_health_percentage, self._unit_helper, player)
        if ok and type(pct) == "number" then
            player_health_pct = pct
        end
    end
    if target and self._unit_helper and self._unit_helper.get_health_percentage then
        local ok, pct = pcall(self._unit_helper.get_health_percentage, self._unit_helper, target)
        if ok and type(pct) == "number" then
            target_health_pct = pct
        end
    end

    local mana_type = self._enums and self._enums.power_type and self._enums.power_type.MANA or nil
    if player and mana_type and self._unit_helper and self._unit_helper.get_resource_percentage then
        local ok, pct = pcall(self._unit_helper.get_resource_percentage, self._unit_helper, player, mana_type)
        if ok and type(pct) == "number" then
            player_mana_pct = pct
        end
    end

    if player_health_pct == nil and player and player.get_health and player.get_max_health then
        local hp = tonumber(player:get_health()) or 0
        local hp_max = math.max(1, tonumber(player:get_max_health()) or hp)
        player_health_pct = hp / hp_max
    end
    if target_health_pct == nil and target and target.get_health and target.get_max_health then
        local hp = tonumber(target:get_health()) or 0
        local hp_max = math.max(1, tonumber(target:get_max_health()) or hp)
        target_health_pct = hp / hp_max
    end

    local target_distance = Helpers.distance_3d(player_pos, target_pos)
    local target_is_casting = target and target.is_casting_spell and target:is_casting_spell() or false

    return {
        player = player,
        target = target,
        player_position = player_pos,
        target_position = target_pos,
        class_id = self._blackboard:get("player.class_id", 0),
        spec_id = self._blackboard:get("player.spec_id", 0),
        enemy_count = self._blackboard:get("combat.enemy_count", 1),
        in_combat = self._blackboard:get("player.in_combat", false),
        now = (core and core.time and core.time()) or 0,
        player_health_pct = player_health_pct,
        player_mana_pct = player_mana_pct,
        target_health_pct = target_health_pct,
        target_distance = target_distance,
        target_is_casting = target_is_casting,
    }
end

---@param ctx table
---@return table|nil
function RotationEngine:get_provider(ctx)
    local class_id = tonumber(ctx.class_id) or 0
    local spec_id = tonumber(ctx.spec_id) or 0

    local provider = self._registry:get(class_id, spec_id)
    if provider and provider.can_run and provider:can_run(ctx) then
        return provider
    end

    -- TBC environments may not report spec_id through this API.
    provider = self._registry:get(class_id, 0)
    if provider and provider.can_run and provider:can_run(ctx) then
        return provider
    end

    return nil
end

---@param ctx table
---@param provider table
---@return table[]
function RotationEngine:build_plan(ctx, provider)
    local plan = {}

    local function append(actions)
        if type(actions) ~= "table" then
            return
        end
        for i = 1, #actions do
            plan[#plan + 1] = actions[i]
        end
    end

    append(provider:defensive(ctx))
    append(provider:interrupt(ctx))
    append(provider:utility(ctx))

    local aoe_threshold = tonumber(self._cfg.aoe_enemy_threshold) or 3
    if (tonumber(ctx.enemy_count) or 1) >= aoe_threshold then
        append(provider:aoe(ctx))
    else
        append(provider:combat(ctx))
    end

    table.sort(plan, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)

    return plan
end

---@private
---@param action table
---@param ctx table
---@return boolean
---@return string|nil
function RotationEngine:_execute_queue_first(action, ctx)
    if not self._queue then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    local cast_target = unwrap_game_object(ctx.target)
    local cast_self = unwrap_game_object(ctx.player)

    if action.action_type == "cast_spell_target" and self._queue.queue_spell_target then
        if not is_native_game_object(cast_target) then
            return false, ErrorCodes.CAST_INVALID_TARGET
        end
        local ok = pcall(self._queue.queue_spell_target, self._queue, action.spell_id, cast_target, action.priority or 1,
            "SentinelCore", action.allow_movement)
        if not ok then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        return true, nil
    end

    if action.action_type == "cast_spell_self" and self._queue.queue_spell_target then
        if not is_native_game_object(cast_self) then
            return false, ErrorCodes.CAST_INVALID_TARGET
        end
        local ok = pcall(self._queue.queue_spell_target, self._queue, action.spell_id, cast_self, action.priority or 1,
            "SentinelCore", true)
        if not ok then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        return true, nil
    end

    return false, ErrorCodes.CAST_GUARD_BLOCKED
end

---@private
---@param action table
---@param ctx table
---@return boolean
---@return string|nil
function RotationEngine:_execute_guarded_fallback(action, ctx)
    local now = (core and core.time and core.time()) or 0
    local throttle = tonumber(self._cfg.action_throttle) or 0.12
    if now - self._last_cast_at < throttle then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    if not ctx.player or (ctx.player.is_casting_spell and ctx.player:is_casting_spell()) then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    if core and core.spell_book and core.spell_book.is_usable_spell then
        local usable = core.spell_book.is_usable_spell(action.spell_id)
        if usable == false then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
    end

    if action.action_type == "cast_spell_target" then
        local cast_target = unwrap_game_object(ctx.target)
        if not cast_target then
            return false, ErrorCodes.TARGET_NOT_FOUND
        end
        if not is_native_game_object(cast_target) then
            return false, ErrorCodes.CAST_INVALID_TARGET
        end
        if core and core.input and core.input.cast_target_spell then
            local ok = core.input.cast_target_spell(action.spell_id, cast_target)
            if ok then
                self._last_cast_at = now
                return true, nil
            end
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
    end

    if action.action_type == "cast_spell_self" then
        local cast_self = unwrap_game_object(ctx.player)
        if not is_native_game_object(cast_self) then
            return false, ErrorCodes.CAST_INVALID_TARGET
        end
        if core and core.input and core.input.cast_target_spell then
            local ok = core.input.cast_target_spell(action.spell_id, cast_self)
            if ok then
                self._last_cast_at = now
                return true, nil
            end
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
    end

    return false, ErrorCodes.CAST_GUARD_BLOCKED
end

---@private
---@param action table
---@param ctx table
---@return boolean
---@return string|nil
function RotationEngine:_action_allowed(action, ctx)
    if type(action) ~= "table" then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    if action.action_type == "cast_spell_target" and not ctx.target then
        return false, ErrorCodes.TARGET_NOT_FOUND
    end

    if action.target_must_be_casting == true and ctx.target_is_casting ~= true then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    local player_health_pct = tonumber(ctx.player_health_pct)
    local target_health_pct = tonumber(ctx.target_health_pct)
    local player_mana_pct = tonumber(ctx.player_mana_pct)
    local target_distance = tonumber(ctx.target_distance)

    if action.max_player_health_pct and (player_health_pct == nil or player_health_pct > action.max_player_health_pct) then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end
    if action.min_player_health_pct and (player_health_pct == nil or player_health_pct < action.min_player_health_pct) then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end
    if action.max_target_health_pct and (target_health_pct == nil or target_health_pct > action.max_target_health_pct) then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end
    if action.min_target_health_pct and (target_health_pct == nil or target_health_pct < action.min_target_health_pct) then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end
    if action.min_player_mana_pct and (player_mana_pct == nil or player_mana_pct < action.min_player_mana_pct) then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end
    if action.max_target_distance and (target_distance == nil or target_distance > action.max_target_distance) then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end
    if action.min_target_distance and (target_distance == nil or target_distance < action.min_target_distance) then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    if type(action.condition) == "function" then
        local ok, allowed = pcall(action.condition, ctx, action)
        if not ok or allowed ~= true then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
    end

    if action.requires_castable_check == true and self._spell_helper and self._spell_helper.is_spell_castable then
        local caster = unwrap_game_object(ctx.player)
        local target = action.action_type == "cast_spell_self" and caster or unwrap_game_object(ctx.target)
        if not is_native_game_object(caster) or not is_native_game_object(target) then
            return false, ErrorCodes.CAST_INVALID_TARGET
        end

        local skip_facing = action.skip_facing == true
        local skip_range = action.skip_range == true
        local ok, castable = pcall(
            self._spell_helper.is_spell_castable,
            self._spell_helper,
            action.spell_id,
            caster,
            target,
            skip_facing,
            skip_range
        )
        if not ok or castable ~= true then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
    end

    return true, nil
end

---@param action table
---@param ctx table
---@return boolean
---@return string|nil
function RotationEngine:execute_action(action, ctx)
    local ok, err = self:_execute_queue_first(action, ctx)
    if ok then
        self._event_bus:emit(Events.ROTATION_EXECUTED, {
            action = action,
            adapter = "queue",
        })
        return true, nil
    end

    local fallback_ok, fallback_err = self:_execute_guarded_fallback(action, ctx)
    if fallback_ok then
        self._event_bus:emit(Events.ROTATION_EXECUTED, {
            action = action,
            adapter = "fallback",
        })
        return true, nil
    end

    return false, fallback_err or err
end

---@return table[]|nil
---@return string|nil
function RotationEngine:generate_plan()
    local ctx = self:_build_context()
    local provider = self:get_provider(ctx)
    if not provider then
        return nil, ErrorCodes.ROTATION_UNAVAILABLE
    end

    local plan = self:build_plan(ctx, provider)
    return plan, nil
end

---@return boolean
---@return string|nil
function RotationEngine:tick_once()
    local ctx = self:_build_context()
    local provider = self:get_provider(ctx)
    if not provider then
        return false, ErrorCodes.ROTATION_UNAVAILABLE
    end

    local plan = self:build_plan(ctx, provider)
    if #plan == 0 then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    local last_err = ErrorCodes.CAST_GUARD_BLOCKED
    for i = 1, #plan do
        local action = plan[i]
        local allowed, guard_err = self:_action_allowed(action, ctx)
        if allowed then
            local executed, exec_err = self:execute_action(action, ctx)
            if executed then
                return true, nil
            end
            last_err = exec_err or guard_err or last_err
        else
            last_err = guard_err or last_err
        end
    end

    return false, last_err
end

---@return table
function RotationEngine:get_pull_profile()
    local ctx = self:_build_context()
    local provider = self:get_provider(ctx)
    if provider and provider.get_pull_profile then
        return provider:get_pull_profile(ctx)
    end
    return {
        pull_spell_id = nil,
        max_pull_range = 25,
    }
end

return RotationEngine
