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

local RETRY_BLOCK_REASON = "__ACTION_RETRY_PENDING__"

---@private
---@param unit any
---@return number
local function safe_unit_guid(unit)
    if not unit then
        return 0
    end
    if type(unit.get_guid) == "function" then
        local ok, guid = pcall(unit.get_guid, unit)
        if ok and tonumber(guid) and tonumber(guid) > 0 then
            return tonumber(guid)
        end
    end
    if type(unit.get_object_guid) == "function" then
        local ok, guid = pcall(unit.get_object_guid, unit)
        if ok and tonumber(guid) and tonumber(guid) > 0 then
            return tonumber(guid)
        end
    end
    return 0
end

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
---@param target any
---@param action table
local function prepare_target_cast(target, action)
    if not target then
        return
    end

    local should_set_target = true
    if action and (action.action_type == "cast_spell_self" or action.skip_target_swap == true) then
        should_set_target = false
    end

    if should_set_target and core and core.input and type(core.input.set_target) == "function" then
        pcall(core.input.set_target, target)
    end

    if action and action.skip_facing == true then
        return
    end

    if core and core.input and type(core.input.look_at) == "function" then
        local pos = nil
        if type(target.get_position) == "function" then
            local ok, value = pcall(target.get_position, target)
            if ok then
                pos = value
            end
        end
        if pos then
            pcall(core.input.look_at, pos)
        end
    end
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
---@field private _last_blocked_event_at number
---@field private _last_blocked_event_key string
---@field private _action_retry_until table<string, number>
---@field private _action_retry_last_sweep_at number
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
    o._last_blocked_event_at = 0
    o._last_blocked_event_key = ""
    o._action_retry_until = {}
    o._action_retry_last_sweep_at = 0

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
---@param item_obj any
---@return string
local function safe_item_name(item_obj)
    if not item_obj or type(item_obj.get_name) ~= "function" then
        return ""
    end
    local ok, name = pcall(item_obj.get_name, item_obj)
    if not ok or type(name) ~= "string" then
        return ""
    end
    return string.lower(name)
end

---@private
---@param value any
---@return string
local function normalize_text(value)
    if type(value) ~= "string" then
        return ""
    end
    return string.lower(value)
end

---@private
---@param row table
---@param keys string[]
---@return boolean
local function row_has_true_flag(row, keys)
    if type(row) ~= "table" then
        return false
    end
    for i = 1, #keys do
        if row[keys[i]] == true then
            return true
        end
    end
    return false
end

---@private
---@param row table
---@return string
local function row_consumable_text(row)
    if type(row) ~= "table" then
        return ""
    end

    local parts = {
        normalize_text(row.kind),
        normalize_text(row.category),
        normalize_text(row.type),
        normalize_text(row.consumable_type),
        normalize_text(row.subtype),
        normalize_text(row.name),
    }

    local out = ""
    for i = 1, #parts do
        if parts[i] ~= "" then
            if out == "" then
                out = parts[i]
            else
                out = out .. " " .. parts[i]
            end
        end
    end
    return out
end

---@private
---@param text string
---@param tokens string[]
---@return boolean
local function text_contains_any(text, tokens)
    local haystack = normalize_text(text)
    if haystack == "" then
        return false
    end

    for i = 1, #tokens do
        local needle = normalize_text(tokens[i])
        if needle ~= "" and string.find(haystack, needle, 1, true) ~= nil then
            return true
        end
    end
    return false
end

---@private
---@param row table
---@param kind string
---@return boolean
local function consumable_matches_kind(row, kind)
    if type(row) ~= "table" then
        return false
    end
    if row.is_health_potion == true or row.is_mana_potion == true then
        return false
    end

    local text = row_consumable_text(row)
    local item_obj = unwrap_item_object(row and (row.item or row))
    local item_name = safe_item_name(item_obj)
    if item_name ~= "" then
        if text == "" then
            text = item_name
        else
            text = text .. " " .. item_name
        end
    end

    local food = row_has_true_flag(row, {
        "is_food",
        "is_eat",
        "is_edible",
        "is_food_consumable",
    }) or text_contains_any(text, {
        "food",
        "bread",
        "cheese",
        "biscuit",
        "venison",
        "meat",
        "fish",
        "stew",
        "banana",
        "roll",
    })
    local water = row_has_true_flag(row, {
        "is_water",
        "is_drink",
        "is_drinkable",
        "is_water_consumable",
    }) or text_contains_any(text, {
        "water",
        "drink",
        "juice",
        "tea",
        "milk",
        "refreshment",
    })

    if kind == "food" then
        return food
    end
    if kind == "water" then
        return water
    end
    if kind == "food_or_water" then
        return food or water
    end
    return false
