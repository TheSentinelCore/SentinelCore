local T = require("tests/TestUtil")

local function run()
    local learned = {
        [686] = true,   -- Shadow Bolt rank 1
        [172] = true,   -- Corruption
        [980] = true,   -- Curse of Agony
        [348] = true,   -- Immolate
        [689] = true,   -- Drain Life
        [1120] = true,  -- Drain Soul
        [1454] = true,  -- Life Tap
        [687] = true,   -- Demon Skin
        [688] = true,   -- Summon Imp
        [697] = true,   -- Summon Voidwalker
        [5019] = true,  -- Shoot
    }

    local shard_item = T.mock_object({ item_id = 6265, stack_count = 3 })

    local include_shards = false
    T.install_core_stub({
        spell_book = {
            is_spell_learned = function(id)
                return learned[tonumber(id) or -1] == true
            end,
            has_spell = function(id)
                return learned[tonumber(id) or -1] == true
            end,
            is_usable_spell = function()
                return true
            end,
        },
        inventory = {
            get_items_in_bag = function(bag_id)
                if include_shards and bag_id == 0 then
                    return {
                        { item = shard_item, slot_id = 1 },
                    }
                end
                return {}
            end,
        },
    })

    local provider = require("rotations/warlock/Affliction")

    local function resolve_from_fallback(_, fallback_ids)
        if type(fallback_ids) == "table" and #fallback_ids > 0 then
            return fallback_ids[1]
        end
        return nil
    end

    local base_ctx = {
        class_id = 9,
        in_combat = true,
        enemy_count = 1,
        player_mana_pct = 0.50,
        player_health_pct = 0.80,
        pet_health_pct = nil,
        pet = nil,
        player_has_aura = function()
            return false
        end,
        target_has_aura = function()
            return false
        end,
        resolve_spell_id = resolve_from_fallback,
    }

    T.assert_true(provider:can_run(base_ctx) == true, "affliction provider should run for class 9")
    T.assert_true(provider:can_run({ class_id = 2 }) == false, "affliction provider must not run for non-warlock")

    local combat = provider:combat(base_ctx)
    local has_corruption = false
    local has_curse = false
    local has_filler = false
    local has_wand = false
    local proc_action = nil
    local drain_soul_action = nil
    for i = 1, #combat do
        local action = combat[i]
        if action.action_type == "cast_spell_target" and tonumber(action.priority) == 555 then
            has_corruption = true
        elseif action.action_type == "cast_spell_target" and tonumber(action.priority) == 550 then
            has_curse = true
        elseif action.action_type == "cast_spell_target" and tonumber(action.priority) == 520 then
            has_filler = true
        elseif action.action_type == "cast_spell_target" and tonumber(action.priority) == 510 then
            has_wand = true
        elseif action.action_type == "cast_spell_target" and tonumber(action.priority) == 570 then
            proc_action = action
        elseif action.action_type == "cast_spell_target" and tonumber(action.priority) == 530 then
            drain_soul_action = action
        end
    end

    T.assert_true(has_corruption, "combat plan should include Corruption upkeep")
    T.assert_true(has_curse, "combat plan should include Curse of Agony upkeep")
    T.assert_true(has_filler, "combat plan should include Shadow Bolt filler")
    T.assert_true(has_wand, "combat plan should include wand fallback")
    T.assert_true(type(proc_action) == "table", "combat plan should include Nightfall proc action")
    T.assert_true(type(drain_soul_action) == "table", "combat plan should include Drain Soul replenish action")

    local proc_ctx = {
        class_id = 9,
        in_combat = true,
        player = T.mock_object({ casting = false }),
        player_has_aura = function(spec)
            return tonumber(spec) == 17941
        end,
        target_has_aura = function()
            return false
        end,
        resolve_spell_id = resolve_from_fallback,
    }
    T.assert_true(proc_action.condition(proc_ctx, proc_action) == true, "nightfall proc action should pass when aura is up")

    local low_mana_ctx = {
        class_id = 9,
        in_combat = true,
        player = T.mock_object({ casting = false, mana = 5, max_mana = 100 }),
        player_mana_pct = 0.05,
        player_has_aura = function()
            return false
        end,
        target_has_aura = function()
            return false
        end,
        resolve_spell_id = resolve_from_fallback,
    }
    T.assert_true(drain_soul_action.condition(low_mana_ctx, drain_soul_action) == true,
        "drain soul action should pass at low mana with no shards")

    local maintenance = provider:maintenance({
        class_id = 9,
        in_combat = false,
        player_mana_pct = 0.90,
        player_health_pct = 0.90,
        player_is_moving = false,
        eating_or_drinking = false,
        pet = nil,
        player_has_aura = function()
            return false
        end,
        resolve_spell_id = resolve_from_fallback,
    })

    local summon_action = nil
    for i = 1, #maintenance do
        local action = maintenance[i]
        if action.action_type == "cast_spell_self" and tonumber(action.priority) == 255 then
            summon_action = action
            break
        end
    end
    T.assert_true(type(summon_action) == "table", "maintenance plan should include summon action")

    include_shards = false
    local no_shard_spell = summon_action.spell_id(base_ctx, summon_action)
    T.assert_eq(no_shard_spell, 688, "summon selection should fallback to imp when no shards are available")

    include_shards = true
    local with_shard_spell = summon_action.spell_id(base_ctx, summon_action)
    T.assert_eq(with_shard_spell, 697, "summon selection should prefer voidwalker when shards are available")

    return {
        warlock_affliction_regressions = true,
    }
end

return { run = run }
