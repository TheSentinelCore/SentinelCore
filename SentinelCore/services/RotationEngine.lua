local RotationRegistry = require("rotations/RotationRegistry")
local Providers = require("rotations/Providers")
local SpellbookResolver = require("rotations/framework/SpellbookResolver")
local CombatContext = require("rotations/framework/CombatContext")
local PlanComposer = require("rotations/framework/PlanComposer")
local ErrorCodes = require("events/ErrorCodes")
local Events = require("events/Events")
local Helpers = require("lib/Helpers")

local OBJECT_UNWRAP_KEYS = {
    "object",
    "raw_object",
    "game_object",
}

local ITEM_UNWRAP_KEYS = {
    "item",
    "object",
    "raw_object",
    "game_object",
}

---@private
---@param action_priority any
---@return number
local function queue_priority(action_priority)
    -- Spell queue API uses 1..9, with 9 reserved for explicit manual overrides.
    local p = tonumber(action_priority) or 1
    if p <= 1 then
        return 1
    end

    -- Framework priorities are larger (for deterministic sorting), so compress to queue scale.
    local normalized = math.floor((p / 100))
    if normalized < 1 then
        normalized = 1
    elseif normalized > 8 then
        normalized = 8
    end
    return normalized
end
---@private
---@param registry RotationRegistry
---@param provider table|nil
---@param target_class_id? number
local function register_provider(registry, provider, target_class_id)
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

    local normalized_target = tonumber(target_class_id)
    if normalized_target and normalized_target > 0 and class_id ~= normalized_target then
        return
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
---@field private _inventory_helper table|nil
---@field private _izi table|nil
---@field private _enums table|nil
---@field private _spellbook SpellbookResolver
---@field private _context_builder CombatContextBuilder
---@field private _last_cast_at number
---@field private _active_provider_class_id number
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
    o._inventory_helper = nil
    o._izi = nil
    o._enums = nil
    o._spellbook = SpellbookResolver:new()
    o._context_builder = CombatContext:new(blackboard)
    o._last_cast_at = 0
    o._active_provider_class_id = 0

    local initial_class_id = tonumber(blackboard and blackboard.get and blackboard:get("player.class_id", 0)) or 0
    o:_sync_provider_registry(initial_class_id)

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

    local ih_ok, inventory_helper = pcall(require, "common/utility/inventory_helper")
    if ih_ok and inventory_helper then
        o._inventory_helper = inventory_helper
    end

    local enums_ok, enums = pcall(require, "common/enums")
    if enums_ok and enums then
        o._enums = enums
    end

    local izi_ok, izi = pcall(require, "common/izi_sdk")
    if izi_ok and izi then
        o._izi = izi
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
---@return any
local function unwrap_item_object(value)
    if type(value) ~= "table" then
        return value
    end

    for i = 1, #ITEM_UNWRAP_KEYS do
        local candidate = rawget(value, ITEM_UNWRAP_KEYS[i])
        if candidate ~= nil then
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
---@param item_obj any
---@return number
local function safe_item_id(item_obj)
    if not item_obj then
        return 0
    end

    if item_obj.is_valid then
        local ok_valid, valid = pcall(item_obj.is_valid, item_obj)
        if not ok_valid or valid ~= true then
            return 0
        end
    end

    if type(item_obj.get_item_id) ~= "function" then
        return 0
    end

    local ok_id, id = pcall(item_obj.get_item_id, item_obj)
    if not ok_id then
        return 0
    end

    return tonumber(id) or 0
end

---@private
---@return table
function RotationEngine:_build_context()
    return self._context_builder:build({
        enums = self._enums,
        spellbook = self._spellbook,
        helpers = {
            unit_helper = self._unit_helper,
            distance_3d = function(a, b)
                return Helpers.distance_3d(a, b)
            end,
        },
    })
end

---@private
---@param class_id number
---@return table[]
function RotationEngine:_resolve_providers_for_class(class_id)
    if type(Providers) ~= "table" then
        return {}
    end

    if type(Providers.load_for_class) == "function" then
        local ok, loaded = pcall(Providers.load_for_class, class_id)
        if ok and type(loaded) == "table" then
            return loaded
        end
        return {}
    end

    return Providers
end

---@private
---@param class_id number|nil
function RotationEngine:_sync_provider_registry(class_id)
    local normalized = tonumber(class_id) or 0
    if normalized <= 0 then
        return
    end

    if self._active_provider_class_id == normalized then
        return
    end

    self._registry = RotationRegistry:new()
    self._active_provider_class_id = normalized

    local providers = self:_resolve_providers_for_class(normalized)
    for i = 1, #providers do
        register_provider(self._registry, providers[i], normalized)
    end