end

---@private
---@param row table
---@return number
local function consumable_row_item_id(row)
    if type(row) ~= "table" then
        return 0
    end
    local direct = tonumber(row.item_id) or 0
    if direct > 0 then
        return direct
    end

    local item_obj = unwrap_item_object(row.item or row)
    return safe_item_id(item_obj)
end

---@private
---@param consumables table
---@param kind string
---@return number|nil
local function best_consumable_item_id(consumables, kind)
    if type(consumables) ~= "table" then
        return nil
    end

    local selected = nil
    for i = 1, #consumables do
        local row = consumables[i]
        if consumable_matches_kind(row, kind) then
            local item_id = consumable_row_item_id(row)
            if item_id > 0 and (selected == nil or item_id > selected) then
                selected = item_id
            end
        end
    end
    return selected
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
                    local item_id = consumable_row_item_id(row)
                    if item_id > 0 and (selected == nil or item_id > selected) then
                        selected = item_id
                    end
                end
            end
            return selected
        end
    end

    if action.action_type == "use_item_self"
        and type(action.item_kind) == "string"
        and action.item_kind ~= ""
        and self._inventory_helper
        and self._inventory_helper.get_current_consumables_list then
        if self._inventory_helper.update_consumables_list then
            pcall(self._inventory_helper.update_consumables_list, self._inventory_helper)
        end

        local list_ok, consumables = pcall(self._inventory_helper.get_current_consumables_list, self._inventory_helper)
        if list_ok and type(consumables) == "table" then
            local matched = {}
            for i = 1, #consumables do
                local row = consumables[i]
                if consumable_matches_kind(row, string.lower(action.item_kind)) then
                    local item_id = consumable_row_item_id(row)
                    if item_id > 0 then
                        matched[item_id] = true
                    end
                end
            end

            if type(action.item_id) == "table" then
                for i = 1, #action.item_id do
                    local preferred_id = tonumber(action.item_id[i]) or 0
                    if preferred_id > 0 and matched[preferred_id] == true then
                        return preferred_id
                    end
                end
            end

            local selected = best_consumable_item_id(consumables, string.lower(action.item_kind))
            if selected and selected > 0 then
                return selected
            end
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

---@private
---@param action table
---@param ctx table
function RotationEngine:_on_action_executed(action, ctx)
    if type(action) ~= "table" or action.action_type ~= "use_item_self" then
        return
    end

    local lock_secs = tonumber(action.rest_lock_secs) or 0
    if lock_secs <= 0 then
        return
    end

    local now = tonumber(ctx and ctx.now) or ((core and core.time and core.time()) or 0)
    if self._blackboard and self._blackboard.set then
        local lock_until = now + lock_secs
        local item_kind = string.lower(tostring(action.item_kind or ""))
        if item_kind ~= "" then
            self._blackboard:set("rotation.rest.lock_until." .. item_kind, lock_until)
        else
            self._blackboard:set("rotation.rest.lock_until", lock_until)
        end
    end
end

---@private
---@param action table|nil
---@return string
function RotationEngine:_rest_lock_key_for_action(action)
    if type(action) == "table" then
        local kind = string.lower(tostring(action.item_kind or ""))
        if kind ~= "" then
            return "rotation.rest.lock_until." .. kind
        end
    end
    return "rotation.rest.lock_until"
end

---@private
---@param action table|nil
---@param now number
---@return number
function RotationEngine:_rest_lock_remaining(action, now)
    if not self._blackboard or type(self._blackboard.get) ~= "function" then
        return 0
    end

    local scoped_key = self:_rest_lock_key_for_action(action)
    local scoped_until = tonumber(self._blackboard:get(scoped_key, 0)) or 0
    local generic_until = tonumber(self._blackboard:get("rotation.rest.lock_until", 0)) or 0
    local lock_until = math.max(scoped_until, generic_until)
    if lock_until <= now then
        return 0
    end
    return lock_until - now
end

---@return boolean
function RotationEngine:should_hold_maintenance()
    local ctx = self:_build_context()
    if ctx.in_combat == true then
        return false
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
---@param reason string|nil
---@return string|nil
function RotationEngine:_normalize_block_reason(reason)
    if reason == RETRY_BLOCK_REASON then
        return ErrorCodes.CAST_GUARD_BLOCKED
    end
    return reason
