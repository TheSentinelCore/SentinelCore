#!/usr/bin/env luajit
-- Generate quest data packs from TBC database for route planning
-- Run: luajit modules/quest/generate_data_pack.lua

package.path = "sentinel/?.lua;sentinel/?/?.lua;sentinel/?/?/?.lua;" .. package.path

local JSON = require("lib/JSON")

-- TBC starting zones for Humans: Northshire (12), Elwynn (132), Westfall (40), Redridge (141), Duskwood (1657)
local HUMAN_ZONES = { 12, 132, 40, 141, 1657 }

local DATABASE_PATH = "../Database/tbcmangos.sqlite"
local OUTPUT_DIR = "sentinel/data/quests"

-- Query SQLite database directly (offline generation)
local function query_db(sql)
    local handle = io.popen(string.format(
        "sqlite3 -json '%s' \"%s\" 2>/dev/null",
        DATABASE_PATH, sql
    ), "r")
    if not handle then return "{}" end
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Generate level band quests for Humans
local function generate_human_quests(min_level, max_level)
    local zones_str = table.concat(HUMAN_ZONES, ",")
    local sql = string.format(
        [[SELECT entry, Title, MinLevel, QuestLevel, ZoneOrSort 
           FROM quest_template 
           WHERE MinLevel >= %d AND MinLevel <= %d 
           AND PrevQuestId = 0 
           AND SpecialFlags = 0 
           AND (RequiredRaces = 1 OR RequiredRaces = 1101)
           AND QuestLevel > 0 AND QuestLevel <= %d
           AND ZoneOrSort IN (%s)
           AND Title NOT LIKE '%%Brewfest%%'
           AND Title NOT LIKE '%%Lunar%%'
           AND Title NOT LIKE '%%Festival%%'
           ORDER BY ZoneOrSort, QuestLevel]],
        min_level, max_level, max_level, zones_str
    )
    local quests_json = query_db(sql)
    return JSON:decode(quests_json) or {}
end

local function main()
    print("Generating Human quest data pack for levels 1-10...")
    
    os.execute(string.format("mkdir -p %s", OUTPUT_DIR))
    
    local quests = generate_human_quests(1, 10)
    
    local output = {
        generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        race = "human",
        level_band = { min = 1, max = 10 },
        zones = HUMAN_ZONES,
        quests = {},
    }
    
    for _, quest in ipairs(quests) do
        output.quests[#output.quests + 1] = {
            id = quest.entry,
            title = quest.Title,
            min_level = quest.MinLevel,
            quest_level = quest.QuestLevel,
            zone_id = quest.ZoneOrSort,
        }
    end
    
    local output_json = JSON:encode(output, true)
    local file = io.open(string.format("%s/human_1_10.json", OUTPUT_DIR), "w")
    if file then
        file:write(output_json)
        file:close()
        print(string.format("Generated %d quests to %s/human_1_10.json", #output.quests, OUTPUT_DIR))
    end
end

main()