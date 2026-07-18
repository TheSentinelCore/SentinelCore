package.path = './sentinel/?.lua;' .. package.path
local ProfileCompiler = require('modules/quest/profile_compiler')
local JSON = require('lib/JSON')

local core = {log = print, logError = print, read_file = function(path) local f = io.open(path, 'r') if f then local c = f:read('*a') f:close() return c end return nil end}
_G.core = core

-- Mock QueryClient with proper quest data
local MockQueryClient = {}
MockQueryClient.__index = MockQueryClient
function MockQueryClient.new()
    local self = setmetatable({_quests = {}, _npcs = {}}, MockQueryClient)
    
    -- Quest data for all quests in the profile
    self._quests = {
        [783] = {title='A Threat Within', quest_level=1, zone_or_sort=0, req_creature_or_go_id1=80, req_creature_or_go_count1=10, prev_quest_id=0, next_quest_id=7},
        [7] = {title='The Latent Memory', quest_level=1, zone_or_sort=0, req_creature_or_go_id1=80, req_creature_or_go_count1=8, prev_quest_id=783, next_quest_id=15},
        [15] = {title='Investigate Echo Ridge', quest_level=2, zone_or_sort=0, prev_quest_id=7, next_quest_id=0},
        [54] = {title='Report to Goldshire', quest_level=5, zone_or_sort=0, prev_quest_id=7, next_quest_id=62},
        [62] = {title='The Fargodeep Mine', quest_level=6, zone_or_sort=0, req_creature_or_go_id1=474, req_creature_or_go_count1=6, prev_quest_id=54, next_quest_id=76},
        [76] = {title='The Jasperlode Mine', quest_level=7, zone_or_sort=0, req_creature_or_go_id1=476, req_creature_or_go_count1=10, prev_quest_id=62, next_quest_id=0},
        [87] = {title='Collecting Kelp', quest_level=5, zone_or_sort=0, req_item_id1=1930, req_item_count1=4, prev_quest_id=54, next_quest_id=91},
        [91] = {title='Murlocs in the Lake', quest_level=5, zone_or_sort=0, req_creature_or_go_id1=482, req_creature_or_go_count1=8, prev_quest_id=87, next_quest_id=0},
        [47] = {title='Guard Thomas', quest_level=7, zone_or_sort=0, req_creature_or_go_id1=482, req_creature_or_go_count1=8, prev_quest_id=91, next_quest_id=52},
        [52] = {title='Protect the Frontier', quest_level=8, zone_or_sort=0, req_creature_or_go_id1=483, req_creature_or_go_count1=8, prev_quest_id=47, next_quest_id=0},
        [62] = {title='The Fargodeep Mine', quest_level=6, zone_or_sort=0, req_creature_or_go_id1=474, req_creature_or_go_count1=6, prev_quest_id=54, next_quest_id=76},
        [76] = {title='The Jasperlode Mine', quest_level=7, zone_or_sort=0, req_creature_or_go_id1=476, req_creature_or_go_count1=10, prev_quest_id=62, next_quest_id=0},
        [87] = {title='Collecting Kelp', quest_level=5, zone_or_sort=0, req_item_id1=1930, req_item_count1=4, prev_quest_id=54, next_quest_id=91},
        [91] = {title='Murlocs in the Lake', quest_level=5, zone_or_sort=0, req_creature_or_go_id1=482, req_creature_or_go_count1=8, prev_quest_id=87, next_quest_id=0},
        [47] = {title='Guard Thomas', quest_level=7, zone_or_sort=0, req_creature_or_go_id1=482, req_creature_or_go_count1=8, prev_quest_id=91, next_quest_id=52},
        [52] = {title='Protect the Frontier', quest_level=8, zone_or_sort=0, req_creature_or_go_id1=483, req_creature_or_go_count1=8, prev_quest_id=47, next_quest_id=0},
        [3104] = {title='Skirmish at Echo Ridge', quest_level=2, zone_or_sort=0, prev_quest_id=15, next_quest_id=0},
        [19] = {title='Investigate Echo Ridge', quest_level=2, zone_or_sort=0, prev_quest_id=15, next_quest_id=0},
        [20] = {title='Skirmish at Echo Ridge', quest_level=2, zone_or_sort=0, prev_quest_id=15, next_quest_id=0},
    }
    return self
