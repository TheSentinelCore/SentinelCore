local T = require("tests/TestUtil")

local function run()
    local learned = {
        [27137] = true,
        [19750] = true,
    }

    T.install_core_stub({
        spell_book = {
            is_usable_spell = function() return true end,
            is_spell_learned = function(id)
                return learned[tonumber(id) or -1] == true
            end,
            has_spell = function(id)
                return learned[tonumber(id) or -1] == true
            end,
        },
    })

    local RankPolicy = require("rotations/framework/RankPolicy")

    local fallback = { 27137, 19943, 19942, 19941, 19940, 19939, 19750 }

    local high_mana_ctx = {
        player_mana_pct = 0.55,
        resolve_spell_id = function(name, fallback_ids)
            return 27137
        end,
    }

    local low_mana_ctx = {
        player_mana_pct = 0.15,
        resolve_spell_id = function(name, fallback_ids)
            return 27137
        end,
    }

    local high = RankPolicy.select_by_mana_policy(high_mana_ctx, {
        spell_name = "flash of light",
        fallback_ids = fallback,
        low_mana_rank_ids = { 19750 },
        low_mana_threshold = 0.22,
        critical_mana_threshold = 0.08,
    })
    T.assert_eq(high, 27137, "high mana should use max flash rank")

    local low = RankPolicy.select_by_mana_policy(low_mana_ctx, {
        spell_name = "flash of light",
        fallback_ids = fallback,
        low_mana_rank_ids = { 19750 },
        low_mana_threshold = 0.22,
        critical_mana_threshold = 0.08,
    })
    T.assert_eq(low, 19750, "low mana should use configured downrank")

    learned[19750] = false
    local low_no_downrank = RankPolicy.select_by_mana_policy(low_mana_ctx, {
        spell_name = "flash of light",
        fallback_ids = fallback,
        low_mana_rank_ids = { 19750 },
        low_mana_threshold = 0.22,
        critical_mana_threshold = 0.08,
    })
    T.assert_eq(low_no_downrank, 27137, "if downrank not learned, policy must fallback to highest learned rank")

    return {
        rotation_rank_policy = true,
    }
end

return { run = run }