end

---@private
---@param action table
---@param ctx table
---@return number
function RotationEngine:_action_retry_target_guid(action, ctx)
    local action_type = tostring(action and action.action_type or "")
    local target = nil
    if action_type == "cast_spell_target" then
        target = unwrap_game_object(ctx and ctx.target)
    elseif action_type == "cast_spell_self" then
        target = unwrap_game_object(ctx and ctx.player)
    elseif action_type == "cast_spell_position" then
        target = unwrap_game_object(ctx and ctx.target) or unwrap_game_object(ctx and ctx.player)
    else
        target = unwrap_game_object(ctx and ctx.player)
    end
    return safe_unit_guid(target)
end

---@private
---@param action table
---@param ctx table
---@return string
function RotationEngine:_action_retry_key(action, ctx)
    local action_type = tostring(action and action.action_type or "")
    local spell_id = tonumber(action and (action._resolved_spell_id or action.spell_id)) or 0
    local item_id = tonumber(action and action._resolved_item_id) or 0
    if item_id <= 0 then
        item_id = tonumber(action and action.item_id) or 0
    end
    local target_guid = self:_action_retry_target_guid(action, ctx)
    return string.format("%s|%d|%d|%d", action_type, spell_id, item_id, target_guid)
end

---@private
---@param now number
function RotationEngine:_prune_action_retry_windows(now)
    local sweep_interval = tonumber(self._cfg.action_retry_sweep_interval) or 2.0
    if (now - (tonumber(self._action_retry_last_sweep_at) or 0)) < sweep_interval then
        return
    end
    self._action_retry_last_sweep_at = now

    local active_count = 0
    for key, retry_until in pairs(self._action_retry_until) do
        if tonumber(retry_until) and retry_until > now then
            active_count = active_count + 1
        else
            self._action_retry_until[key] = nil
        end
    end

    local max_entries = tonumber(self._cfg.action_retry_max_entries) or 512
    if active_count <= max_entries then
        return
    end

    local overflow = active_count - max_entries
    for key, _ in pairs(self._action_retry_until) do
        self._action_retry_until[key] = nil
        overflow = overflow - 1
        if overflow <= 0 then
            break
        end
    end
end

---@private
---@param spell_id number
---@return number|nil
function RotationEngine:_resolve_spell_retry_backoff(spell_id)
    if spell_id <= 0 or not core or not core.spell_book then
        return nil
    end

    local remaining = nil
    if type(core.spell_book.get_spell_cooldown_remaining) == "function" then
        local ok_remaining, value = pcall(core.spell_book.get_spell_cooldown_remaining, spell_id)
        if ok_remaining and tonumber(value) then
            remaining = tonumber(value)
        end
    end

    if (remaining == nil or remaining <= 0) and type(core.spell_book.get_spell_cooldown) == "function" then
        local ok_cd, a, b = pcall(core.spell_book.get_spell_cooldown, spell_id)
        if ok_cd then
            if type(a) == "table" then
                remaining = tonumber(a.remaining)
                    or tonumber(a.cooldown_remaining)
                    or tonumber(a.time_left)
                    or tonumber(a.left)
                    or tonumber(a.duration)
            elseif tonumber(a) and tonumber(a) > 0 and tonumber(a) <= 30 then
                remaining = tonumber(a)
            elseif tonumber(b) and tonumber(b) > 0 and tonumber(b) <= 30 and tonumber(a) == 0 then
                remaining = tonumber(b)
            end
        end
    end

    local gcd = nil
    if type(core.spell_book.get_global_cooldown) == "function" then
        local ok_gcd, value = pcall(core.spell_book.get_global_cooldown)
        if ok_gcd and tonumber(value) then
            gcd = tonumber(value)
        end
    end

    if remaining and remaining > 50 then
        remaining = remaining / 1000.0
    end
    if gcd and gcd > 50 then
        gcd = gcd / 1000.0
    end

    if remaining == nil or remaining < 0 then
        remaining = 0
    end
    if gcd and gcd > remaining then
        remaining = gcd
    end

    if remaining > 0 then
        return remaining
    end
    return nil
end

