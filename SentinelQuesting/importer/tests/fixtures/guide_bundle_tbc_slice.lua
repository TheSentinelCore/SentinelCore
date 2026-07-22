RXPGuides.RegisterGuide([[
#version 1
#tbc
#classic
#include QuestDB
#group RestedXP TBC Preparation
#subgroup Turn-in Guide
#name Prep-Silithus Start
#chapter
#title Pre-launch Preparation
<< Alliance
step
>>Before starting, double check and make sure you have the following flight paths:
.fp Silvermoon,2 >> Silvermoon City, Eversong Woods << Horde
.goto Eversong Woods,54.4,50.8,0 << Horde
.fp Tranquillien,2 >> Tranquillien, Ghostlands << Horde
.goto Ghostlands,45.6,30.6,0 << Horde
.fp Nethergarde,2 >> Nethergarde Keep, Blasted Lands << Alliance
.goto Blasted Lands,65.6,24.4,0 << Alliance
.fp Stonard,2 >> Stonard, Swamp of Sorrows << Horde
.goto Swamp of Sorrows,46.0,54.4,0 << Horde
.fp Emerald Sanctuary,2 >> Emerald Sanctuary, Felwood
.goto Felwood,51.6,82.2,0
step
.setturninhs
step << Hunter
#optional
#completewith next
+|cRXP_WARN_Swap your quiver for an extra bag for the turn in section. You will most likely need the extra bag space!|r
step
#include TurnInPrep2
]]);
RXPGuides.RegisterGuide([[
#version 1
#tbc
#classic
#include QuestDB
#group RestedXP TBC Preparation
#subgroup Preparation guide
#chapter
#title Dire Maul East
#name DM East
#next Select Dungeon
step
>>Look for a dungeon group for Dire Maul East (DME)
>>Clear the dungeon and kill the endboss |cRXP_ENEMY_Alzzin the Wildshaper|r
>>Loot a |T132884:0|t[|cRXP_PICK_Felvine Shard|r] from the ground next to a big thorn to the right of the dungeon exit tunnel
.collect 18501,1 
.isQuestAvailable 5526
step
+You have completed this section of the guide. |cRXP_WARN_Select another one to continue|r
>>|cRXP_WARN_You'll need to do Strat Live and Scholomance before Strat Undead|r, other than that, you can do the dungeon section in any order
.clicknext BRD >> BRD
.clicknext UBRS >> UBRS
.clicknext LBRS >> LBRS
.clicknext Scholo >> Scholo
.clicknext Strat Live >> Strat Live
.clicknext Strat Undead >> Strat Undead
]]);
