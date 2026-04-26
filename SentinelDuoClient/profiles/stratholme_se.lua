-- profiles/stratholme_se.lua
-- Stratholme Service Entrance — Frost Mage duo AoE farm profile.
--
-- ─── Coordinate provenance ────────────────────────────────────────────────────
--
--  CONFIRMED — sourced from binary DBC files (AreaTrigger.dbc, TaxiNodes.dbc)
--              extracted from the 2.4.3 TBC client, cross-verified against
--              cmangos-tbc C++ source (stratholme.h) and AzerothCore SQL.
--
--  DERIVED   — calculated from confirmed anchor points using known dungeon layout.
--              Reliable within ±5 yards but should still be captured in-game.
--
--  CAPTURE   — no reliable source found; must be recorded in-game via ProfileTab.
--
-- ─── Critical fixes vs. v1 ────────────────────────────────────────────────────
--
--  * gate_object_id corrected to 175368 (GO_SERVICE_ENTRANCE per cmangos source).
--    The old value 183396 is "Zeppelin Debris" in Hellfire Peninsula — wrong.
--
--  * Outdoor coordinates overhauled. The area trigger for the Service Entrance
--    (AT 2214) sits at x=3237.46, y=-4060.60 on map 0. The old profile had
--    x=3318, y=-3483 which is ~1 km off.
--
--  * Light's Hope Chapel flight node confirmed from TaxiNodes.dbc:
--    x=2271.09, y=-5340.80, z=87.11.  The old profile had x=3439, y=-1364
--    which is a completely different zone.
--
--  * Aerie Peak flight node confirmed from TaxiNodes.dbc:
--    x=283.74, y=-2002.76, z=194.74.
--
--  * Instance portal confirmed: x=3590.87, y=-3643.22, z=138.491 (map 318).
--
--  * Gauntlet boundary confirmed from AT 2187: x=3673.60, y=-3633.87.
--    Elders' Square occupies roughly x=3585–3673; do NOT pull past x=3668.
--
-- ─────────────────────────────────────────────────────────────────────────────

local Profile = {}

Profile.id              = "stratholme_se_v3"
Profile.dungeon_name    = "Stratholme Service Entrance"
Profile.instance_map_id = 318   -- core.get_map_id() returns 318 in-game (TBC client ID)
Profile.outdoor_map_id  = 0     -- Eastern Kingdoms continent map

-- ─────────────────────────────────────────────────────────────────────────────
-- OUTDOOR — Eastern Plaguelands (map 0)
--
-- Geography recap:
--   Light's Hope Chapel (LHC) is in southern EPL at (2271, -5340).
--   The Service Entrance gate is in northeastern EPL at approx (3237, -4053).
--   Path from LHC goes northeast via the tower road: LHC → Eastwall Tower
--   → Northpass Tower → SE gate.
-- ─────────────────────────────────────────────────────────────────────────────

-- Where the instance area trigger fires (AT 2214).  Standing here teleports
-- the player inside after the gate has been opened.
-- CONFIRMED: AreaTrigger.dbc row 2214, map=0, box 10×10×10.
Profile.entrance_position = { x = 3237.46, y = -4060.60, z = 112.01 }

-- Short walk from the road down to the gate, then to the trigger.
-- Gate is a few yards north of the area trigger; trigger at y=-4060.
-- CAPTURE: walk this path in-game and record each waypoint.
Profile.entrance_walk_path = {
    { x = 3237.0, y = -4025.0, z = 112.0 },  -- CAPTURE: road approach, top of path
    { x = 3237.0, y = -4040.0, z = 112.0 },  -- CAPTURE: mid-approach to gate
    { x = 3237.5, y = -4053.0, z = 112.0 },  -- CAPTURE: gate position (just before trigger)
    { x = 3237.5, y = -4060.6, z = 112.0 },  -- DERIVED: area trigger (triggers instance entry)
}

-- Physical gate gameobject — requires Key to the City (item 12382) to open.
-- CONFIRMED: GO_SERVICE_ENTRANCE = 175368 (stratholme.h line 63, cmangos-tbc).
-- Position is estimated just north of the area trigger; CAPTURE in-game.
Profile.gate_position    = { x = 3237.46, y = -4053.0,  z = 112.01 }  -- DERIVED
Profile.gate_object_id   = 175368   -- GO_SERVICE_ENTRANCE (cmangos source confirmed)
Profile.gate_key_item_id = 12382    -- "Key to the City"