---@private
---@param action table
---@param ctx table
---@param reason string|nil
---@param now number
---@return number
function RotationEngine:_estimate_action_retry_backoff(action, ctx, reason, now)
    local backoff = tonumber(self._cfg.action_retry_default_backoff) or 0.25
    local throttle = tonumber(self._cfg.action_throttle) or 0.12
    local since_cast = now - (tonumber(self._last_cast_at) or 0)
    if since_cast < throttle then
        backoff = math.max(backoff, throttle - since_cast)
    end

    if action.allow_movement ~= true and ctx.player_is_moving == true then
        backoff = math.max(backoff, tonumber(self._cfg.action_retry_moving_backoff) or 0.18)
    end

    local player_mana_pct = tonumber(ctx.player_mana_pct)
    if action.min_player_mana_pct and player_mana_pct and player_mana_pct < action.min_player_mana_pct then
        local deficit = action.min_player_mana_pct - player_mana_pct
        backoff = math.max(backoff, math.min(1.75, 0.30 + (deficit * 3.0)))
    end
    if action.max_player_mana_pct and player_mana_pct and player_mana_pct > action.max_player_mana_pct then
        backoff = math.max(backoff, tonumber(self._cfg.action_retry_resource_backoff) or 0.40)
    end

    local player_health_pct = tonumber(ctx.player_health_pct)
    if action.min_player_health_pct and player_health_pct and player_health_pct < action.min_player_health_pct then
        backoff = math.max(backoff, tonumber(self._cfg.action_retry_resource_backoff) or 0.40)
    end

    local target_health_pct = tonumber(ctx.target_health_pct)
    if action.min_target_health_pct and target_health_pct and target_health_pct < action.min_target_health_pct then
        backoff = math.max(backoff, tonumber(self._cfg.action_retry_threshold_backoff) or 0.30)
    end
    if action.max_target_health_pct and target_health_pct and target_health_pct > action.max_target_health_pct then
        backoff = math.max(backoff, tonumber(self._cfg.action_retry_threshold_backoff) or 0.30)
    end

    local target_distance = tonumber(ctx.target_distance)
    if action.max_target_distance and target_distance and target_distance > action.max_target_distance then
        backoff = math.max(backoff, tonumber(self._cfg.action_retry_range_backoff) or 0.28)
    end
    if action.min_target_distance and target_distance and target_distance < action.min_target_distance then
        backoff = math.max(backoff, tonumber(self._cfg.action_retry_range_backoff) or 0.28)
    end

    if action.action_type == "use_item_self" then
        local lock_remaining = self:_rest_lock_remaining(action, now)
        if lock_remaining > 0 then
            backoff = math.max(backoff, lock_remaining)
        end
    end

    local spell_id = tonumber(action._resolved_spell_id or action.spell_id) or 0
    local cooldown_backoff = self:_resolve_spell_retry_backoff(spell_id)
    if cooldown_backoff then
        backoff = math.max(backoff, cooldown_backoff)
    end

    if reason == ErrorCodes.TARGET_NOT_FOUND or reason == ErrorCodes.CAST_INVALID_TARGET then
        backoff = math.max(backoff, tonumber(self._cfg.action_retry_invalid_target_backoff) or 0.45)
    end

    local min_backoff = tonumber(self._cfg.action_retry_min_backoff) or 0.12
    local max_backoff = tonumber(self._cfg.action_retry_max_backoff) or 2.00
    if backoff < min_backoff then
        backoff = min_backoff
    elseif backoff > max_backoff then
        backoff = max_backoff
    end
    return backoff
end

---@private
---@param action table
---@param ctx table
---@param reason string|nil
---@param now number
function RotationEngine:_schedule_action_retry(action, ctx, reason, now)
    if reason == RETRY_BLOCK_REASON then
        return
    end

    local key = self:_action_retry_key(action, ctx)
    if key == "" then
        return
    end

    local normalized_reason = self:_normalize_block_reason(reason) or ErrorCodes.CAST_GUARD_BLOCKED
    local backoff = self:_estimate_action_retry_backoff(action, ctx, normalized_reason, now)
    local retry_until = now + backoff
    local existing = tonumber(self._action_retry_until[key]) or 0
    if retry_until > existing then
        self._action_retry_until[key] = retry_until
    end
end

---@private
---@param action table
---@param ctx table
function RotationEngine:_clear_action_retry(action, ctx)
    local key = self:_action_retry_key(action, ctx)
    if key == "" then
        return
    end
    self._action_retry_until[key] = nil
end

