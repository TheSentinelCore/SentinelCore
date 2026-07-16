--- Unit tests for RuleEngine
--- Run with: _G.SentinelCore.run_tests()

local RuleEngine = require("modules/quest/rule_engine")

local tests = {}

local function make_quest_node(opts)
    opts = opts or {}
    return {
        id = opts.id or 100,
        title = opts.title or "Test Quest",
        level = opts.level or 10,
        is_elite = opts.is_elite or false,
        is_dungeon = opts.is_dungeon or false,
        objectives = opts.objectives or {},
        zone_pvp = opts.zone_pvp or false,
        start_npc = opts.start_npc,
    }
end

local function make_profile(opts)
    opts = opts or {}
    return {
        zone = opts.zone or "TestZone",
        rules = {
            skip_elites = opts.skip_elites,
            skip_escort = opts.skip_escort,
            skip_dungeon_chains = opts.skip_dungeon_chains,
            skip_pvp = opts.skip_pvp,
            max_travel_yards = opts.max_travel_yards,
            min_xp_per_minute = opts.min_xp_per_minute,
            vendor_threshold_pct = opts.vendor_threshold_pct,
            repair_threshold_pct = opts.repair_threshold_pct,
            min_bag_slots = opts.min_bag_slots,
        },
        scoring = opts.scoring,
    }
end

local function make_context(opts)
    opts = opts or {}
    return {
        player_pos = opts.player_pos or {x = 0, y = 0, z = 0},
        nav_adapter = opts.nav_adapter,
        zone_pvp = opts.zone_pvp or false,
    }
end

local function make_blackboard(opts)
    opts = opts or {}
    return {
        get = function(self, key, default)
            if key == "module.grind.bag_free_slots" then return opts.free_slots or 10 end
            if key == "module.grind.bag_total_slots" then return opts.total_slots or 16 end
            if key == "module.grind.avg_durability_pct" then return opts.durability or 100 end
            return default
        end
    }
end

function tests.test_skip_elites()
    local profile = make_profile({skip_elites = true})
    local node = make_quest_node({is_elite = true})
    local context = make_context({})
    
    local pass, reason = RuleEngine.evaluate(profile, node, context)
    
    assert(pass == false, "Should fail for elite quest")
    assert(reason == "elite", "Reason should be 'elite'")
    
    print("✓ test_skip_elites passed")
end

function tests.test_skip_escort()
    local profile = make_profile({skip_escort = true})
    local node = make_quest_node({
        objectives = {{type = "ESCORT", npc_id = 100, waypoints = {}}}
    })
    local context = make_context({})
    
    local pass, reason = RuleEngine.evaluate(profile, node, context)
    
    assert(pass == false, "Should fail for escort quest")
    assert(reason == "escort", "Reason should be 'escort'")
    
    print("✓ test_skip_escort passed")
end

function tests.test_skip_dungeon_chains()
    local profile = make_profile({skip_dungeon_chains = true})
    local node = make_quest_node({is_dungeon = true})
    local context = make_context({})
    
    local pass, reason = RuleEngine.evaluate(profile, node, context)
    
    assert(pass == false, "Should fail for dungeon quest")
    assert(reason == "dungeon", "Reason should be 'dungeon'")
    
    print("✓ test_skip_dungeon_chains passed")
end

function tests.test_max_travel()
    local profile = make_profile({max_travel_yards = 500})
    local node = make_quest_node({start_npc = {x = 1000, y = 1000, z = 0}})
    local mock_nav = {
        estimate_distance = function(self, from, to)
            return 1414 -- sqrt(1000^2 + 1000^2) ≈ 1414
        end
    }
    local context = make_context({nav_adapter = mock_nav})
    
    local pass, reason = RuleEngine.evaluate(profile, node, context)
    
    assert(pass == false, "Should fail for distant quest")
    assert(reason == "travel", "Reason should be 'travel'")
    
    print("✓ test_max_travel passed")
end

function tests.test_filter_quests()
    local profile = make_profile({skip_elites = true})
    local nodes = {
        make_quest_node({id = 1, is_elite = false}),
        make_quest_node({id = 2, is_elite = true}),
        make_quest_node({id = 3, is_elite = false}),
    }
    local context = make_context({})
    
    local filtered = RuleEngine.filter_quests(nodes, profile, context)
    
    assert(#filtered == 2, "Should filter out 1 elite quest")
    assert(filtered[1].id == 1, "First quest should be non-elite")
    assert(filtered[2].id == 3, "Second quest should be non-elite")
    
    print("✓ test_filter_quests passed")
end

function tests.test_should_town_bags()
    local profile = make_profile({vendor_threshold_pct = 80})
    local bb = make_blackboard({free_slots = 2, total_slots = 16}) -- 87.5% full
    
    local should, reason = RuleEngine.should_return_to_town(profile, bb)
    
    assert(should == true, "Should return to town")
    assert(reason == "vendor", "Reason should be 'vendor'")
    
    print("✓ test_should_town_bags passed")
end

function tests.test_should_town_repair()
    local profile = make_profile({repair_threshold_pct = 40})
    local bb = make_blackboard({durability = 35})
    
    local should, reason = RuleEngine.should_return_to_town(profile, bb)
    
    assert(should == true, "Should return to town")
    assert(reason == "repair", "Reason should be 'repair'")
    
    print("✓ test_should_town_repair passed")
end

function tests.test_scoring_weights()
    local profile = make_profile({
        scoring = {xp_per_minute = 1.0, travel_efficiency = 0.0}
    })
    local weights = RuleEngine.get_scoring_weights(profile)
    
    assert(weights.xp_per_minute == 1.0, "Custom weight should override")
    assert(weights.travel_efficiency == 0.0, "Custom zero weight should apply")
    
    -- Test defaults
    local default_weights = RuleEngine.get_scoring_weights(nil)
    assert(default_weights.xp_per_minute == 0.35, "Default XP weight")
    assert(default_weights.travel_efficiency == 0.25, "Default travel weight")
    
    print("✓ test_scoring_weights passed")
end

function tests.run_all()
    print("Running RuleEngine tests...")
    tests.test_skip_elites()
    tests.test_skip_escort()
    tests.test_skip_dungeon_chains()
    tests.test_max_travel()
    tests.test_filter_quests()
    tests.test_should_town_bags()
    tests.test_should_town_repair()
    tests.test_scoring_weights()
    print("All RuleEngine tests passed!")
end

return tests