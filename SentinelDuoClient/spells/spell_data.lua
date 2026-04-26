-- spell_data.lua — Pre-extracted from MaNGOS DB. Do not edit manually.
-- Format: spell_data[spell_id] = { name, rank, mana_cost, cooldown_ms, max_range, min_range, cast_time_ms, school }
-- school 16 = Frost, school 64 = Arcane
local spell_data = {
    -- Blizzard (AoE ground-targeted, 8s channel, 8 ticks)
    [10185] = { name="Blizzard", rank=1,  mana_cost=320,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0,    school=16 },
    [10186] = { name="Blizzard", rank=2,  mana_cost=440,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0,    school=16 },
    [10187] = { name="Blizzard", rank=3,  mana_cost=560,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0,    school=16 },
    [10188] = { name="Blizzard", rank=4,  mana_cost=665,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0,    school=16 },
    [10189] = { name="Blizzard", rank=5,  mana_cost=765,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0,    school=16 },
    [10190] = { name="Blizzard", rank=6,  mana_cost=880,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0,    school=16 },
    [27085] = { name="Blizzard", rank=7,  mana_cost=1045, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0,    school=16 },  -- TBC max rank

    -- Frost Nova (instant AoE root around caster)
    [122]   = { name="Frost Nova", rank=1, mana_cost=65,  cooldown_ms=25000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [865]   = { name="Frost Nova", rank=2, mana_cost=75,  cooldown_ms=25000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [6131]  = { name="Frost Nova", rank=3, mana_cost=90,  cooldown_ms=25000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [10230] = { name="Frost Nova", rank=4, mana_cost=105, cooldown_ms=25000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [27088] = { name="Frost Nova", rank=5, mana_cost=115, cooldown_ms=25000, max_range=0, min_range=0, cast_time_ms=0, school=16 },  -- TBC max

    -- Ice Block (5min CD, 10s immunity)
    [45438] = { name="Ice Block", rank=1, mana_cost=0, cooldown_ms=300000, max_range=0, min_range=0, cast_time_ms=0, school=16 },

    -- Cold Snap (10min CD, resets Ice Block / Frost Nova / Ice Barrier CDs)
    [11958] = { name="Cold Snap", rank=1, mana_cost=0, cooldown_ms=600000, max_range=0, min_range=0, cast_time_ms=0, school=16 },

    -- Ice Barrier (absorb shield, talent)
    [11426] = { name="Ice Barrier", rank=4, mana_cost=375, cooldown_ms=30000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [13031] = { name="Ice Barrier", rank=5, mana_cost=440, cooldown_ms=30000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [13032] = { name="Ice Barrier", rank=6, mana_cost=515, cooldown_ms=30000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [13033] = { name="Ice Barrier", rank=7, mana_cost=595, cooldown_ms=30000, max_range=0, min_range=0, cast_time_ms=0, school=16 },  -- TBC max

    -- Counterspell (interrupt, 8s school lockout)
    [2139]  = { name="Counterspell", rank=1, mana_cost=150, cooldown_ms=24000, max_range=30, min_range=0, cast_time_ms=0, school=64 },

    -- Frostbolt (key ranks for tagging and rotation)
    [116]   = { name="Frostbolt", rank=1,  mana_cost=25,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=1500, school=16 },  -- pull tag (cheap)
    [205]   = { name="Frostbolt", rank=2,  mana_cost=35,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=1500, school=16 },
    [837]   = { name="Frostbolt", rank=3,  mana_cost=50,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=2000, school=16 },
    [7322]  = { name="Frostbolt", rank=4,  mana_cost=70,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=2500, school=16 },
    [8406]  = { name="Frostbolt", rank=5,  mana_cost=90,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=2500, school=16 },
    [8407]  = { name="Frostbolt", rank=6,  mana_cost=115, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=3000, school=16 },
    [8408]  = { name="Frostbolt", rank=7,  mana_cost=140, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=3000, school=16 },
    [10179] = { name="Frostbolt", rank=8,  mana_cost=170, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=3000, school=16 },
    [10180] = { name="Frostbolt", rank=9,  mana_cost=205, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=3000, school=16 },
    [10181] = { name="Frostbolt", rank=10, mana_cost=240, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=3000, school=16 },
    [25304] = { name="Frostbolt", rank=11, mana_cost=290, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=3000, school=16 },
    [27071] = { name="Frostbolt", rank=12, mana_cost=330, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=3000, school=16 },  -- TBC max

    -- Blink (teleport forward 20 yards)
    [1953]  = { name="Blink", rank=1, mana_cost=195, cooldown_ms=15000, max_range=0, min_range=0, cast_time_ms=0, school=64 },

    -- Evocation (8s channel, restores 100% mana, 8min CD)
    [12051] = { name="Evocation", rank=1, mana_cost=0, cooldown_ms=480000, max_range=0, min_range=0, cast_time_ms=0, school=64 },

    -- Cone of Cold
    [120]   = { name="Cone of Cold", rank=1, mana_cost=95,  cooldown_ms=10000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [8492]  = { name="Cone of Cold", rank=2, mana_cost=130, cooldown_ms=10000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [10159] = { name="Cone of Cold", rank=3, mana_cost=165, cooldown_ms=10000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [10160] = { name="Cone of Cold", rank=4, mana_cost=200, cooldown_ms=10000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [10161] = { name="Cone of Cold", rank=5, mana_cost=240, cooldown_ms=10000, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [27087] = { name="Cone of Cold", rank=6, mana_cost=290, cooldown_ms=10000, max_range=0, min_range=0, cast_time_ms=0, school=16 },  -- TBC max

    -- Ice Armor (frost armor replacement, defensive aura)
    [7302]  = { name="Ice Armor", rank=1, mana_cost=100, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [7320]  = { name="Ice Armor", rank=2, mana_cost=150, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [10219] = { name="Ice Armor", rank=3, mana_cost=250, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=16 },
    [10220] = { name="Ice Armor", rank=4, mana_cost=400, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=16 },  -- TBC max

    -- Dampen Magic (reduces magic damage taken, useful during pulls)
    [168]   = { name="Dampen Magic", rank=1, mana_cost=50,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0, school=64 },
    [7300]  = { name="Dampen Magic", rank=2, mana_cost=80,  cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0, school=64 },
    [7301]  = { name="Dampen Magic", rank=3, mana_cost=120, cooldown_ms=0, max_range=30, min_range=0, cast_time_ms=0, school=64 },

    -- Mana Shield
    [604]   = { name="Mana Shield", rank=1, mana_cost=50,  cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=64 },
    [8450]  = { name="Mana Shield", rank=2, mana_cost=60,  cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=64 },
    [8451]  = { name="Mana Shield", rank=3, mana_cost=70,  cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=64 },
    [10173] = { name="Mana Shield", rank=4, mana_cost=80,  cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=64 },
    [10174] = { name="Mana Shield", rank=5, mana_cost=90,  cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=64 },
    [33944] = { name="Mana Shield", rank=6, mana_cost=100, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=64 },

    -- Conjure Water
    [5504]  = { name="Conjure Water", rank=1, mana_cost=130, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [5505]  = { name="Conjure Water", rank=2, mana_cost=190, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [7326]  = { name="Conjure Water", rank=3, mana_cost=275, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [7327]  = { name="Conjure Water", rank=4, mana_cost=335, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [7328]  = { name="Conjure Water", rank=5, mana_cost=410, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [10138] = { name="Conjure Water", rank=6, mana_cost=505, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [10139] = { name="Conjure Water", rank=7, mana_cost=575, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [27090] = { name="Conjure Water", rank=8, mana_cost=665, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },  -- TBC max

    -- Conjure Food
    [587]   = { name="Conjure Food", rank=1, mana_cost=90,  cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [597]   = { name="Conjure Food", rank=2, mana_cost=130, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [990]   = { name="Conjure Food", rank=3, mana_cost=185, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [6129]  = { name="Conjure Food", rank=4, mana_cost=235, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [10144] = { name="Conjure Food", rank=5, mana_cost=290, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [10145] = { name="Conjure Food", rank=6, mana_cost=345, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },
    [28612] = { name="Conjure Food", rank=7, mana_cost=520, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=3000, school=64 },  -- TBC max

    -- Mana Shield (TBC max corrected)
    [27131] = { name="Mana Shield", rank=7, mana_cost=110, cooldown_ms=0, max_range=0, min_range=0, cast_time_ms=0, school=64 },

    -- Hearthstone item (tracked for CD, not a real spell from spellbook)
    [8690]  = { name="Hearthstone", rank=1, mana_cost=0, cooldown_ms=3600000, max_range=0, min_range=0, cast_time_ms=10000, school=0 },
}

return spell_data