---@private
---@param action table
---@param ctx table
---@param now number
---@return boolean
function RotationEngine:_is_action_retry_blocked(action, ctx, now)
    self:_prune_action_retry_windows(now)
    local key = self:_action_retry_key(action, ctx)
    if key == "" then
        return false
    end

    local retry_until = tonumber(self._action_retry_until[key]) or 0
    if retry_until > now then
        return true
    end

    if retry_until > 0 then
        self._action_retry_until[key] = nil
    end
    return false
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
    local now = (core and core.time and core.time()) or 0

    if action.action_type == "use_best_health_potion" and self._izi and self._izi.use_best_health_potion_safe then
        local ok, used = pcall(self._izi.use_best_health_potion_safe)
        if ok and used == true then
            self._last_cast_at = now
            return true, nil
        end
    end

    if action.action_type == "use_best_mana_potion" and self._izi and self._izi.use_best_mana_potion_safe then
        local ok, used = pcall(self._izi.use_best_mana_potion_safe)
        if ok and used == true then
            self._last_cast_at = now
            return true, nil
        end
    end

    if not self._queue then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    local throttle = tonumber(self._cfg.action_throttle) or 0.12
    if now - self._last_cast_at < throttle then
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
        prepare_target_cast(cast_target, action)
        local ok = pcall(self._queue.queue_spell_target, self._queue, spell_id, cast_target, qp,
            "SentinelCore", action.allow_movement)
        if not ok then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        self._last_cast_at = now
        return true, nil
    end

    if action.action_type == "cast_spell_self" and self._queue.queue_spell_self then
        if spell_id <= 0 then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        local ok = pcall(
            self._queue.queue_spell_self,
            self._queue,
            spell_id,
            qp,
            "SentinelCore",
            action.allow_movement
        )
        if not ok then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
        self._last_cast_at = now
        return true, nil
    end

    if action.action_type == "cast_spell_self" then
        if not is_native_game_object(cast_self) then
            return false, ErrorCodes.CAST_INVALID_TARGET
        end
        -- Do not route self-casts through queue_spell_target; some queue adapters swap target to self.
        return false, ErrorCodes.CAST_GUARD_BLOCKED
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
        self._last_cast_at = now
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
        self._last_cast_at = now
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
        self._last_cast_at = now
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
            local ok_usable, usable = pcall(core.spell_book.is_usable_spell, spell_id)
            if ok_usable and usable == false then
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
        prepare_target_cast(cast_target, action)
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
        if core and core.input and core.input.cast_self_spell then
            local ok = core.input.cast_self_spell(spell_id)
            if ok then
                self._last_cast_at = now
                return true, nil
            end
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end

        prepare_target_cast(cast_self, action)
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
    local now = tonumber(ctx and ctx.now) or ((core and core.time and core.time()) or 0)

    if action.action_type == "cast_spell_target" and not ctx.target then
        return false, ErrorCodes.TARGET_NOT_FOUND
    end

    if action.action_type == "use_item_self" then
        local lock_remaining = self:_rest_lock_remaining(action, now)
        if lock_remaining > 0 then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
    end

    if action.target_must_be_casting == true and ctx.target_is_casting ~= true then
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end
    if action.allow_movement ~= true and ctx.player_is_moving == true then
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

    if spell_id and spell_id > 0
        and (action.action_type == "cast_spell_target"
            or action.action_type == "cast_spell_self"
            or action.action_type == "cast_spell_position")
        and core and core.spell_book and core.spell_book.is_usable_spell then
        local ok_usable, usable = pcall(core.spell_book.is_usable_spell, spell_id)
        if ok_usable and usable == false then
            return false, ErrorCodes.CAST_GUARD_BLOCKED
        end
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

    if self:_is_action_retry_blocked(action, ctx, now) then
        return false, RETRY_BLOCK_REASON
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
        self:_clear_action_retry(action, ctx)
        self:_on_action_executed(action, ctx)
        self._event_bus:emit(Events.ROTATION_EXECUTED, {
            action = action,
            adapter = "queue",
        })
        return true, nil
    end

    local fallback_ok, fallback_err = self:_execute_guarded_fallback(action, ctx)
    if fallback_ok then
        self:_clear_action_retry(action, ctx)
        self:_on_action_executed(action, ctx)
        self._event_bus:emit(Events.ROTATION_EXECUTED, {
            action = action,
            adapter = "fallback",
        })
        return true, nil
    end

    return false, fallback_err or err
end

