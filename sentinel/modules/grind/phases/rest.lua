local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local bag_scanner = require("modules/grind/bag_scanner")
local ConsumableIds = require("modules/grind/consumable_ids")

local Rest = {}

local FOOD_ITEMS = ConsumableIds.FOOD_ITEMS
local WATER_ITEMS = ConsumableIds.WATER_ITEMS


-- Diagnostic: throttled rest-gate logging
local _last_rest_diag_ms = 0
local DIAG_INTERVAL_MS = 3000

---Scan bags for an item matching the lookup set.
---@param lookup table<number, boolean>
---@return number|nil item_id of the first match, or nil
local function find_consumable_in_bags(lookup)
    local found_id = nil
    bag_scanner.for_each_item(function(obj)
        if found_id then return end
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if ok_id and raw_id then
            local item_id = tonumber(raw_id)
            if item_id and lookup[item_id] then
                found_id = item_id
            end
        end
    end)
    return found_id
end

---Build the rest phase sub-tree.
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT node
function Rest.build(event_bus, nav_adapter)
    -- One-shot eating/drinking state (upvalues shared across ticks)
    local _eat_active = false
    local _eat_started_ms = 0
    local _eat_initial_hp = 0
    local _eat_reuse_count = 0

    local _drink_active = false
    local _drink_started_ms = 0
    local _drink_initial_mana = 0
    local _drink_reuse_count = 0

    local MAX_REUSE_ATTEMPTS = 5
    local CONSUME_VERIFY_MS = 5000  -- Check if consuming actually started after 5s
    local CONSUME_MIN_GAIN = 0.05   -- Expect at least 5% gain if consuming (eating/drinking gives ~15%+ in 5s)

    return BT.sequence("rest", {
        -- Gate: grind must be enabled
        BT.condition("grind_enabled", function(bb)
            return bb:get("module.grind.enabled") == true
        end),

        -- Gate: combat module must not be actively engaged.
        -- Uses combat.source instead of player.in_combat because WoW's combat
        -- timer lingers 5-6s after a kill, blocking rest entirely.
        BT.condition("not_engaged", function(bb)
            local source = bb:get("combat.source")
            if source ~= nil then
                local now = bb:get("system.now_ms", 0)
                if now - _last_rest_diag_ms >= DIAG_INTERVAL_MS then
                    _last_rest_diag_ms = now
                    if core and core.log then
                        pcall(core.log, "[Rest] blocked: combat.source=" .. tostring(source))
                    end
                end
                return false
            end
            return true
        end),

        -- At least one rest trigger must fire
        BT.selector("needs_rest", {
            BT.condition("health_below_eat_threshold", function(bb)
                local pct = bb:get("player.health_pct", 1)
                local threshold = bb:get("module.grind.health_eat_pct", 0.50)
                return pct < threshold
            end),
            BT.condition("mana_below_drink_threshold", function(bb)
                local pct = bb:get("player.mana_pct", 1)
                local threshold = bb:get("module.grind.mana_drink_pct", 0.40)
                return pct < threshold
            end),
            -- Diagnostic: both thresholds passed, log actual values
            BT.action("rest_diag_skip", function(bb)
                local now = bb:get("system.now_ms", 0)
                if now - _last_rest_diag_ms >= DIAG_INTERVAL_MS then
                    _last_rest_diag_ms = now
                    if core and core.log then
                        pcall(core.log, string.format(
                            "[Rest] skip: hp=%.2f(>=%.2f) mana=%.2f(>=%.2f)",
                            bb:get("player.health_pct", 1),
                            bb:get("module.grind.health_eat_pct", 0.50),
                            bb:get("player.mana_pct", 1),
                            bb:get("module.grind.mana_drink_pct", 0.40)))
                    end
                end
                return Status.FAILURE
            end),
        }),

        -- Call profile:prepare_rest() if available (e.g. mage conjuring)
        -- Respects RUNNING from profile (e.g. mage waiting for spirit regen to conjure)
        -- and stays RUNNING while casting to avoid sitting mid-conjure.
        BT.action("prepare_rest", function(bb)
            local profile = bb:get("module.combat.profile")
            local profile_result = Status.SUCCESS
            if profile and type(profile.prepare_rest) == "function" then
                profile_result = profile:prepare_rest(bb)
            end
            if bb:get("player.is_casting", false) == true
            or bb:get("player.is_channeling", false) == true then
                return Status.RUNNING
            end
            return profile_result
        end),

        -- Set resting flag so other phases know we're resting
        BT.action("set_resting_flag", function(bb)
            bb:set("module.grind.is_resting", true)
            if core and core.log then
                pcall(core.log, string.format("[Rest] STARTED: hp=%.2f mana=%.2f",
                    bb:get("player.health_pct", 1), bb:get("player.mana_pct", 1)))
            end
            return Status.SUCCESS
        end),

        -- Eat food / drink water and wait for recovery
        BT.action("sit_and_consume", function(bb)
            -- Re-check engagement (Sequence _running_index skips the gate condition).
            -- If the combat module engaged an attacker, abort rest so we fight back.
            if bb:get("combat.source") ~= nil then
                bb:set("module.grind.is_resting", false)
                _eat_active = false
                _eat_reuse_count = 0
                _drink_active = false
                _drink_reuse_count = 0
                return Status.FAILURE
            end

            -- Stop movement so eating/drinking buffs aren't cancelled
            if nav_adapter and nav_adapter:is_active() then
                nav_adapter:stop("rest")
            end

            local hp = bb:get("player.health_pct", 1)
            local mana = bb:get("player.mana_pct", 1)

            -- Scan bags once for food and water IDs (avoids 4 scans per tick)
            local food_id = find_consumable_in_bags(FOOD_ITEMS)
            local water_id = find_consumable_in_bags(WATER_ITEMS)

            -- With consumables: wait for 95% recovery.
            -- Without consumables: wait for threshold + 15% hysteresis so we
            -- don't busy-loop (rest triggers at threshold, needs to regen past
            -- it before re-triggering).
            local eat_threshold = bb:get("module.grind.health_eat_pct", 0.50)
            local drink_threshold = bb:get("module.grind.mana_drink_pct", 0.40)
            local no_food_target = math.min(eat_threshold + 0.15, 0.95)
            local no_water_target = math.min(drink_threshold + 0.15, 0.95)
            local hp_ok = hp >= 0.95 or (not food_id and hp >= no_food_target)
            local mana_ok = mana >= 0.95 or (not water_id and mana >= no_water_target)

            if hp_ok and mana_ok then
                _eat_active = false
                _eat_reuse_count = 0
                _drink_active = false
                _drink_reuse_count = 0
                return Status.SUCCESS
            end

            -- Don't try to eat/drink while casting (maintenance buff, etc.)
            if bb:get("player.is_casting", false) == true
            or bb:get("player.is_channeling", false) == true then
                return Status.RUNNING
            end

            local now = bb:get("system.now_ms", 0)

            -- Food: use_item, then verify real eating started (not just passive regen).
            -- After CONSUME_VERIFY_MS, check if gain exceeds CONSUME_MIN_GAIN.
            -- Passive spirit regen gives ~2-3% per 5s; eating gives ~15%+ per 5s.
            if not hp_ok and food_id then
                if _eat_reuse_count >= MAX_REUSE_ATTEMPTS then
                    _eat_active = false
                    _eat_reuse_count = 0
                elseif not _eat_active then
                    if core and core.input and core.input.use_item then
                        local ok_use, err = pcall(core.input.use_item, food_id)
                        if core and core.log then
                            pcall(core.log, string.format("[Rest] EAT use_item(%d) ok=%s err=%s hp=%.2f",
                                food_id, tostring(ok_use), tostring(err), hp))
                        end
                    end
                    _eat_active = true
                    _eat_started_ms = now
                    _eat_initial_hp = hp
                elseif now - _eat_started_ms > CONSUME_VERIFY_MS then
                    local gain = hp - _eat_initial_hp
                    if gain < CONSUME_MIN_GAIN then
                        -- Passive regen only — eating didn't start. Retry.
                        if core and core.log then
                            pcall(core.log, string.format("[Rest] EAT stall: gain=%.3f < %.3f, retry #%d",
                                gain, CONSUME_MIN_GAIN, _eat_reuse_count + 1))
                        end
                        _eat_active = false
                        _eat_reuse_count = _eat_reuse_count + 1
                    else
                        -- Real eating confirmed — reset timer for next verification window
                        _eat_started_ms = now
                        _eat_initial_hp = hp
                    end
                end
            elseif hp_ok then
                _eat_active = false
                _eat_reuse_count = 0
            end

            -- Water: same pattern as food.
            if not mana_ok and water_id then
                if _drink_reuse_count >= MAX_REUSE_ATTEMPTS then
                    _drink_active = false
                    _drink_reuse_count = 0
                elseif not _drink_active then
                    if core and core.input and core.input.use_item then
                        local ok_use, err = pcall(core.input.use_item, water_id)
                        if core and core.log then
                            pcall(core.log, string.format("[Rest] DRINK use_item(%d) ok=%s err=%s mana=%.2f",
                                water_id, tostring(ok_use), tostring(err), mana))
                        end
                    end
                    _drink_active = true
                    _drink_started_ms = now
                    _drink_initial_mana = mana
                elseif now - _drink_started_ms > CONSUME_VERIFY_MS then
                    local gain = mana - _drink_initial_mana
                    if gain < CONSUME_MIN_GAIN then
                        if core and core.log then
                            pcall(core.log, string.format("[Rest] DRINK stall: gain=%.3f < %.3f, retry #%d",
                                gain, CONSUME_MIN_GAIN, _drink_reuse_count + 1))
                        end
                        _drink_active = false
                        _drink_reuse_count = _drink_reuse_count + 1
                    else
                        _drink_started_ms = now
                        _drink_initial_mana = mana
                    end
                end
            elseif mana_ok then
                _drink_active = false
                _drink_reuse_count = 0
            end

            return Status.RUNNING
        end),

        -- Cancel sitting state from eating/drinking so the next phase
        -- (loot, pull) doesn't fail while the character is still seated.
        BT.action("stand_up", function(_bb)
            if core and core.input then
                if type(core.input.move_forward_start) == "function" then
                    pcall(core.input.move_forward_start)
                end
                if type(core.input.move_forward_stop) == "function" then
                    pcall(core.input.move_forward_stop)
                end
            end
            return Status.SUCCESS
        end),

        -- Clear resting flag and publish rest complete event
        BT.action("publish_rest_complete", function(bb)
            bb:set("module.grind.is_resting", false)
            _eat_active = false
            _eat_reuse_count = 0
            _drink_active = false
            _drink_reuse_count = 0
            if core and core.log then
                pcall(core.log, string.format("[Rest] DONE: hp=%.2f mana=%.2f",
                    bb:get("player.health_pct", 1), bb:get("player.mana_pct", 1)))
            end
            event_bus:publish("grind:rest_complete", {})
            return Status.SUCCESS
        end),
    })
end

return Rest