end

---@param ctx table
---@return table|nil
function RotationEngine:get_provider(ctx)
    local class_id = tonumber(ctx.class_id) or 0
    local spec_id = tonumber(ctx.spec_id) or 0
    self:_sync_provider_registry(class_id)

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
    local aoe_threshold = tonumber(self._cfg.aoe_enemy_threshold) or 3
    return PlanComposer.compose_combat(provider, ctx, aoe_threshold)
end

---@param ctx table
---@param provider table
---@return table[]
function RotationEngine:build_maintenance_plan(ctx, provider)
    return PlanComposer.compose_maintenance(provider, ctx)
end

---@private
---@param player game_object|nil
---@param item_id number
---@return boolean
function RotationEngine:_player_has_item(player, item_id)
    if not player or not item_id or item_id <= 0 then
        return false
    end

    if player.has_item then
        local ok, has = pcall(player.has_item, player, item_id)
        if ok and has == true then
            return true
        end
    end

    if core and core.inventory and core.inventory.get_items_in_bag then
        for bag_id = 0, 4 do
            local ok_slots, slots = pcall(core.inventory.get_items_in_bag, bag_id)
            if ok_slots and type(slots) == "table" then
                for i = 1, #slots do
                    local row = slots[i]
                    local direct_id = tonumber(row and row.item_id) or 0
                    if direct_id == item_id then
                        return true
                    end

                    local obj = unwrap_item_object(row)
                    local current_id = safe_item_id(obj)
                    if current_id == item_id then
                        return true
                    end
                end
            end
        end
    end

    return false
end

---@private
---@param action table
---@param ctx table
---@return number|nil
function RotationEngine:_resolve_item_id(action, ctx)
    if action.action_type == "use_best_health_potion" and self._izi and self._izi.best_health_potion_id then
        local ok, item_id = pcall(self._izi.best_health_potion_id)
        if ok then
            return tonumber(item_id)
        end
    end

    if action.action_type == "use_best_mana_potion" and self._izi and self._izi.best_mana_potion_id then
        local ok, item_id = pcall(self._izi.best_mana_potion_id)
        if ok then
            return tonumber(item_id)
        end
    end

    if (action.action_type == "use_best_health_potion" or action.action_type == "use_best_mana_potion")
        and self._inventory_helper and self._inventory_helper.get_current_consumables_list then
        if self._inventory_helper.update_consumables_list then
            pcall(self._inventory_helper.update_consumables_list, self._inventory_helper)
        end
        local list_ok, consumables = pcall(self._inventory_helper.get_current_consumables_list, self._inventory_helper)
        if list_ok and type(consumables) == "table" then
            local selected = nil
            for i = 1, #consumables do
                local row = consumables[i]
                local is_health = action.action_type == "use_best_health_potion" and row.is_health_potion == true
                local is_mana = action.action_type == "use_best_mana_potion" and row.is_mana_potion == true
                if is_health or is_mana then
                    local item_obj = unwrap_item_object(row and row.item)
                    local item_id = safe_item_id(item_obj)
                    if item_id > 0 and (selected == nil or item_id > selected) then
                        selected = item_id
                    end
                end
            end
            return selected
        end
    end

    local configured = action.item_id
    if type(configured) == "number" then
        local id = tonumber(configured) or 0
        if self:_player_has_item(ctx.player, id) then
            return id
        end
        return nil
    end

    if type(configured) == "table" then
        for i = 1, #configured do
            local id = tonumber(configured[i]) or 0
            if id > 0 and self:_player_has_item(ctx.player, id) then
                return id
            end
        end
    end

    return nil
end

---@return boolean
function RotationEngine:should_hold_maintenance()
    local ctx = self:_build_context()
    if ctx.in_combat == true then
        return false
    end

    if ctx.eating_or_drinking == true then
        return true
    end

    local provider = self:get_provider(ctx)
    if provider and provider.should_hold_maintenance then
        local ok, hold = pcall(provider.should_hold_maintenance, provider, ctx)
        if ok then
            return hold == true
        end
    end

    local class_id = tonumber(ctx.class_id) or 0
    local runtime = type(ctx.routine_policy) == "table" and ctx.routine_policy or nil

    local eat_threshold = nil
    local drink_threshold = nil
    if class_id == 2 then
        local paladin = type(runtime) == "table" and runtime.paladin or nil
        local retribution = type(paladin) == "table" and paladin.retribution or nil
        eat_threshold = tonumber(type(retribution) == "table" and retribution.eat_health_pct or nil)
        drink_threshold = tonumber(type(retribution) == "table" and retribution.drink_mana_pct or nil)
    end

    if eat_threshold == nil and type(runtime) == "table" then
        eat_threshold = tonumber(runtime.eat_health_pct)
    end
    if drink_threshold == nil and type(runtime) == "table" then
        drink_threshold = tonumber(runtime.drink_mana_pct)
    end

    local needs_health_rest = eat_threshold and ctx.player_health_pct and ctx.player_health_pct < eat_threshold
    local needs_mana_rest = drink_threshold and ctx.player_mana_pct and ctx.player_mana_pct < drink_threshold
    return needs_health_rest == true or needs_mana_rest == true
