--- Unit tests for QuestScorer
--- Run with: _G.SentinelCore.run_tests()

local QuestScorer = require("modules/quest/quest_scorer")

local tests = {}

--- Create mock quest node
local function make_quest_node(opts)
    opts = opts or {}
    return {
        id = opts.id or 100,
        title = opts.title or "Test Quest",
        level = opts.level or 10,
        zone = opts.zone or "TestZone",
        objectives = opts.objectives or {},
        rewards = opts.rewards or {xp = 1000, money = 1000, choices = {}, fixed = {}},
        suggested_players = opts.suggested_players or 1,
        is_elite = opts.is_elite or false,
        is_dungeon = opts.is_dungeon or false,
        start_npc = opts.start_npc,
        end_npc = opts.end_npc,
        prev_quest_id = opts.prev_quest or 0,
        next_in_chain = opts.next_in_chain or 0,
        zone_or_sort = opts.zone_or_sort or 0,
    }
end

--- Create mock context
local function make_context(opts)
    opts = opts or {}
    return {
        player_pos = opts.player_pos or {x = 0, y = 0, z = 0},
        player_level = opts.player_level or 10,
        active_quests = opts.active_quests or {},
        profile = opts.profile,
        quest_graph = opts.quest_graph,
        nav_adapter = opts.nav_adapter,
    }
end

function tests.test_basic_scoring()
    local scorer = QuestScorer.new()
    local node = make_quest_node({
        id = 100,
        rewards = {xp = 2000, money = 5000, choices = {}, fixed = {}},
        objectives = {{type = "KILL", target_id = 100, count = 10}},
        start_npc = {x = 100, y = 100, z = 0},
        end_npc = {x = 200, y = 200, z = 0},
    })
    local context = make_context({
        player_pos = {x = 0, y = 0, z = 0},
        player_level = 10,
    })
    
    local score = scorer:score(node, context)
    assert(score > 0, "Score should be positive")
    
    print("✓ test_basic_scoring passed (score: " .. string.format("%.2f", score) .. ")")
end

function tests.test_elite_penalty()
    local scorer = QuestScorer.new()
    local node = make_quest_node({
        id = 100,
        is_elite = true,
        rewards = {xp = 2000},
        objectives = {{type = "KILL", target_id = 100, count = 10}},
    })
    local context = make_context({player_level = 10})
    
    local normal_node = make_quest_node({
        id = 101,
        is_elite = false,
        rewards = {xp = 2000},
        objectives = {{type = "KILL", target_id = 100, count = 10}},
    })
    
    local normal_score = scorer:score(normal_node, context)
    local elite_score = scorer:score(node, context)
    
    assert(elite_score < normal_score, "Elite quest should score lower")
    
    print("✓ test_elite_penalty passed (normal: " .. string.format("%.2f", normal_score) .. ", elite: " .. string.format("%.2f", elite_score) .. ")")
end

function tests.test_dungeon_penalty()
    local scorer = QuestScorer.new()
    local node = make_quest_node({
        id = 100,
        is_dungeon = true,
        rewards = {xp = 5000},
        objectives = {{type = "KILL", target_id = 100, count = 5}},
    })
    local context = make_context({player_level = 10})
    
    local score = scorer:score(node, context)
    assert(score < 100, "Dungeon quest should have heavy penalty")
    
    print("✓ test_dungeon_penalty passed (score: " .. string.format("%.2f", score) .. ")")
end

function tests.test_travel_penalty()
    local scorer = QuestScorer.new()
    
    local nearby = make_quest_node({
        id = 100,
        rewards = {xp = 1000},
        objectives = {{type = "KILL", count = 5}},
        start_npc = {x = 50, y = 50, z = 0},
    })
    
    local far = make_quest_node({
        id = 101,
        rewards = {xp = 1000},
        objectives = {{type = "KILL", count = 5}},
        start_npc = {x = 2000, y = 2000, z = 0},
    })
    
    local context = make_context({player_pos = {x = 0, y = 0, z = 0}})
    
    local nearby_score = scorer:score(nearby, context)
    local far_score = scorer:score(far, context)
    
    assert(nearby_score > far_score, "Nearby quest should score higher")
    
    print("✓ test_travel_penalty passed (nearby: " .. string.format("%.2f", nearby_score) .. ", far: " .. string.format("%.2f", far_score) .. ")")
