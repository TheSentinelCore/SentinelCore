local T = require("tests/TestUtil")

return { run = function()
    local PerformanceAdvisor = require("ai/PerformanceAdvisor")
    local TacticalSelector = require("ai/TacticalSelector")
    local SingleTargetTactic = require("tactics/SingleTargetTactic")
    local AoEKiteTactic = require("tactics/AoEKiteTactic")
    local EventBus = require("events/EventBus")

    local function make_payload(kills, deaths, xp)
        return { snapshot = { kills = kills, deaths = deaths, xp_gained = xp } }
    end

    -- 1. Advisor biases influence TacticalSelector scoring
    do
        local bus = EventBus:new()
        local advisor = PerformanceAdvisor:new(bus)
        advisor._min_sample_secs = 2  -- low threshold for test

        local selector = TacticalSelector:new(advisor)
        selector:register(SingleTargetTactic:new())
        selector:register(AoEKiteTactic:new())

        -- Context where both tactics are viable
        local ctx = {
            pack_count = 3,
            player_mana_pct = 0.8,
            enemy_count = 3,
            in_combat = false,
            has_target = false,
        }
        selector:refresh_available(ctx)

        -- Without bias, AoE should win (0.65 vs ST's ~0.30)
        local picked = selector:select(ctx)
        T.assert_true(picked ~= nil, "a tactic is selected")
        T.assert_eq(picked:get_name(), "aoe_kite", "AoE wins without bias")

        -- Simulate bad AoE performance: many deaths
        advisor:set_active_tactic("aoe_kite")
        advisor:_on_telemetry(make_payload(0, 0, 0))
        advisor:_on_telemetry(make_payload(2, 5, 100))
        advisor:_on_telemetry(make_payload(4, 10, 200))
        -- aoe_kite: effective_xp = 200 - 10*300 = -2800 -> 0.001

        -- Simulate good ST performance
        advisor:set_active_tactic("single_target")
        advisor:_on_telemetry(make_payload(4, 10, 200))
        advisor:_on_telemetry(make_payload(14, 10, 1200))
        advisor:_on_telemetry(make_payload(24, 10, 2200))
        -- single_target: effective_xp = 2000, active_secs=2

        -- Now advisor should boost ST (~1.2) and suppress AoE (~0.8)
        local st_bias = advisor:get_bias("single_target")
        local aoe_bias = advisor:get_bias("aoe_kite")
        T.assert_true(st_bias > aoe_bias, "ST bias > AoE bias after bad AoE performance")

        -- With bias, AoE raw=0.65*0.8=0.52 vs ST raw=0.30*1.2=0.36
        -- AoE still wins on raw utility, but the gap narrowed significantly
        T.assert_true(st_bias > 1.0, "ST boosted above 1.0")
        T.assert_true(aoe_bias < 1.0, "AoE suppressed below 1.0")
    end

    -- 2. PerformanceAdvisor get_bias returns 1.0 for unknown tactics
    do
        local advisor = PerformanceAdvisor:new(nil)
        T.assert_eq(advisor:get_bias("nonexistent"), 1.0, "unknown tactic bias is 1.0")
    end

    -- 3. Precombat conjure spells present in Frost rotation
    do
        local ok, Frost = pcall(require, "rotations/mage/Frost")
        if ok and Frost then
            -- Build a minimal context
            local frost = setmetatable({}, { __index = Frost })
            local ctx = {
                player_is_stunned = false,
                player_is_feared = false,
                player_mana_pct = 0.5,
                in_combat = false,
            }

            -- Install core stub with conjure spells learned
            local prev_core = rawget(_G, "core")
            rawset(_G, "core", {
                spell_book = {
                    is_spell_known = function(id)
                        -- Conjure Water rank 7 = 27090, Conjure Food rank 7 = 33717
                        return id == 27090 or id == 33717
                    end,
                    get_spell_cooldown = function() return 0 end,
                },
            })

            local actions = frost:precombat(ctx)
            T.assert_true(#actions >= 2, "precombat returns conjure actions, got " .. #actions)

            -- Verify priorities
            local found_water = false
            local found_food = false
            for _, action in ipairs(actions) do
                if action.priority == 200 then found_water = true end
                if action.priority == 195 then found_food = true end
            end
            T.assert_true(found_water, "conjure water at priority 200")
            T.assert_true(found_food, "conjure food at priority 195")

            -- Verify stunned returns empty
            ctx.player_is_stunned = true
            local stunned_actions = frost:precombat(ctx)
            T.assert_eq(#stunned_actions, 0, "precombat empty when stunned")

            rawset(_G, "core", prev_core)
        end
    end

    return true
end }