end

---@private
---@param action table
---@param ctx table
---@return number|nil
---@return string|nil
function RotationEngine:_resolve_action_spell_id(action, ctx)
    if action.action_type ~= "cast_spell_target"
        and action.action_type ~= "cast_spell_self"
        and action.action_type ~= "cast_spell_position" then
        return nil, nil
    end

    local raw = action.spell_id
    if type(raw) == "function" then
        local ok, dynamic_spell_id = pcall(raw, ctx, action)
        if not ok then
            return nil, ErrorCodes.CAST_GUARD_BLOCKED
        end
        raw = dynamic_spell_id
    end

    local spell_id = tonumber(raw)
    if not spell_id or spell_id <= 0 then
        return nil, ErrorCodes.CAST_GUARD_BLOCKED
    end

    action._resolved_spell_id = spell_id
    return spell_id, nil
end

---@private
---@param action table
---@param ctx table
---@return any|nil
---@return string|nil
function RotationEngine:_resolve_action_position(action, ctx)
    if action.action_type ~= "cast_spell_position" then
        return nil, nil
    end

    local raw = action.position
    if type(raw) == "function" then
        local ok, dynamic_position = pcall(raw, ctx, action)
        if not ok then
            return nil, ErrorCodes.CAST_GUARD_BLOCKED
        end
        raw = dynamic_position
    end

    if raw == nil then
        raw = ctx and ctx.target_position or nil
    end

    if raw == nil then
        return nil, ErrorCodes.CAST_GUARD_BLOCKED
    end

    action._resolved_position = raw
    return raw, nil
end