end

function tests.test_overlap_bonus()
    local scorer = QuestScorer.new()
    local node = make_quest_node({
        id = 100,
        rewards = {xp = 1000},
        objectives = {{type = "KILL", target_id = 100, count = 10}},
    })
    
    local context1 = make_context({
        player_pos = {x = 0, y = 0, z = 0},
        active_quests = {},
    })
    
    local other_quest = make_quest_node({
        id = 101,
        objectives = {{type = "KILL", target_id = 100, count = 5}}, -- Same mob!
    })
    
    local context2 = make_context({
        player_pos = {x = 0, y = 0, z = 0},
        active_quests = {other_quest},
    })
    
    local score1 = scorer:score(node, context1)
    local score2 = scorer:score(node, context2)
    
    assert(score2 > score1, "Overlap should increase score")
    
    print("✓ test_overlap_bonus passed (alone: " .. string.format("%.2f", score1) .. ", overlap: " .. string.format("%.2f", score2) .. ")")
end

function tests.test_score_all_sorts()
    local scorer = QuestScorer.new()
    local nodes = {
        make_quest_node({id = 1, rewards = {xp = 500}, objectives = {{type = "KILL", count = 10}}}),
        make_quest_node({id = 2, rewards = {xp = 2000}, objectives = {{type = "KILL", count = 5}}}),
        make_quest_node({id = 3, rewards = {xp = 1000}, objectives = {{type = "KILL", count = 8}}}),
    }
    local context = make_context({player_pos = {x = 0, y = 0, z = 0}})
    
    local scored = scorer:score_all(nodes, context)
    
    assert(#scored == 3, "Should score all 3")
    assert(scored[1].node.id == 2, "Highest XP quest should be first")
    assert(scored[1].score >= scored[2].score, "Should be sorted descending")
    assert(scored[2].score >= scored[3].score, "Should be sorted descending")
    
    print("✓ test_score_all_sorts passed (order: " .. scored[1].node.id .. ", " .. scored[2].node.id .. ", " .. scored[3].node.id .. ")")
end

function tests.test_profile_weights()
    local scorer = QuestScorer.new()
    local node = make_quest_node({
        id = 100,
        rewards = {xp = 1000},
        objectives = {{type = "KILL", count = 5}},
    })
    
    local context = make_context({
        player_pos = {x = 0, y = 0, z = 0},
        profile = {
            scoring = {
                xp_per_minute = 1.0, -- Double weight
                travel_efficiency = 0.0,
                objective_overlap = 0.0,
                reward_value = 0.0,
                chain_priority = 0.0,
            }
        }
    })
    
    local score = scorer:score(node, context)
    
    -- Should be higher with doubled XP weight
    local normal_context = make_context({player_pos = {x = 0, y = 0, z = 0}})
    local normal_score = scorer:score(node, normal_context)
    
    assert(score > normal_score, "Custom weights should affect score")
    
    print("✓ test_profile_weights passed (custom: " .. string.format("%.2f", score) .. ", normal: " .. string.format("%.2f", normal_score) .. ")")
end

function tests.run_all()
    print("Running QuestScorer tests...")
    tests.test_basic_scoring()
    tests.test_elite_penalty()
    tests.test_dungeon_penalty()
    tests.test_travel_penalty()
    tests.test_overlap_bonus()
    tests.test_score_all_sorts()
    tests.test_profile_weights()
    print("All QuestScorer tests passed!")
end

return tests