-- ─────────────────────────────────────────────────────────────────────────────
-- INSIDE — Path from instance portal into Elders' Square
--
-- CONFIRMED: Instance portal lands at (3590.87, -3643.22, 138.491).
-- Service Entrance exit trigger (AT 2221): (3584.78, -3632.05, z=142.12).
-- Gauntlet entrance trigger  (AT 2187): (3673.60, -3633.87, z=139.94).
-- Elders' Square runs east from the portal to approximately x=3668 before
-- the gauntlet gate (GO 175357).  Do NOT pull past x=3668.
-- ─────────────────────────────────────────────────────────────────────────────
Profile.inside_walk_path = {
    { x = 3590.87, y = -3643.22, z = 138.49 },  -- CONFIRMED: instance portal entry (AT 2214 dest)
    { x = 3598.0,  y = -3643.0,  z = 138.5  },  -- DERIVED: a few steps east into corridor
    { x = 3608.0,  y = -3643.0,  z = 138.5  },  -- DERIVED: entrance of Elders' Square
}

-- Exit via death — mobs kill both mages quickly anywhere inside.
-- DERIVED: deep inside Elders' Square, east of pull 2, before gauntlet gate.
Profile.exit_position  = { x = 3666.0, y = -3637.0, z = 139.5 }
Profile.exit_use_death = true

