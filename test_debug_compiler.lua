-- test_debug_compiler.lua - Debug compiler output
package.path = package.path .. ";./sentinel/?.lua;./sentinel/modules/?.lua;./sentinel/modules/quest/?.lua"

local JSON = require("lib/JSON")
local ProfileCompiler = require("modules/quest/profile_compiler")

local core = {
    log = function(msg) print("[LOG] " .. msg) end,
    logError = function(msg) print("[ERROR] " .. msg) end,
    read_file = function(path)
        local f = io.open(path, "r")
        if f then local c = f:read("*a"); f:close(); return c end
        return nil
    end,
    time = function() return os.clock() * 1000 end,
}
_G.core = core

local QueryClient = {}
QueryClient.__index = QueryClient
function QueryClient.new(bb) return setmetatable({_bb = bb}, QueryClient) end
function QueryClient:fetch_quest(id)
    if id == 783 then
        return {title = "Test Quest", quest_level = 1, zone_or_sort = 0,
                req_creature_or_go_id1 = 80, req_creature_or_go_count1 = 8,
                start_npc = {id = 197, name = "Test NPC", x = 0, y = 0, z = 0, map_id = 0},
                end_npc = {id = 197, name = "Test NPC", x = 0, y = 0, z = 0, map_id = 0}}
    end
    return nil
end
function QueryClient:fetch_quest_npcs(id, role)
    if id == 783 then return {{npc_id = 197, name = "Test NPC", x = 0, y = 0, z = 0, map_id = 0}} end
    return {}
end

local QuestRegistry = {}
QuestRegistry.__index = QuestRegistry
function QuestRegistry.new(qc) return setmetatable({_client = qc, _cache = {}}, QuestRegistry) end
function QuestRegistry:getQuest(id)
    if self._cache[id] then return self._cache[id] end
    local data = self._client:fetch_quest(id)
    if data then self._cache[id] = data end
    return data
end
function QuestRegistry:getQuestNPCs(id, role) return self._client:fetch_quest_npcs(id, role) end

local PolicyLoader = {}
PolicyLoader.__index = PolicyLoader
function PolicyLoader.new(dir) return setmetatable({_dir = dir, _cache = {}}, PolicyLoader) end
function PolicyLoader:load(name)
    if self._cache[name] then return self._cache[name] end
    local path = self._dir .. "/" .. name .. ".yaml"
    local content = core.read_file(path)
    if not content then return nil end
    local policy = {name = name}
    for line in content:gmatch("[^\n]+") do
        local k, v = line:match("^(%w+):%s*(.+)$")
        if k and v then
            if v:match("^%[") then
                local arr = {}
                for item in v:gmatch("[^,%[%]]+") do
                    item = item:match("^%s*(.-)%s*$")
                    if item ~= "" then table.insert(arr, item) end
                end
                policy[k] = arr
            else
                policy[k] = v:match("^%s*(.-)%s*$")
            end
        end
    end
    self._cache[name] = policy
    return policy
end

local CoreActions = {}
CoreActions.__index = CoreActions
function CoreActions.new()
    local actions = {}
    local names = {"nav.followPolicy", "nav.cancel", "combat.setTargetFilter", "combat.clearTargetFilter",
        "combat.engage", "consume.useFood", "consume.stop", "vendor.sellJunk", "vendor.repair",
        "vendor.buyConsumables", "loot.lootAll", "quest.acceptQuest", "quest.turnInQuest",
        "quest.getAvailableQuests", "engine.selectBestReward", "core.log", "core.logError"}
    for _, name in ipairs(names) do
        actions[name] = function(ctx, ...) print("  [Action] " .. name .. "(" .. table.concat({...}, ", ") .. ")"); return true end
    end
    return setmetatable({_actions = actions, _signatures = {}}, CoreActions)
end
function CoreActions:validate(name) return self._actions[name] ~= nil end
function CoreActions:call(name, ctx, ...)
    local action = self._actions[name]
    if action then return action(ctx, ...) end
    return false, "Not found: " .. name
end

local Blackboard = {}
Blackboard.__index = Blackboard
function Blackboard.new() return setmetatable({_data = {}}, Blackboard) end
function Blackboard:get(key, def) return self._data[key] or def end
function Blackboard:set(key, val) self._data[key] = val end

local bb = Blackboard.new()
bb:set("player.level", 1)
bb:set("player.health_pct", 100)

local queryClient = QueryClient.new(bb)
local questRegistry = QuestRegistry.new(queryClient)
local policyLoader = PolicyLoader.new("sentinel/data/routing_policies")
local coreActions = CoreActions.new()

local profileYaml = core.read_file("sentinel/data/profiles/quests/test_profile.yaml")
print("=== Compiling Profile ===")
local compiler = ProfileCompiler.new(questRegistry, policyLoader, coreActions)
local result = compiler:compile(profileYaml)

print("ok:", result.ok)
print("errors:", #result.diagnostics.errors)
for _, err in ipairs(result.diagnostics.errors) do
    print("  ERROR [" .. err.path .. "]: " .. err.message)
end
print("warnings:", #result.diagnostics.warnings)
for _, warn in ipairs(result.diagnostics.warnings) do
    print("  WARN [" .. warn.path .. "]: " .. warn.message)
end

if result.ok then
    local compiled = result.compiled
    print("\nCompiled Profile:")
    print("  profile:", JSON.encode(compiled.profile))
    print("  variables:", JSON.encode(compiled.variables))
    print("  regions:", JSON.encode(compiled.regions))
    print("  states count:", 0)
    for k, v in pairs(compiled.states) do
        print("  state: " .. k .. " type=" .. v.type .. " parent=" .. tostring(v.parent) .. " region=" .. tostring(v.region))
    end
else
    print("Compilation failed!")
end