---@private
---@param action table
---@param reason string|nil
---@param index number
---@return table
function RotationEngine:_blocked_entry(action, reason, index)
    return {
        index = index,
        reason = reason or ErrorCodes.CAST_GUARD_BLOCKED,
        action_type = tostring(action and action.action_type or ""),
        priority = tonumber(action and action.priority) or 0,
        spell_id = tonumber(action and (action._resolved_spell_id or action.spell_id)) or 0,
        item_id = tonumber(action and (action._resolved_item_id or action.item_id)) or 0,
    }
end

---@private
---@param reason string|nil
---@param blocked table[]
function RotationEngine:_emit_rotation_blocked(reason, blocked)
    if not self._event_bus then
        return
    end

    local now = (core and core.time and core.time()) or 0
    local top = blocked and blocked[1] or nil
    local key = string.format(
        "%s|%s|%d|%d",
        tostring(reason or ErrorCodes.CAST_GUARD_BLOCKED),
        tostring(top and top.action_type or ""),
        tonumber(top and top.spell_id) or 0,
        tonumber(top and top.item_id) or 0
    )
    if key == self._last_blocked_event_key and (now - self._last_blocked_event_at) < 2.00 then
        return
    end

    self._last_blocked_event_key = key
    self._last_blocked_event_at = now
    self._event_bus:emit(Events.ROTATION_BLOCKED, {
        timestamp = now,
        error_code = reason or ErrorCodes.CAST_GUARD_BLOCKED,
        blocked = blocked or {},
    })
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
---@param opts? table
---@return boolean
---@return string|nil
function RotationEngine:_execute_plan(plan, ctx, opts)
    local emit_blocked = not (type(opts) == "table" and opts.emit_blocked == false)
    if #plan == 0 then
        if emit_blocked then
            self:_emit_rotation_blocked(ErrorCodes.CAST_GUARD_BLOCKED, {})
        end
        return false, ErrorCodes.CAST_GUARD_BLOCKED
    end

    local now = tonumber(ctx and ctx.now) or ((core and core.time and core.time()) or 0)
    local last_err = ErrorCodes.CAST_GUARD_BLOCKED
    local blocked = {}
    for i = 1, #plan do
        local action = plan[i]
        local allowed, guard_err = self:_action_allowed(action, ctx)
        if allowed then
            local executed, exec_err = self:execute_action(action, ctx)
            if executed then
                return true, nil
            end
            local normalized_exec_err = self:_normalize_block_reason(exec_err or guard_err) or ErrorCodes.CAST_GUARD_BLOCKED
            last_err = normalized_exec_err or last_err
            self:_schedule_action_retry(action, ctx, normalized_exec_err, now)
            if #blocked < 4 then
                blocked[#blocked + 1] = self:_blocked_entry(action, normalized_exec_err, i)
            end
        else
            local normalized_guard_err = self:_normalize_block_reason(guard_err) or ErrorCodes.CAST_GUARD_BLOCKED
            last_err = normalized_guard_err or last_err
            self:_schedule_action_retry(action, ctx, guard_err, now)
            if #blocked < 4 then
                blocked[#blocked + 1] = self:_blocked_entry(action, normalized_guard_err, i)
            end
        end
    end

    if emit_blocked then
        self:_emit_rotation_blocked(last_err, blocked)
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
    return self:_execute_plan(plan, ctx, { emit_blocked = false })
end

---@return table
function RotationEngine:get_movement_profile()
    local ctx = self:_build_context()
    local provider = self:get_provider(ctx)

    local movement = {}
    if provider and provider.get_movement_profile then
        local ok_profile, profile = pcall(provider.get_movement_profile, provider, ctx)
        if ok_profile and type(profile) == "table" then
            movement = profile
        end
    end

    if movement.combat_chase_range == nil and provider and provider.get_pull_profile then
        local ok_pull, pull = pcall(provider.get_pull_profile, provider, ctx)
        if ok_pull and type(pull) == "table" then
            movement.combat_chase_range = tonumber(pull.combat_chase_range) or tonumber(pull.max_pull_range)
        end
    end

    return {
        combat_chase_range = tonumber(movement.combat_chase_range),
    }
end

---@return table
function RotationEngine:get_pull_profile()
    local ctx = self:_build_context()
    local provider = self:get_provider(ctx)
    if provider and provider.get_pull_profile then
        local ok_profile, profile = pcall(provider.get_pull_profile, provider, ctx)
        if ok_profile and type(profile) == "table" then
            return profile
        end
    end
    return {
        pull_spell_id = nil,
        max_pull_range = 25,
    }
end

return RotationEngine