-- ─────────────────────────────────────────────────────────────────────────────
-- PULL DEFINITIONS
--
-- Elders' Square (first farming area after Service Entrance):
--   x range: 3590–3668 (confirmed by portal anchor + gauntlet AT boundary)
--   y range: ~-3630 to -3650 (central corridor, confirmed AT 2221 width ≈18y)
--   z range: ~138–142
--
-- Undead population: mixed elite undead (Stratholme Courier, Risen Guard,
-- Skeletal Guardian NPC_SKELETAL_GUARDIAN=10390, Berserker=10391, etc.).
-- No Timmy the Cruel near SE (Timmy is on the Scarlet side at x=3614, y=-3187).
--
-- Pull strategy (duo frost mage):
--   Puller runs pull_path to tag mobs, retreats to ice_block_position, Ice Blocks.
--   Support waits at safe_position, casts Blizzard on blizzard_center on IB confirm.
--   After IB cancel: both Frost Nova, reposition, continue AoE until dead.
--   Puller on first pull skips pull_start barrier (concurrent entry design).
-- ─────────────────────────────────────────────────────────────────────────────
Profile.pulls = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- PULL 1 — Elders' Square: Entry corridor groups
--
-- Puller starts immediately after entering (first-pull concurrent logic in
-- FarmPositioning.lua).  Tags groups 1–2 just east of the portal, retreats
-- to near-portal IB spot.  Support enters gate, walks to safe_position, and
-- casts Blizzard once IB is confirmed.
-- ─────────────────────────────────────────────────────────────────────────────
Profile.pulls[1] = {
    id = 1,

    -- Puller runs east, tags mobs, then retreats west to ice_block_position.
    -- DERIVED from confirmed portal (3590, -3643) + Elders' Square layout.
    pull_path = {
        { x = 3614.0, y = -3643.0, z = 138.5 },  -- DERIVED: 23 yards east of portal
        { x = 3635.0, y = -3643.0, z = 138.5 },  -- DERIVED: mid first cluster
        { x = 3652.0, y = -3643.0, z = 139.0 },  -- DERIVED: far end of entry groups
    },

    aggro_radius           = 18.0,
    pull_tag_spell         = "frostbolt_r1",
    expected_mob_count_min = 4,
    expected_mob_count_max = 10,

    -- Puller IB spot — well behind the mob stack, near the entrance portal.
    -- DERIVED: ~22 yards west of mid pull-path; safe from Blizzard splash.
    ice_block_position = { x = 3598.0, y = -3643.0, z = 138.5 },

    -- Blizzard lands where mobs chase the retreating puller and stack up.
    -- DERIVED: midway between IB spot and pull-path midpoint.
    blizzard_center    = { x = 3630.0, y = -3643.0, z = 138.5 },

    -- Support stands here to cast Blizzard — must be within 35 yards of blizzard_center.
    -- 3600 → 3630 = 30 yards west; safely behind the puller's IB spot (3598).
    blizzard_position  = { x = 3600.0, y = -3643.0, z = 138.5 },  -- DERIVED

    -- Support waits here while puller runs.  Behind aggro range, facing east.
    -- CONFIRMED anchor: AT 2221 exit trigger at (3584.78, -3632.05); support
    -- stands just east of that near the portal.
    safe_position      = { x = 3593.0, y = -3638.0, z = 138.5 },

    -- Where puller moves after IB cancel to join AoE (beside IB spot, east-facing).
    puller_reposition  = { x = 3608.0, y = -3643.0, z = 138.5 },

    mob_ids       = {},   -- target all hostile mobs
    mob_ids_avoid = {},   -- nothing to avoid in this zone
    pull_delay_ms = 500,

    timing = {
        pull_to_ib_mob_count      = 4,      -- IB when ≥4 mobs following
        ice_block_cancel_delay_ms = 3000,   -- cancel IB after 3 s (Blizzard ticking)
        loot_settle_ms            = 2000,
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- PULL 2 — Elders' Square: Deeper groups (east half)
--
-- After pull 1 clears, safe_position advances into cleared area.
-- Puller pulls groups at x=3650–3665, retreating west to cleared pull-1 area.
-- Stay below x=3668 to avoid triggering the Gauntlet gate (AT 2187 at x=3673).
-- ─────────────────────────────────────────────────────────────────────────────
Profile.pulls[2] = {
    id = 2,

    pull_path = {
        { x = 3653.0, y = -3640.0, z = 139.0 },  -- DERIVED: east of pull-1 clear area
        { x = 3662.0, y = -3638.0, z = 139.5 },  -- DERIVED: second cluster
        { x = 3667.0, y = -3636.0, z = 139.5 },  -- DERIVED: near gauntlet gate (do NOT cross x=3668)
    },

    aggro_radius           = 18.0,
    pull_tag_spell         = "frostbolt_r1",
    expected_mob_count_min = 4,
    expected_mob_count_max = 12,

    -- DERIVED: retreat west into cleared pull-1 area
    ice_block_position = { x = 3638.0, y = -3642.0, z = 138.5 },
    blizzard_center    = { x = 3656.0, y = -3639.0, z = 139.0 },
    -- Support stands ~26 yards west of blizzard_center for Blizzard casting range.
    blizzard_position  = { x = 3630.0, y = -3642.0, z = 138.5 },  -- DERIVED
    safe_position      = { x = 3618.0, y = -3643.0, z = 138.5 },
    puller_reposition  = { x = 3642.0, y = -3642.0, z = 138.5 },

    mob_ids       = {},
    mob_ids_avoid = {},   -- Timmy is far away (Scarlet side x=3614, y=-3187)
    pull_delay_ms = 500,

    timing = {
        pull_to_ib_mob_count      = 4,
        ice_block_cancel_delay_ms = 3000,
        loot_settle_ms            = 2000,
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Vendor Route (Alliance)
--
-- Flow: Hearthstone to Aerie Peak (Hinterlands) → vendor/repair at Aerie Peak
--       → fly Aerie Peak → Light's Hope Chapel (Eastern Plaguelands)
--       → walk northeast from LHC to Stratholme SE gate.
--
-- Aerie Peak flight node:  x=283.74,  y=-2002.76, z=194.74  (TaxiNodes.dbc #43)
-- LHC flight node:         x=2271.09, y=-5340.80, z=87.11   (TaxiNodes.dbc #67)
--
-- Intermediate tower positions on the walkback road (confirmed TaxiNodes.dbc):
--   Eastwall Tower:   x=2499.23, y=-4742.85, z=93.50
--   Northpass Tower:  x=3109.31, y=-4285.13, z=109.45
-- ─────────────────────────────────────────────────────────────────────────────
Profile.vendor_route = {
    hearthstone_item_id       = 6948,
    hearthstone_dest_map_id   = 0,
    -- CAPTURE: stand at the Aerie Peak inn hearthstone bind point and record.
    -- Rough area: near Aerie Peak flight master at (283.74, -2002.76, 194.74).
    hearthstone_dest_position = { x = 283.74, y = -2002.76, z = 194.74 },  -- CAPTURE (near FM)

    -- CAPTURE: Aerie Peak general goods vendor NPC ID and position.
    -- Shandy Glossgleam or another vendor inside the peak.
    vendor_npc_id   = 0,      -- CAPTURE: use .npc info on vendor to get entry
    vendor_position = { x = 283.0, y = -2010.0, z = 194.0 },  -- CAPTURE
    repair_at_vendor = true,

    -- CAPTURE: Aerie Peak flight master (Gryphon Master Talonaxe or similar).
    -- DBC gives the landing node position; the NPC is right there.
    -- CONFIRMED: TaxiNodes.dbc node 43 at (283.74, -2002.76, z=194.74).
    flight_master_npc_id   = 0,       -- CAPTURE: use .npc info on the gryphon master
    flight_master_position = { x = 283.74, y = -2002.76, z = 194.74 },  -- CONFIRMED (taxi node)
    taxi_dest_name         = "Light's Hope Chapel, Eastern Plaguelands",
    flight_dest_map_id     = 0,
    -- CONFIRMED: TaxiNodes.dbc node 67 (Alliance LHC landing).
    flight_dest_position   = { x = 2271.09, y = -5340.80, z = 87.11 },  -- CONFIRMED

    flight_arrive_detect_timeout_ms = 300000,  -- 5 minutes max for flight

    -- Walk from Light's Hope Chapel northeast to Stratholme SE gate.
    -- Total distance: ~1050 units east + ~1287 units north (long trek).
    -- Intermediate confirmed waypoints from TaxiNodes.dbc tower positions.
    -- Road runs: LHC → east → northeast via towers → approach SE from south.
    walkback_path = {
        -- CONFIRMED: LHC Alliance flight master landing (TaxiNodes #67).
        { x = 2271.09, y = -5340.80, z =  87.11 },

        -- CAPTURE: first turn northeast onto EPL road from LHC area.
        { x = 2350.0,  y = -5200.0,  z =  90.0  },  -- CAPTURE

        -- CONFIRMED: Eastwall Tower taxi node (TaxiNodes #86) — road waypoint.
        { x = 2499.23, y = -4742.85, z =  93.50 },

        -- CAPTURE: road bend northeast toward Northpass Tower.
        { x = 2800.0,  y = -4550.0,  z = 100.0  },  -- CAPTURE

        -- CONFIRMED: Northpass Tower taxi node (TaxiNodes #85) — road waypoint.
        { x = 3109.31, y = -4285.13, z = 109.45 },

        -- CAPTURE: approach road toward SE (northeast of Northpass Tower).
        { x = 3190.0,  y = -4150.0,  z = 110.0  },  -- CAPTURE

        -- CAPTURE: final approach to SE gate from road above.
        { x = 3237.0,  y = -4075.0,  z = 112.0  },  -- CAPTURE

        -- DERIVED: just north of the area trigger; walk into trigger fires TP.
        { x = 3237.46, y = -4053.0,  z = 112.01 },
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Global timing
-- ─────────────────────────────────────────────────────────────────────────────
Profile.timing = {
    pull_to_ib_mob_count              = 4,      -- IB when puller has ≥N mobs following
    ice_block_cancel_delay_ms         = 3000,   -- cancel IB after Blizzard has ticked once
    frost_nova_after_ib_cancel_ms     = 200,    -- slight delay before Frost Nova after IB cancel
    blizzard_recast_buffer_ms         = 500,    -- recast Blizzard 500ms before it expires
    loot_settle_ms                    = 2000,   -- wait after last mob dies before looting
    between_pulls_ms                  = 1500,   -- pause between pull cycles
    hs_landing_detect_timeout_ms      = 30000,  -- 30s: time out waiting for HS animation
    flight_arrive_detect_timeout_ms   = 300000, -- 5min: wait for flight to arrive at LHC
    barrier_timeout_ms                = 90000,  -- 90s: max barrier wait before solo proceed
}

Profile.min_mana_pct_to_pull = 0.60  -- puller needs ≥60% mana before pulling
Profile.min_hp_pct_to_pull   = 0.50  -- both mages need ≥50% HP
Profile.bags_full_threshold  = 4     -- vendor when free slots ≤ 4

return Profile
