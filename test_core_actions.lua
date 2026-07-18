package.path = './sentinel/?.lua;' .. package.path

local CoreActions = require('modules/quest/profile_actions')

-- Mock engine subsystems
local mockEngine = {
    nav = {
        followPolicy = function(self, name) print("  [nav] followPolicy:", name); return true end,
        cancel = function(self) print("  [nav] cancel"); return true end,
    },
    combat = {
        setTargetFilter = function(self, npcs) print("  [combat] setTargetFilter:", table.concat(npcs, ", ")); return true end,
        clearTargetFilter = function(self) print("  [combat] clearTargetFilter"); return true end,
        engage = function(self, targetGUID) print("  [combat] engage:", targetGUID or "auto"); return true end,
    },
    consume = {
        useFood = function(self) print("  [consume] useFood"); return true end,
        useWater = function(self) print("  [consume] useWater"); return true end,
        useBandage = function(self) print("  [consume] useBandage"); return true end,
        stop = function(self) print("  [consume] stop"); return true end,
    },
    vendor = {
        sellJunk = function(self) print("  [vendor] sellJunk"); return true end,
        repair = function(self) print("  [vendor] repair"); return true end,
        buyConsumables = function(self, list) print("  [vendor] buyConsumables:", table.concat(list or {}, ", ")); return true end,
    },
    trainer = {
        trainAvailable = function(self) print("  [trainer] trainAvailable"); return true end,
    },
    loot = {
        lootAll = function(self) print("  [loot] lootAll"); return true end,
    },
    acceptQuest = function(self, questId, npcId) print("  [engine] acceptQuest:", questId, "from NPC", npcId); return true end,
    turnInQuest = function(self, questId, rewardIndex) print("  [engine] turnInQuest:", questId, "reward:", rewardIndex or 0); return true end,
    bindHearthstone = function(self, npcId) print("  [engine] bindHearthstone:", npcId); return true end,
    movement = {
        mount = function(self) print("  [movement] mount"); return true end,
        dismount = function(self) print("  [movement] dismount"); return true end,
    },
}

local actions = CoreActions.new(
    mockEngine,
    mockEngine.nav,
    mockEngine.combat,
    mockEngine.consume,
    mockEngine.vendor,
    mockEngine.loot,
    mockEngine,
    mockEngine.trainer,
    mockEngine.movement
)

print("=== Testing CoreActions ===")

-- Test validation
assert(actions:validate("nav.followPolicy"), "nav.followPolicy should be valid")
assert(not actions:validate("invalid.action"), "invalid.action should not be valid")
print("✓ Validation works")

-- Test get
local action = actions:get("nav.followPolicy")
assert(type(action) == "function", "Action should be a function")
print("✓ Get action works")

-- Test call
local ctx = {engine = mockEngine}
local ok, err = actions:call("nav.followPolicy", ctx, "test_policy")
assert(ok, "Action call failed: " .. tostring(err))
print("✓ Action call works")

-- Test invalid action
local ok2, err2 = actions:call("invalid.action", ctx)
assert(not ok2, "Invalid action should fail")
print("✓ Invalid action rejected")

-- Test all_names
local names = actions:all_names()
print("Registered actions:", table.concat(names, ", "))
assert(#names >= 17, "Should have 17+ actions")

-- Test signatures
local sigs = actions._signatures
assert(sigs["nav.followPolicy"], "nav.followPolicy should have signature")
assert(sigs["nav.followPolicy"].params[1] == "policyName", "nav.followPolicy should have policyName param")

print("\n=== All CoreActions tests passed ===")