---@private
---@param action table
---@param ctx table
---@return boolean
---@return string|nil
function RotationEngine:_execute_queue_first(action, ctx)
    if action.action_type == "use_best_health_potion" and self._izi and self._izi.use_best_health_potion_safe then
        local ok, used = pcall(self._izi.use_best_health_potion_safe)
        if ok and used == true then
            return true, nil
        end
    end

    if action.action_type == "use_best_mana_potion" and self._izi and self._izi.use_best_mana_potion_safe then
        local ok, used = pcall(self._izi.use_best_mana_potion_safe)
        if ok and used == true then
            return true, nil
        end
    end

    if not self._queue then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    local cast_target = unwrap_game_object(ctx.target)
    local cast_self = unwrap_game_object(ctx.player)
    local spell_id = tonumber(action._resolved_spell_id or action.spell_id) or 0
    local item_id = tonumber(action._resolved_item_id) or 0
    local qp = queue_priority(action.priority)

    if action.action_type == "cast_spell_target" and self._queue.queue_spell_target then
        if not is_native_game_object(cast_target) then
            return false, ErrorCodes.CAST_INVALID_TARGET
        end
        local ok = pcall(self._queue.queue_spell_target, self._queue, spell_id, cast_target, qp,
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
        local ok = pcall(self._queue.queue_spell_target, self._queue, spell_id, cast_self, qp,
            "SentinelCore", true)
        if not ok then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        return true, nil
    end

    if action.action_type == "cast_spell_position" and self._queue.queue_spell_position then
        local cast_position = action._resolved_position
        if cast_position == nil then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        local ok = pcall(self._queue.queue_spell_position, self._queue, spell_id, cast_position, qp,
            "SentinelCore", action.allow_movement)
        if not ok then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        return true, nil
    end

    if action.action_type == "use_item_self" and self._queue.queue_item_self then
        if item_id <= 0 then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        local ok = pcall(self._queue.queue_item_self, self._queue, item_id, qp, "SentinelCore")
        if not ok then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        return true, nil
    end

    if (action.action_type == "use_best_health_potion" or action.action_type == "use_best_mana_potion")
        and self._queue.queue_item_self then
        if item_id <= 0 then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        local ok = pcall(self._queue.queue_item_self, self._queue, item_id, qp, "SentinelCore")
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

    local spell_id = tonumber(action._resolved_spell_id or action.spell_id) or 0
    local item_id = tonumber(action._resolved_item_id) or 0

    if action.action_type == "cast_spell_target"
        or action.action_type == "cast_spell_self"
        or action.action_type == "cast_spell_position" then
        if core and core.spell_book and core.spell_book.is_usable_spell then
            local usable = core.spell_book.is_usable_spell(spell_id)
            if usable == false then
                return false, ErrorCodes.CAST_GUARD_BLOCKED
            end
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
            local ok = core.input.cast_target_spell(spell_id, cast_target)
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
            local ok = core.input.cast_target_spell(spell_id, cast_self)
            if ok then
                self._last_cast_at = now
                return true, nil
            end
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
    end

    if action.action_type == "cast_spell_position" then
        local cast_position = action._resolved_position
        if cast_position == nil then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        if core and core.input and core.input.cast_position_spell then
            local ok = core.input.cast_position_spell(spell_id, cast_position)
            if ok then
                self._last_cast_at = now
                return true, nil
            end
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
    end

    if action.action_type == "use_item_self" then
        if item_id <= 0 then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        if core and core.input and core.input.use_item then
            local ok = core.input.use_item(item_id)
            if ok then
                self._last_cast_at = now
                return true, nil
            end
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        if self._izi and self._izi.item then
            local ok_item, item = pcall(self._izi.item, item_id)
            if ok_item and item and item.use_self_safe then
                local ok_use, used = pcall(item.use_self_safe, item, "SentinelCore")
                if ok_use and used == true then
                    self._last_cast_at = now
                    return true, nil
                end
            end
        end
    end

    if action.action_type == "use_best_health_potion" or action.action_type == "use_best_mana_potion" then
        if item_id <= 0 then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        if core and core.input and core.input.use_item then
            local ok = core.input.use_item(item_id)
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
    if action.max_player_mana_pct and (player_mana_pct == nil or player_mana_pct > action.max_player_mana_pct) then
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

    local spell_id, spell_err = self:_resolve_action_spell_id(action, ctx)
    if spell_err then
        return false, spell_err
    end

    local _, pos_err = self:_resolve_action_position(action, ctx)
    if pos_err then
        return false, pos_err
    end

    if action.action_type == "use_item_self"
        or action.action_type == "use_best_health_potion"
        or action.action_type == "use_best_mana_potion" then
        local resolved_item = self:_resolve_item_id(action, ctx)
        if action.action_type == "use_best_health_potion" and self._izi and self._izi.use_best_health_potion_safe then
            action._resolved_item_id = resolved_item
        elseif action.action_type == "use_best_mana_potion" and self._izi and self._izi.use_best_mana_potion_safe then
            action._resolved_item_id = resolved_item
        elseif not resolved_item or resolved_item <= 0 then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        else
            action._resolved_item_id = resolved_item
        end
    end

    if action.requires_castable_check == true and self._spell_helper and self._spell_helper.is_spell_castable then
        local caster = unwrap_game_object(ctx.player)
        local target = nil
        if action.action_type == "cast_spell_self" then
            target = caster
        elseif action.action_type == "cast_spell_position" then
            target = unwrap_game_object(ctx.target) or caster
        else
            target = unwrap_game_object(ctx.target)
        end
        if not is_native_game_object(caster) or not is_native_game_object(target) then
            return false, ErrorCodes.CAST_INVALID_TARGET
        end

        local skip_facing = action.skip_facing == true
        local skip_range = action.skip_range == true
        local ok, castable = pcall(
            self._spell_helper.is_spell_castable,
            self._spell_helper,
            spell_id,
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

---@return table[]|nil
---@return string|nil
function RotationEngine:generate_maintenance_plan()
    local ctx = self:_build_context()
    local provider = self:get_provider(ctx)
    if not provider then
        return nil, ErrorCodes.ROTATION_UNAVAILABLE
    end

    local plan = self:build_maintenance_plan(ctx, provider)
    return plan, nil
end

---@private
---@param plan table[]
---@param ctx table
---@return boolean
---@return string|nil
function RotationEngine:_execute_plan(plan, ctx)
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

---@return boolean
---@return string|nil
function RotationEngine:tick_once()
    local ctx = self:_build_context()
    local provider = self:get_provider(ctx)
    if not provider then
        return false, ErrorCodes.ROTATION_UNAVAILABLE
    end

    local plan = self:build_plan(ctx, provider)
    return self:_execute_plan(plan, ctx)
end

---@return boolean
---@return string|nil
function RotationEngine:tick_maintenance_once()
    local ctx = self:_build_context()
    local provider = self:get_provider(ctx)
    if not provider then
        return false, ErrorCodes.ROTATION_UNAVAILABLE
    end

    local plan = self:build_maintenance_plan(ctx, provider)
    return self:_execute_plan(plan, ctx)
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