end
function MockQueryClient:fetch_quest(id)
    return self._quests[id]
end
function MockQueryClient:fetch_quest_npcs(id, role)
    local npcs = {
        [783] = {giver={{npc_id=197,name='Marshal McBride',x=-8900,y=-100,z=80,map_id=0}}, turnin={{npc_id=197,name='Marshal McBride',x=-8900,y=-100,z=80,map_id=0}}},
        [7] = {giver={{npc_id=197,name='Marshal McBride',x=-8900,y=-100,z=80,map_id=0}}, turnin={{npc_id=197,name='Marshal McBride',x=-8900,y=-100,z=80,map_id=0}}},
        [54] = {giver={{npc_id=296,name='Marshal Dughan',x=-9400,y=-200,z=85,map_id=0}}, turnin={{npc_id=296,name='Marshal Dughan',x=-9400,y=-200,z=85,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
    }
    return self._quests[id]
end
function MockQueryClient:fetch_quest_npcs(id, role)
    local npcs = {
        [783] = {giver={{npc_id=197,name='Marshal McBride',x=-8900,y=-100,z=80,map_id=0}}, turnin={{npc_id=197,name='Marshal McBride',x=-8900,y=-100,z=80,map_id=0}}},
        [7] = {giver={{npc_id=197,name='Marshal McBride',x=-8900,y=-100,z=80,map_id=0}}, turnin={{npc_id=197,name='Marshal McBride',x=-8900,y=-100,z=80,map_id=0}}},
        [54] = {giver={{npc_id=296,name='Marshal Dughan',x=-9400,y=-200,z=85,map_id=0}}, turnin={{npc_id=296,name='Marshal Dughan',x=-9400,y=-200,z=85,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
        [47] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [52] = {giver={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}, turnin={{npc_id=295,name='Guard Thomas',x=-9000,y=-400,z=80,map_id=0}}},
        [62] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [76] = {giver={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}, turnin={{npc_id=297,name='William Pestle',x=-9500,y=-300,z=80,map_id=0}}},
        [87] = {giver={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}, turnin={{npc_id=299,name='Smith Argus',x=-9300,y=-150,z=80,map_id=0}}},
        [91] = {giver={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}, turnin={{npc_id=298,name='Auntie Bernice',x=-9400,y=-100,z=85,map_id=0}}},
    }
    return npcs[id] and npcs[id][role] or {}
end

local MockPolicyLoader = {load = function(self, name) return {name=name, strategy='smart', preferredPath='road', avoid={'elite','water'}, dynamicReplan=true, allowShortcuts=true} end}

local CoreActions = {}
CoreActions.__index = CoreActions
function CoreActions.new()
    local actions = {}
    local names = {'nav.followPolicy','nav.cancel','combat.setTargetFilter','combat.clearTargetFilter','combat.engage','consume.useFood','consume.useWater','consume.stop','vendor.sellJunk','vendor.repair','vendor.buyConsumables','loot.lootAll','quest.acceptQuest','quest.turnInQuest','quest.getAvailableQuests','quest.acceptAllQuestsAtNpc','quest.turnInQuest','quest.getAvailableQuests','engine.selectBestReward','consume.useFood','consume.useWater','consume.useBandage','consume.stop','vendor.sellJunk','vendor.repair','vendor.buyConsumables','trainer.trainAvailable','loot.lootAll','movement.mount','movement.dismount','core.log','core.logError','interact.acceptQuest','interact.turnInQuest','interact.bindHearthstone','consume.useFood','consume.useWater','consume.useBandage','consume.stop','vendor.sellJunk','vendor.repair','vendor.buyConsumables','trainer.trainAvailable','loot.lootAll','movement.mount','movement.dismount','core.log','core.logError','interact.acceptQuest','interact.turnInQuest','interact.bindHearthstone','consume.useFood','consume.useWater','consume.useBandage','consume.stop','vendor.sellJunk','vendor.repair','vendor.buyConsumables','trainer.trainAvailable','loot.lootAll','movement.mount','movement.dismount'}
    for _, name in ipairs(names) do actions[name] = function(ctx, ...) print('  [Action]', name, ...); return true end end
    local instance = {_actions = actions, _signatures = {}}
    setmetatable(instance, CoreActions)
    CoreActions.__index = function(t,k) return t._actions[k] or CoreActions[k] end
    return instance
end
function CoreActions:validate(name) return self._actions[name] ~= nil end
function CoreActions:call(name, ctx, ...) local action = self._actions[name] if action then return action(ctx, ...) end return false, "Not found: " .. name end

local CoreActions = CoreActions.new()

local MockQueryClient = {}
MockQueryClient.__index = MockQueryClient
function MockQueryClient.new(bb) return setmetatable({_blackboard = bb, _quests = {}}, MockQueryClient) end
function MockQueryClient:fetch_quest(id) return self._quests[id] end
function MockQueryClient:fetch_quest_npcs(id, role) local npcs = self._npcs[id] return npcs and npcs[role] or {} end

local MockPolicyLoader = {load = function(self, name) return {name=name, strategy='smart', preferredPath='road', avoid={'elite','water'}, dynamicReplan=true, allowShortcuts=true} end}

local CoreActions = CoreActions.new()

local QuestRegistry = {}
QuestRegistry.__index = QuestRegistry
function QuestRegistry.new(qc) return setmetatable({_client = qc, _cache = {}}, QuestRegistry) end
function QuestRegistry:getQuest(id) if self._cache[id] then return self._cache[id] end local data = self._client:fetch_quest(id) if data then self._cache[id] = data end return data end
function QuestRegistry:getQuestNPCs(id, role) return self._client:fetch_quest_npcs(id, role) end

local core = {log = print, logError = print, read_file = function(path) local f = io.open(path, 'r') if f then local c = f:read('*a') f:close() return c end return nil end}
_G.core = core

local questRegistry = QuestRegistry.new(MockQueryClient.new())
local policyLoader = {load = function(self, name) return {name=name, strategy='smart', preferredPath='road', avoid={'elite','water'}, dynamicReplan=true, allowShortcuts=true} end}

local ProfileCompiler = require('modules/quest/profile_compiler')
local compiler = ProfileCompiler.new(questRegistry, {load = function(self, name) return {name=name, strategy='smart', preferredPath='road', avoid={'elite','water'}, dynamicReplan=true, allowShortcuts=true} end}, {validate = function(self, name) return true end, call = function(self, name, ctx, ...) print('[ACTION]', name, ...) return true end})

local core = {log = print, logError = print, read_file = function(path) local f = io.open(path, 'r') if f then local c = f:read('*a') f:close() return c end return nil end}
_G.core = core

local yaml = core.read_file('sentinel/data/profiles/quests/alliance_human_01_10_elwynn.yaml')
print('=== Compiling Profile ===')
local result = compiler:compile(yaml)
if result.ok then
  print('Compilation successful!')
  local count = 0
  for _ in pairs(result.compiled.states) do count = count + 1 end
  print('States:', count)
  for k,_ in pairs(result.compiled.regions) do print('  Region: ' .. k) end
else
  print('Compilation failed:')
  for _, err in ipairs(result.diagnostics.errors) do
    print('  ERROR [' .. err.path .. ']: ' .. err.message)
  end
  for _, warn in ipairs(result.diagnostics.warnings) do
    print('  WARN [' .. warn.path .. ']: ' .. warn.message)
  end
end