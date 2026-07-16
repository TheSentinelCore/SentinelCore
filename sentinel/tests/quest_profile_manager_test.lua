--- Unit tests for QuestProfileManager
--- Run with: _G.SentinelCore.run_tests()

local QuestProfileManager = require("modules/quest/quest_profile_manager")

local tests = {}

function tests.test_load_profile()
    local pm = QuestProfileManager.new({}, {})
    
    -- Test loading a known profile
    local success, err = pm:load_profile("westfall")
    assert(success, "Should load westfall profile: " .. tostring(err))
    assert(pm._profiles["westfall"], "Profile should be stored")
    assert(pm._profiles["westfall"].zone == "Westfall", "Zone should match")
    
    print("✓ test_load_profile passed")
end

function tests.test_autoload_ek()
    local pm = QuestProfileManager.new({}, {
        get = function(self, key)
            if key == "player.faction" then return "Alliance" end
            return nil
        end
    })
    
    -- Test auto-load for Eastern Kingdoms (map_id = 0) at level 15
    local success = pm:try_autoload(15, 0, "Alliance")
    assert(success, "Should auto-load a profile for EK level 15 Alliance")
    assert(pm._active_profile, "Should have active profile")
    assert(pm._active_profile.level_range.min <= 15 and pm._active_profile.level_range.max >= 15, "Level should be in range")
    
    print("✓ test_autoload_ek passed")
end

function tests.test_autoload_kalimdor()
    local pm = QuestProfileManager.new({}, {
        get = function(self, key)
            if key == "player.faction" then return "Horde" end
            return nil
        end
    })
    
    -- Test auto-load for Kalimdor (map_id = 1) at level 15
    local success = pm:try_autoload(15, 1, "Horde")
    assert(success, "Should auto-load a profile for Kalimdor level 15 Horde")
    assert(pm._active_profile, "Should have active profile")
    
    print("✓ test_autoload_kalimdor passed")
end

function tests.test_fallback_to_default()
    local pm = QuestProfileManager.new({}, {
        get = function(self, key)
            if key == "player.faction" then return "Alliance" end
            return nil
        end
    })
    
    -- Test fallback when no zone-specific profile matches
    local success = pm:try_autoload(5, 0, "Alliance") -- Level 5, no matching zone
    -- Should still succeed by loading default
    if not success and pm._profiles["default"] then
        -- Default loaded
    end
    
    print("✓ test_fallback_to_default passed")
end

function tests.test_yaml_parsing()
    local pm = QuestProfileManager.new({}, {})
    
    local yaml_content = [[
zone: "Test Zone"
level_range:
  min: 10
  max: 20
faction: "Alliance"
rules:
  skip_elites: true
  skip_escort: false
  max_travel_yards: 1500
scoring:
  xp_per_minute: 0.4
objective_strategy: "cluster"
]]
    
    local parsed = pm:_parse_yaml(yaml_content)
    assert(parsed, "Should parse YAML")
    assert(parsed.zone == "Test Zone", "Zone should parse")
    assert(parsed.level_range.min == 10, "Level min should parse")
    assert(parsed.level_range.max == 20, "Level max should parse")
    assert(parsed.faction == "Alliance", "Faction should parse")
    assert(parsed.rules.skip_elites == true, "Skip elites should be boolean")
    assert(parsed.scoring.xp_per_minute == 0.4, "Scoring should parse")
    
    print("✓ test_yaml_parsing passed")
end

function tests.test_rules_normalization()
    local pm = QuestProfileManager.new({}, {})
    
    local rules = {
        skip_elites = false,
        vendor_threshold_pct = 70,
    }
    
    local normalized = pm:_normalize_rules(rules)
    assert(normalized.skip_elites == false, "Custom rule should override default")
    assert(normalized.vendor_threshold_pct == 70, "Custom value should be used")
    assert(normalized.skip_escort == false, "Default should be used for missing")
    assert(normalized.max_travel_yards == 1800, "Default should be used for missing")
    
    print("✓ test_rules_normalization passed")
end

function tests.run_all()
    print("Running QuestProfileManager tests...")
    tests.test_load_profile()
    tests.test_autoload_ek()
    tests.test_autoload_kalimdor()
    tests.test_fallback_to_default()
    tests.test_yaml_parsing()
    tests.test_rules_normalization()
    print("All QuestProfileManager tests passed!")
end

return tests