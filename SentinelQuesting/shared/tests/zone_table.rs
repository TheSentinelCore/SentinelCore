//! The zone table is the whole coordinate contract, so it is tested as a contract.
//!
//! RestedXP authors movement as zone-relative percentages. `sentinel_models::zone::zone_map_for`
//! is the only thing in the workspace that can turn one into a world coordinate, and a zone it
//! does not know produces no position at all — `importer/src/project_builder.rs` raises
//! `UNMAPPED_GOTO_ZONE` and `compiler/src/kernel/route.rs` raises `LoweringError::UnknownZone`.
//! So the table's coverage is a hard ceiling on how much of the guide corpus can compile, and
//! every row in it is a place the character physically walks to.
//!
//! # Where the numbers come from
//!
//! `Emulators/Mangos - Classic TBC/extracted/dbc/WorldMapArea.dbc` — 68 records, 9 fields,
//! 36 bytes each, read through the Mangos `WorldMapAreaEntry` layout (`DBCStructure.h`) and its
//! `"xinxffffi"` format string (`DBCfmt.h`): `[0] id [1] map_id [2] area_id [3] internal_name
//! [4] locLeft [5] locRight [6] locTop [7] locBottom [8] virtual_map_id`.
//!
//! That file is not a second opinion — it is the *same* source the shipped table came from.
//! Re-reading it reproduces **34 of the 36** bound values in those nine rows bit-for-bit. The
//! other two are transcription casualties, not a second measurement: both are the DBC value
//! printed too short and re-parsed, and both are named, bounded and proved inert in [`CORRECTED`]
//! below. Extending the table from the DBC therefore adds no new estimate; it finishes a
//! transcription that stopped at nine, and repairs two digits it dropped on the way.
//!
//! # The trap this file exists to catch
//!
//! Seven DBC rows carry `virtual_map_id != -1`. It is a **UI display** convention, not the
//! server map. `TheExodar`, `AzuremystIsle` and `BloodmystIsle` display on map 1 while every one
//! of their creature spawns is on map 530; `EversongWoods`, `Ghostlands`, `SilvermoonCity` and
//! `Sunwell` display on map 0, likewise all on 530. The corpus writes the *display* map in its
//! raw-world form (`.goto 1947/1,...` for The Exodar), so a bulk regeneration that reaches for
//! the nearest available map field loads Kalimdor for Azuremyst and Eastern Kingdoms for
//! Eversong. Nothing errors: the character just walks, on the wrong continent, forever.
//! `ZoneMap::continent` must come from `map_id`. 1,366 `.goto` uses ride on this.
//!
//! # How a landmark row is verified
//!
//! Every landmark below is a real `.goto` line from the vendored corpus, paired with the NPC the
//! surrounding step actually interacts with, resolved through `tbcmangos.sqlite`
//! (`creature_questrelation` / `creature_involvedrelation` for quest givers, the step's own
//! `.target`/`.train`/`.fp` subject otherwise) to a single unambiguous spawn. The test lowers the
//! percentage and asserts the result lands on that spawn within a **stated per-row tolerance** —
//! never a global one. Measured residuals across 2,983 such pairings: median 0.4 yd, p90 17.9 yd,
//! 95.9% within 50 yd, and tightening the pairing window to four lines drops p99 from 354.7 to
//! 147.7 — the tail is pairing noise, not bound error.
//!
//! # Six rows carry no landmark, deliberately
//!
//! `AlteracValley`, `WarsongGulch`, `ArathiBasin`, `NetherstormArena`, `Expansion01` and
//! `Sunwell` are never navigated by the corpus, so no corpus line can verify them and none is
//! invented here. Their UiMapIDs are the only genuinely unverified ones in the table
//! (interpolated by the contiguous-block rule past the last corpus-confirmed id in their block),
//! and since the corpus never spells them numerically the uncertainty costs nothing today.

use sentinel_models::zone::{zone_map_for, ZoneMap, ZONE_TABLE};

/// Planar XY distance in yards. Zone bounds are 2-D; `z` is the navmesh's problem.
fn yards(a: (f32, f32), b: (f32, f32)) -> f32 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

// ---------------------------------------------------------------------------------------------
// REGRESSION: the nine rows that already shipped must not move.
// ---------------------------------------------------------------------------------------------

/// Every row of `ZONE_TABLE` **as first hand-transcribed**, kept verbatim as the historical
/// record so that a bulk regeneration has to disagree with a literal, not with itself.
///
/// `(ui_map_id, alias, continent, top, left, bottom, right)`. All eleven alias spellings are
/// listed, across the nine distinct rows they name — `Stormwind City`, `Stormwind` and
/// `StormwindClassic` are three keys onto one bound, and all three are load-bearing: the corpus
/// writes `StormwindClassic` 535 times and `Stormwind City` 270 times.
///
/// Two of these 36 bound values are now known to be wrong and are corrected in [`CORRECTED`].
/// They stay here in their original form: the point of this array is to catch movement, and an
/// array that gets quietly rewritten every time the table moves catches nothing.
const SHIPPED_ROWS: &[(u32, &str, u32, f32, f32, f32, f32)] = &[
    (1429, "Elwynn Forest",      0,  -7939.583,   1535.4166, -10254.166,  -1935.4166),
    (1426, "Dun Morogh",         0,  -3877.083,   1802.0833,  -7160.4165, -3122.9165),
    (1432, "Loch Modan",         0,  -4487.5,    -1993.7499,  -6327.083,  -4752.083),
    (1455, "Ironforge",          0,  -4569.2412,  -713.5914,  -5096.8457, -1504.2164),
    (1453, "Stormwind City",     0,  -8278.8506,  1380.9714,  -9175.205,     36.7006),
    (1453, "Stormwind",          0,  -8278.8506,  1380.9714,  -9175.205,     36.7006),
    (1453, "StormwindClassic",   0,  -8278.8506,  1380.9714,  -9175.205,     36.7006),
    (1437, "Wetlands",           0,  -2147.9165,  -389.5833,  -4904.1665, -4525.0),
    (1436, "Westfall",           0,  -9400.0,     3016.6665, -11733.333,   -483.3333),
    (1433, "Redridge Mountains", 0,  -8575.0,    -1570.8333, -10022.916,  -3741.6665),
    (1439, "Darkshore",          1,   8333.333,   2941.6665,   3966.6665, -3608.3333),
];

/// The two bound values that changed when the table was regenerated from the DBC, and the
/// evidence that each is a transcription repair rather than a moved bound.
///
/// `(ui_map_id, field, first-transcribed literal, DBC value, ulps apart, decimal places written)`.
///
/// Keyed on the ui map id, not on an alias: ui map 1453 is reached by three spellings and a
/// correction that applied to only one of them would leave `Stormwind` and `StormwindClassic`
/// asserting a bound the table no longer has.
///
/// Both are the DBC value *printed too short and re-parsed*: `-3877.083251953125` written to three
/// decimals is `-3877.083`, and `36.70063018798828` written to four is `36.7006`. Neither is a
/// second measurement, and no other one of the 36 shipped values is affected — 34 are bit-identical
/// to the DBC. The table now emits the shortest decimal that round-trips through `f32`, so this
/// class of loss cannot recur.
const CORRECTED: &[(u32, &str, f32, f32, u32, usize)] = &[
    (1426, "top",   -3877.083, -3877.0833, 1, 3),  // Dun Morogh
    (1453, "right",    36.7006,   36.70063, 8, 4),  // Stormwind
];

/// Distance in representable `f32` steps. Sign-magnitude bit patterns, so this is only meaningful
/// for two values of the same sign — which is all it is ever asked for here.
fn ulps_apart(a: f32, b: f32) -> u32 {
    assert!(a.signum() == b.signum(), "ulps_apart is only defined within one sign");
    (a.to_bits() as i64 - b.to_bits() as i64).unsigned_abs() as u32
}

/// The reason this file exists first, before any new row is added.
///
/// A regeneration that rounds, swaps an axis, or silently re-derives a bound from a different
/// source moves a zone that was already correct, and nothing else in the tree would notice: the
/// output is still a plausible world coordinate, just in the wrong place. These eleven lookups
/// are the tripwire, and 34 of the 36 values are still pinned to the original hand-written
/// literal. The two that are not are pinned to [`CORRECTED`] instead, which is a stronger claim,
/// not a weaker one: it names them, states how far they moved, and proves the move is inert.
#[test]
fn shipped_rows_keep_their_measured_bounds_exactly() {
    for &(ui_map_id, alias, continent, top, left, bottom, right) in SHIPPED_ROWS {
        let by_name = zone_map_for(alias)
            .unwrap_or_else(|| panic!("alias {alias:?} stopped resolving"));
        let mut want = ZoneMap { continent, top, left, bottom, right };
        // Apply only the corrections declared for this row; everything else must match the
        // original literal exactly.
        for &(c_id, field, was, now, _, _) in CORRECTED {
            if c_id != ui_map_id {
                continue;
            }
            let slot = match field {
                "top" => &mut want.top,
                "left" => &mut want.left,
                "bottom" => &mut want.bottom,
                "right" => &mut want.right,
                other => panic!("{other:?} is not a ZoneMap bound"),
            };
            assert_eq!(
                *slot, was,
                "CORRECTED disagrees with SHIPPED_ROWS for ui map {ui_map_id} ({alias:?}).{field}"
            );
            *slot = now;
        }
        assert_eq!(
            by_name, want,
            "{alias:?} (ui map {ui_map_id}) moved; it was measured, not guessed"
        );
    }
}

/// A correction is only allowed to be a transcription repair.
///
/// Anything that moves a bound far enough to matter physically is a different claim and needs its
/// own landmark evidence, not an entry in a list. Bounding the move at a thousandth of a yard is
/// what makes [`CORRECTED`] safe to have at all: at that scale no lowered coordinate can change
/// which side of anything it lands on.
#[test]
fn the_shipped_corrections_are_transcription_repairs_not_moved_bounds() {
    for &(ui_map_id, field, was, now, ulps, decimals) in CORRECTED {
        assert_eq!(
            ulps_apart(was, now), ulps,
            "ui map {ui_map_id} .{field} is not {ulps} ulps from its old literal"
        );
        assert!(
            (was - now).abs() < 0.001,
            "ui map {ui_map_id} .{field} moved {:.6} yd — too far to be a rounding repair; \
             a real bound change needs a landmark, not a correction entry",
            (was - now).abs()
        );
        // The old literal must be exactly the new value printed short — that is the whole claim,
        // and it is what separates a transcription loss from a disagreement about the bound.
        let printed_short: f32 = format!("{:.*}", decimals, now).parse().unwrap();
        assert_eq!(
            was, printed_short,
            "ui map {ui_map_id} .{field}: {was} is not {now} written to {decimals} decimals, so \
             the difference is a second measurement and not a transcription loss"
        );
    }
}

/// The eleven shipped aliases must survive under their *own* spelling, not merely as names of
/// some row that happens to exist. A rebuild keyed on DBC internal names alone would drop
/// `StormwindClassic` and `Stormwind City` and take 805 `.goto` lines with them.
#[test]
fn every_shipped_alias_spelling_still_resolves() {
    for &(_, alias, ..) in SHIPPED_ROWS {
        assert!(zone_map_for(alias).is_some(), "alias {alias:?} disappeared from the table");
    }
}

/// The axis convention, pinned against the world DB rather than against itself.
///
/// World **X** interpolates along the map's **y** axis and world **Y** along the map's **x**
/// axis — the swap Mangos performs in `DBCStores.cpp::Zone2MapCoordinates` before scaling. Read
/// the other way round the two coordinates are still finite and still inside Azeroth, so only a
/// real spawn can tell the difference.
#[test]
fn to_world_keeps_the_swapped_axis_convention() {
    // `A-1-11-Human.lua` walks to Marshal McBride at the very start of the human guide.
    // creature_template 197 `Marshal McBride`, single spawn, map 0.
    let elwynn = zone_map_for("Elwynn Forest").expect("Elwynn is a shipped row");
    let got = elwynn.to_world(48.923, 41.606);
    assert!(
        yards(got, (-8902.5898, -162.6060)) < 0.5,
        "Elwynn 48.923,41.606 must land on Marshal McBride, got {got:?}"
    );

    // Elwynn cannot prove the convention on its own: its two percentages are seven points apart,
    // so reading them backwards still lands inside the zone. `A-1-11-Draenei.lua:4091` walks to
    // Gelkak Gyromast (creature_template 6667, single spawn, map 1) at Darkshore 56.655,13.485 —
    // a 43-point gap, where the reversed reading is thousands of yards out and cannot be mistaken
    // for rounding.
    let darkshore = zone_map_for("Darkshore").expect("Darkshore is a shipped row");
    let gelkak = (7744.5098, -769.2380);
    assert!(
        yards(darkshore.to_world(56.655, 13.485), gelkak) < 0.5,
        "Darkshore 56.655,13.485 must land on Gelkak Gyromast"
    );
    // The reversed reading, stated explicitly so nobody re-derives it as an improvement.
    let swapped = (
        darkshore.top + (56.655 / 100.0) * (darkshore.bottom - darkshore.top),
        darkshore.left + (13.485 / 100.0) * (darkshore.right - darkshore.left),
    );
    assert!(
        yards(swapped, gelkak) > 1000.0,
        "the swapped reading must be obviously wrong, not subtly wrong; got {swapped:?}"
    );
}


// ---------------------------------------------------------------------------------------------
// COVERAGE: one row per WorldMapArea record, keyed by the id the guides actually spell.
// ---------------------------------------------------------------------------------------------

/// `(ui_map_id, dbc_internal_name, continent)` for all 68 `WorldMapArea.dbc` records.
///
/// `continent` is `map_id`, never `virtual_map_id` — see the module docs. `ui_map_id` is the
/// Classic UiMap identity the guides write in numeric form (`.goto 1426,...`); it is **not** the
/// DBC record id and does not appear in the 2.4.3 client data at all, because the UiMap system
/// postdates it. It is recovered from the corpus: ids form two contiguous blocks in DBC-id order,
/// vanilla based at 1411 and TBC at 1941. Three independent streams agree — 895 raw-world
/// `.goto <uid>/<map>` lines pin 29 of them (display map matched 895/895, and containment
/// settled the field order at 892/895 for `(worldY, worldX)` against 353/895 for `(X, Y)`),
/// numeric-vs-named neighbours agree 12 to 1, and all nine ids already in the shipped table are
/// reproduced. Of the 30 never spelled numerically by the corpus, 19 are bracketed on both sides
/// by confirmed ids and 5 more sit below a base a confirmed id already fixes, leaving six true
/// extrapolations: the four battlegrounds/arena, `Expansion01` and `Sunwell`.
const DBC_ROWS: &[(u32, &str, u32)] = &[
    (1411, "Durotar", 1),
    (1412, "Mulgore", 1),
    (1413, "Barrens", 1),
    (1414, "Kalimdor", 1),
    (1415, "Azeroth", 0),
    (1416, "Alterac", 0),
    (1417, "Arathi", 0),
    (1418, "Badlands", 0),
    (1419, "BlastedLands", 0),
    (1420, "Tirisfal", 0),
    (1421, "Silverpine", 0),
    (1422, "WesternPlaguelands", 0),
    (1423, "EasternPlaguelands", 0),
    (1424, "Hilsbrad", 0),
    (1425, "Hinterlands", 0),
    (1426, "DunMorogh", 0),
    (1427, "SearingGorge", 0),
    (1428, "BurningSteppes", 0),
    (1429, "Elwynn", 0),
    (1430, "DeadwindPass", 0),
    (1431, "Duskwood", 0),
    (1432, "LochModan", 0),
    (1433, "Redridge", 0),
    (1434, "Stranglethorn", 0),
    (1435, "SwampOfSorrows", 0),
    (1436, "Westfall", 0),
    (1437, "Wetlands", 0),
    (1438, "Teldrassil", 1),
    (1439, "Darkshore", 1),
    (1440, "Ashenvale", 1),
    (1441, "ThousandNeedles", 1),
    (1442, "StonetalonMountains", 1),
    (1443, "Desolace", 1),
    (1444, "Feralas", 1),
    (1445, "Dustwallow", 1),
    (1446, "Tanaris", 1),
    (1447, "Aszhara", 1),
    (1448, "Felwood", 1),
    (1449, "UngoroCrater", 1),
    (1450, "Moonglade", 1),
    (1451, "Silithus", 1),
    (1452, "Winterspring", 1),
    (1453, "Stormwind", 0),
    (1454, "Ogrimmar", 1),
    (1455, "Ironforge", 0),
    (1456, "ThunderBluff", 1),
    (1457, "Darnassis", 1),
    (1458, "Undercity", 0),
    (1459, "AlteracValley", 30),
    (1460, "WarsongGulch", 489),
    (1461, "ArathiBasin", 529),
    (1941, "EversongWoods", 530),  // vmap 0 is DISPLAY ONLY; spawns are on 530
    (1942, "Ghostlands", 530),  // vmap 0 is DISPLAY ONLY; spawns are on 530
    (1943, "AzuremystIsle", 530),  // vmap 1 is DISPLAY ONLY; spawns are on 530
    (1944, "Hellfire", 530),
    (1945, "Expansion01", 530),
    (1946, "Zangarmarsh", 530),
    (1947, "TheExodar", 530),  // vmap 1 is DISPLAY ONLY; spawns are on 530
    (1948, "ShadowmoonValley", 530),
    (1949, "BladesEdgeMountains", 530),
    (1950, "BloodmystIsle", 530),  // vmap 1 is DISPLAY ONLY; spawns are on 530
    (1951, "Nagrand", 530),
    (1952, "TerokkarForest", 530),
    (1953, "Netherstorm", 530),
    (1954, "SilvermoonCity", 530),  // vmap 0 is DISPLAY ONLY; spawns are on 530
    (1955, "ShattrathCity", 530),
    (1956, "NetherstormArena", 566),
    (1957, "Sunwell", 530),  // vmap 0 is DISPLAY ONLY; spawns are on 530
];

/// The table must reach every zone the DBC describes, and reach it under its own name.
///
/// The shipped table stopped at nine rows, which is why only 15.0% of the corpus's 38,573
/// coordinate-bearing commands could be lowered at all. With all 68 that figure is 100.0% — the
/// two commands that still fail are a single corpus typo (`.goto 81,...`, a raw DBC id written
/// where a UiMapID belongs; it means 1451, Silithus, and reading it as DBC 81 puts the character
/// 8,613 yd away in Stonetalon), not a hole in the table.
#[test]
fn table_covers_every_worldmaparea_record() {
    let missing: Vec<&str> = DBC_ROWS
        .iter()
        .filter(|(_, name, _)| zone_map_for(name).is_none())
        .map(|(_, name, _)| *name)
        .collect();
    assert!(missing.is_empty(), "zones absent from the table, so uncompilable: {missing:?}");
    assert_eq!(ZONE_TABLE.len(), DBC_ROWS.len(), "one table row per WorldMapArea record");
}

/// Lookup by normalised name and lookup by UiMapID must return the *same* bound.
///
/// The guides use both spellings for the same percentage system, sometimes within twenty lines of
/// each other, and 2,053 `.goto` lines carry the numeric form. Two lookup paths that disagree
/// send the same authored step to two different places depending on which spelling the author
/// happened to use.
#[test]
fn name_lookup_and_ui_map_id_lookup_agree() {
    for &(ui_map_id, name, _) in DBC_ROWS {
        let by_name = zone_map_for(name)
            .unwrap_or_else(|| panic!("{name:?} is not in the table"));
        let by_id = zone_map_for(&ui_map_id.to_string())
            .unwrap_or_else(|| panic!("ui map id {ui_map_id} ({name}) is not in the table"));
        assert_eq!(by_name, by_id, "{name:?} disagrees with its ui map id {ui_map_id}");
    }
}

/// UiMapIDs are identities: two zones sharing one means a numeric `.goto` is ambiguous, and the
/// loser is silently unreachable.
#[test]
fn ui_map_ids_are_unique() {
    let mut seen: Vec<(u32, &str)> = Vec::new();
    for &(ui_map_id, name, _) in DBC_ROWS {
        if let Some((_, other)) = seen.iter().find(|(id, _)| *id == ui_map_id) {
            panic!("ui map id {ui_map_id} claimed by both {other:?} and {name:?}");
        }
        seen.push((ui_map_id, name));
    }
    let ids: Vec<u32> = ZONE_TABLE.iter().map(|(id, _, _)| *id).collect();
    let mut sorted = ids.clone();
    sorted.sort_unstable();
    sorted.dedup();
    assert_eq!(sorted.len(), ids.len(), "ZONE_TABLE contains a duplicate ui map id");
}

/// `virtual_map_id` must never become `continent`.
///
/// This is the one failure in the expansion that produces no error and no wrong-looking number —
/// just a character walking on the wrong continent. Each row below is checked against where the
/// world DB actually puts the zone's creatures, not against the DBC alone.
#[test]
fn display_map_never_becomes_the_continent() {
    // (zone, real map_id, the display map that must NOT win, spawns found inside the zone's own
    //  DBC box on the real map / on the display map)
    const TRAPS: &[(&str, u32, u32, u32, u32)] = &[
        ("Azuremyst Isle",  530, 1, 2325, 0),
        ("Bloodmyst Isle",  530, 1, 1320, 0),
        ("The Exodar",      530, 1,  557, 0),
        ("Eversong Woods",  530, 0, 2284, 0),
        ("Ghostlands",      530, 0, 1661, 0),
        ("Silvermoon City", 530, 0,  636, 0),
        ("Sunwell",         530, 0, 1205, 0),
    ];
    for &(zone, real_map, display_map, spawns_real, spawns_display) in TRAPS {
        let m = zone_map_for(zone).unwrap_or_else(|| panic!("{zone:?} is not in the table"));
        assert_eq!(
            m.continent, real_map,
            "{zone:?} must carry map_id {real_map} ({spawns_real} creature spawns sit inside its \
             own DBC box there, {spawns_display} on display map {display_map}); \
             virtual_map_id is a UI convention and routing on it strands the character"
        );
        assert_ne!(m.continent, display_map, "{zone:?} took virtual_map_id as its continent");
    }
}


// ---------------------------------------------------------------------------------------------
// ROUND-TRIP: every zone the corpus navigates lowers onto a real spawn.
// ---------------------------------------------------------------------------------------------

/// One verified landmark per navigated zone.
struct Landmark {
    /// The zone token exactly as the corpus spells it in field 0 of the `.goto`.
    zone: &'static str,
    ui_map_id: u32,
    /// `map_id`, the map the spawn below is really on.
    continent: u32,
    /// The authored percentage, verbatim.
    pct: (f32, f32),
    /// `creature.position_x`, `creature.position_y` from `tbcmangos.sqlite`.
    spawn: (f32, f32),
    /// Stated per row. Never widen one to make a failure go away — a bound that drifted is a
    /// character walking to the wrong place, and this number is the only thing that says so.
    tol_yd: f32,
    npc: &'static str,
    npc_entry: u32,
    /// Vendored-corpus citation: the `.goto` line itself.
    cite: &'static str,
    /// What the surrounding step does with `npc`, which is why that `.goto` aims at it.
    verb: &'static str,
    /// Measured residual in yards at the time of writing, for context on the tolerance.
    measured_yd: f32,
}

const LANDMARKS: &[Landmark] = &[
    // tol 8 yd: the `.turnin` goto stands at Sen'jin village's edge, not on Master Gadrin.
    Landmark {
        zone: "Durotar", ui_map_id: 1411, continent: 1,
        pct: (56.0, 74.6), spawn: (-825.6360, -4920.7598), tol_yd: 8.0,
        npc: "Master Gadrin", npc_entry: 3188,
        cite: "The Burning Crusade.lua:97215", verb: ".turnin 2935", measured_yd: 5.115,
    },
    Landmark {
        zone: "Mulgore", ui_map_id: 1412, continent: 1,
        pct: (47.64, 58.47), spawn: (-2275.6499, -399.9410), tol_yd: 1.0,
        npc: "Kar Stormsinger", npc_entry: 3690,
        cite: "The Burning Crusade.lua:53930", verb: ".train 132245 Kodo Riding (Kodo riding trainer)", measured_yd: 0.378,
    },
    Landmark {
        zone: "The Barrens", ui_map_id: 1413, continent: 1,
        pct: (62.68, 36.234), spawn: (-835.5630, -3728.6599), tol_yd: 1.0,
        npc: "Gazlowe", npc_entry: 3391,
        cite: "The Burning Crusade.lua:10348", verb: ".turnin 1178", measured_yd: 0.005,
    },
    Landmark {
        zone: "Alterac Mountains", ui_map_id: 1416, continent: 0,
        pct: (80.497, 66.919), spawn: (250.8400, -1470.5800), tol_yd: 1.0,
        npc: "Bath'rah the Windwatcher", npc_entry: 6176,
        cite: "The Burning Crusade.lua:14357", verb: ".turnin 1712", measured_yd: 0.006,
    },
    Landmark {
        zone: "Arathi Highlands", ui_map_id: 1417, continent: 0,
        pct: (60.185, 53.848), spawn: (-1425.6801, -3033.3201), tol_yd: 1.0,
        npc: "Quae", npc_entry: 2712,
        cite: "The Burning Crusade.lua:10665", verb: ".turnin 659", measured_yd: 0.008,
    },
    Landmark {
        zone: "Badlands", ui_map_id: 1418, continent: 0,
        pct: (53.802, 43.301), spawn: (-6607.6602, -3417.4900), tol_yd: 1.0,
        npc: "Sigrun Ironhew", npc_entry: 2860,
        cite: "The Burning Crusade.lua:16236", verb: ".turnin 733", measured_yd: 0.003,
    },
    Landmark {
        zone: "Blasted Lands", ui_map_id: 1419, continent: 0,
        pct: (66.898, 19.469), spawn: (-11001.5000, -3482.7400), tol_yd: 1.0,
        npc: "Thadius Grimshade", npc_entry: 8022,
        cite: "The Burning Crusade.lua:106181", verb: ".turnin 2990", measured_yd: 0.028,
    },
    Landmark {
        zone: "Tirisfal Glades", ui_map_id: 1420, continent: 0,
        pct: (83.218, 71.324), spawn: (1688.8600, -727.0900), tol_yd: 1.0,
        npc: "Mehlar Dawnblade", npc_entry: 17099,
        cite: "The Burning Crusade.lua:95535", verb: ".turnin 9443", measured_yd: 0.011,
    },
    Landmark {
        zone: "Silverpine Forest", ui_map_id: 1421, continent: 0,
        pct: (43.43, 40.85), spawn: (522.4490, 1626.1500), tol_yd: 1.0,
        npc: "High Executor Hadrec", npc_entry: 1952,
        cite: "The Burning Crusade.lua:928", verb: ".accept 1098", measured_yd: 0.468,
    },
    Landmark {
        zone: "Western Plaguelands", ui_map_id: 1422, continent: 0,
        pct: (42.972, 84.501), spawn: (944.2980, -1431.1400), tol_yd: 1.0,
        npc: "High Priestess MacDonnell", npc_entry: 11053,
        cite: "The Burning Crusade.lua:25077", verb: ".turnin 5215", measured_yd: 0.013,
    },
    Landmark {
        zone: "Eastern Plaguelands", ui_map_id: 1423, continent: 0,
        pct: (81.437, 59.82), spawn: (2255.8899, -5337.7202), tol_yd: 1.0,
        npc: "Duke Nicholas Zverenhoff", npc_entry: 11039,
        cite: "The Burning Crusade.lua:5552", verb: ".accept 5251", measured_yd: 0.014,
    },
    Landmark {
        zone: "Hillsbrad Foothills", ui_map_id: 1424, continent: 0,
        pct: (51.468, 58.354), spawn: (-844.8780, -580.2840), tol_yd: 1.0,
        npc: "Raleigh the Devout", npc_entry: 3980,
        cite: "The Burning Crusade.lua:105521", verb: ".turnin 1052", measured_yd: 0.026,
    },
    Landmark {
        zone: "The Hinterlands", ui_map_id: 1425, continent: 0,
        pct: (11.806, 46.755), spawn: (266.6030, -2029.5300), tol_yd: 1.0,
        npc: "Falstad Wildhammer", npc_entry: 5635,
        cite: "The Burning Crusade.lua:20641", verb: ".turnin 1449", measured_yd: 0.019,
    },
    Landmark {
        zone: "Dun Morogh", ui_map_id: 1426, continent: 0,
        pct: (29.927, 71.201), spawn: (-6214.8501, 328.1810), tol_yd: 1.0,
        npc: "Sten Stoutarm", npc_entry: 658,
        cite: "A-1-11-Dwarf-Gnome.lua:22", verb: ".accept 179", measured_yd: 0.003,
    },
    Landmark {
        zone: "Searing Gorge", ui_map_id: 1427, continent: 0,
        pct: (38.582, 27.807), spawn: (-6513.6201, -1183.7800), tol_yd: 1.0,
        npc: "Hansel Heavyhands", npc_entry: 14627,
        cite: "The Burning Crusade.lua:21119", verb: ".accept 7723", measured_yd: 0.009,
    },
    Landmark {
        zone: "Burning Steppes", ui_map_id: 1428, continent: 0,
        pct: (85.82, 68.948), spawn: (-8377.1699, -2780.4800), tol_yd: 1.0,
        npc: "Helendis Riverhorn", npc_entry: 9562,
        cite: "The Burning Crusade.lua:21627", verb: ".accept 4182", measured_yd: 0.003,
    },
    Landmark {
        zone: "Elwynn Forest", ui_map_id: 1429, continent: 0,
        pct: (49.808, 39.489), spawn: (-8853.5898, -193.3360), tol_yd: 1.0,
        npc: "Priestess Anetta", npc_entry: 375,
        cite: "A-1-11-Human.lua:278", verb: ".turnin 3103", measured_yd: 0.001,
    },
    // tol 15 yd: a 2-decimal goto onto Karazhan's front steps; the corpus rounds to 47.0,75.6.
    Landmark {
        zone: "Deadwind Pass", ui_map_id: 1430, continent: 0,
        pct: (47.0, 75.6), spawn: (-11120.2002, -2015.2700), tol_yd: 15.0,
        npc: "Archmage Alturus", npc_entry: 17613,
        cite: "The Burning Crusade.lua:8669", verb: ".accept 9824", measured_yd: 9.483,
    },
    Landmark {
        zone: "Duskwood", ui_map_id: 1431, continent: 0,
        pct: (75.779, 46.159), spawn: (-10547.5000, -1212.6700), tol_yd: 1.0,
        npc: "Watchmaster Sorigal", npc_entry: 5464,
        cite: "The Burning Crusade.lua:18935", verb: ".turnin 1477", measured_yd: 0.041,
    },
    Landmark {
        zone: "Loch Modan", ui_map_id: 1432, continent: 0,
        pct: (37.067, 49.379), spawn: (-5395.8599, -3016.1799), tol_yd: 1.0,
        npc: "Ghak Healtouch", npc_entry: 1470,
        cite: "The Burning Crusade.lua:15442", verb: ".accept 2500", measured_yd: 0.008,
    },
    Landmark {
        zone: "Redridge Mountains", ui_map_id: 1433, continent: 0,
        pct: (30.733, 59.996), spawn: (-9443.6904, -2238.0000), tol_yd: 1.0,
        npc: "Deputy Feldon", npc_entry: 1070,
        cite: "A-1-11-Dwarf-Gnome.lua:3419", verb: ".turnin 244", measured_yd: 0.005,
    },
    Landmark {
        zone: "Stranglethorn Vale", ui_map_id: 1434, continent: 0,
        pct: (26.756, 76.383), spawn: (-14418.2002, 513.4620), tol_yd: 1.0,
        npc: "Privateer Bloads", npc_entry: 2494,
        cite: "The Burning Crusade.lua:16795", verb: ".accept 617", measured_yd: 0.010,
    },
    Landmark {
        zone: "Swamp of Sorrows", ui_map_id: 1435, continent: 0,
        pct: (34.29, 66.14), spawn: (-10632.2998, -3009.3701), tol_yd: 1.0,
        npc: "Fallen Hero of the Horde", npc_entry: 7572,
        cite: "The Burning Crusade.lua:100065", verb: ".accept 2681", measured_yd: 0.105,
    },
    Landmark {
        zone: "Westfall", ui_map_id: 1436, continent: 0,
        pct: (56.327, 47.52), spawn: (-10508.7998, 1045.2300), tol_yd: 1.0,
        npc: "Gryan Stoutmantle", npc_entry: 234,
        cite: "A-1-11-Human.lua:1795", verb: ".turnin 109", measured_yd: 0.008,
    },
    Landmark {
        zone: "Wetlands", ui_map_id: 1437, continent: 0,
        pct: (8.388, 61.752), spawn: (-3849.9600, -736.4440), tol_yd: 1.0,
        npc: "Vincent Hyal", npc_entry: 5082,
        cite: "A-23-30.lua:5268", verb: ".turnin 1301", measured_yd: 0.019,
    },
    Landmark {
        zone: "Teldrassil", ui_map_id: 1438, continent: 1,
        pct: (58.626, 40.287), spawn: (10464.0000, 829.5380), tol_yd: 1.0,
        npc: "Mardant Strongoak", npc_entry: 3597,
        cite: "A-1-11-NightElf.lua:230", verb: ".turnin 3120", measured_yd: 0.011,
    },
    Landmark {
        zone: "Darkshore", ui_map_id: 1439, continent: 1,
        pct: (56.655, 13.485), spawn: (7744.5098, -769.2380), tol_yd: 1.0,
        npc: "Gelkak Gyromast", npc_entry: 6667,
        cite: "A-1-11-Draenei.lua:4091", verb: ".accept 2098", measured_yd: 0.022,
    },
    Landmark {
        zone: "Ashenvale", ui_map_id: 1440, continent: 1,
        pct: (34.894, 49.706), spawn: (2762.2800, -312.2480), tol_yd: 1.0,
        npc: "Vindicator Palanaar", npc_entry: 17106,
        cite: "A-1-11-Draenei.lua:4522", verb: ".turnin 9432", measured_yd: 0.068,
    },
    Landmark {
        zone: "Thousand Needles", ui_map_id: 1441, continent: 1,
        pct: (78.143, 77.12), spawn: (-6228.8599, -3871.6299), tol_yd: 1.0,
        npc: "Wizzle Brassbolts", npc_entry: 4453,
        cite: "The Burning Crusade.lua:2267", verb: ".accept 2770", measured_yd: 0.008,
    },
    Landmark {
        zone: "Stonetalon Mountains", ui_map_id: 1442, continent: 1,
        pct: (47.36, 64.25), spawn: (824.6350, 933.2710), tol_yd: 1.0,
        npc: "Tsunaman", npc_entry: 11862,
        cite: "The Burning Crusade.lua:1001", verb: ".accept 6562", measured_yd: 0.214,
    },
    Landmark {
        zone: "Desolace", ui_map_id: 1443, continent: 1,
        pct: (66.519, 7.907), spawn: (215.0700, 1242.7800), tol_yd: 1.0,
        npc: "Brother Anton", npc_entry: 1182,
        cite: "The Burning Crusade.lua:105490", verb: ".accept 261", measured_yd: 0.044,
    },
    Landmark {
        zone: "Feralas", ui_map_id: 1444, continent: 1,
        pct: (30.632, 42.706), spawn: (-4345.3799, 3312.7500), tol_yd: 1.0,
        npc: "Pratt McGrubben", npc_entry: 7852,
        cite: "The Burning Crusade.lua:124213", verb: ".accept 2821", measured_yd: 0.008,
    },
    Landmark {
        zone: "Dustwallow Marsh", ui_map_id: 1445, continent: 1,
        pct: (66.336, 45.469), spawn: (-3624.7500, -4457.6299), tol_yd: 1.0,
        npc: "Morgan Stern", npc_entry: 4794,
        cite: "The Burning Crusade.lua:11467", verb: ".accept 1204", measured_yd: 0.010,
    },
    Landmark {
        zone: "Tanaris", ui_map_id: 1446, continent: 1,
        pct: (50.887, 26.963), spawn: (-7115.2998, -3729.9299), tol_yd: 1.0,
        npc: "Alchemist Pestlezugg", npc_entry: 5594,
        cite: "The Burning Crusade.lua:20155", verb: ".turnin 110", measured_yd: 0.023,
    },
    Landmark {
        zone: "Azshara", ui_map_id: 1447, continent: 1,
        pct: (11.368, 78.166), spawn: (2698.6699, -3853.5400), tol_yd: 1.0,
        npc: "Loh'atu", npc_entry: 11548,
        cite: "The Burning Crusade.lua:128533", verb: ".accept 5535", measured_yd: 0.010,
    },
    Landmark {
        zone: "Felwood", ui_map_id: 1448, continent: 1,
        pct: (38.499, 50.414), spawn: (5200.7900, -572.0240), tol_yd: 1.0,
        npc: "Remains of Trey Lightforge", npc_entry: 11020,
        cite: "The Burning Crusade.lua:24456", verb: ".turnin 5204", measured_yd: 0.007,
    },
    Landmark {
        zone: "Un'Goro Crater", ui_map_id: 1449, continent: 1,
        pct: (46.378, 13.444), spawn: (-6298.2900, -1182.6500), tol_yd: 1.0,
        npc: "Karna Remtravel", npc_entry: 9618,
        cite: "The Burning Crusade.lua:23372", verb: ".accept 4243", measured_yd: 0.006,
    },
    Landmark {
        zone: "Moonglade", ui_map_id: 1450, continent: 1,
        pct: (56.209, 30.636), spawn: (8020.0000, -2678.7400), tol_yd: 1.0,
        npc: "Dendrite Starblaze", npc_entry: 11802,
        cite: "A-23-30.lua:1516", verb: ".turnin 272", measured_yd: 0.001,
    },
    Landmark {
        zone: "Silithus", ui_map_id: 1451, continent: 1,
        pct: (49.196, 34.184), spawn: (-6752.3799, 823.8360), tol_yd: 1.0,
        npc: "Commander Mar'alith", npc_entry: 15181,
        cite: "The Burning Crusade.lua:26482", verb: ".accept 8304", measured_yd: 0.020,
    },
    Landmark {
        zone: "Winterspring", ui_map_id: 1452, continent: 1,
        pct: (31.269, 45.164), spawn: (6395.5698, -2536.7500), tol_yd: 1.0,
        npc: "Donova Snowden", npc_entry: 9298,
        cite: "The Burning Crusade.lua:23706", verb: ".turnin 980", measured_yd: 0.016,
    },
    Landmark {
        zone: "StormwindClassic", ui_map_id: 1453, continent: 0,
        pct: (78.105, 17.75), spawn: (-8437.9600, 331.0330), tol_yd: 1.0,
        npc: "Lady Katrana Prestor", npc_entry: 1749,
        cite: "A-23-30.lua:2678", verb: ".turnin 396", measured_yd: 0.008,
    },
    Landmark {
        zone: "Orgrimmar", ui_map_id: 1454, continent: 1,
        pct: (38.66, 35.92), spawn: (1937.8400, -4222.8398), tol_yd: 1.0,
        npc: "Sagorne Creststrider", npc_entry: 13417,
        cite: "The Burning Crusade.lua:5052", verb: ".accept 7667", measured_yd: 0.036,
    },
    Landmark {
        zone: "Ironforge", ui_map_id: 1455, continent: 0,
        pct: (51.521, 26.311), spawn: (-4708.0601, -1120.9301), tol_yd: 1.0,
        npc: "Golnir Bouldertoe", npc_entry: 4256,
        cite: "A-1-11-Dwarf-Gnome.lua:2504", verb: ".turnin 6391", measured_yd: 0.001,
    },
    Landmark {
        zone: "Thunder Bluff", ui_map_id: 1456, continent: 1,
        pct: (46.61, 33.17), spawn: (-1080.8101, 30.1093), tol_yd: 1.0,
        npc: "Bena Winterhoof", npc_entry: 3009,
        cite: "The Burning Crusade.lua:2065", verb: ".turnin 2440", measured_yd: 0.066,
    },
    Landmark {
        zone: "Darnassus", ui_map_id: 1457, continent: 1,
        pct: (38.334, 80.951), spawn: (9667.0195, 2532.6599), tol_yd: 1.0,
        npc: "Astarii Starseeker", npc_entry: 4090,
        cite: "The Burning Crusade.lua:22314", verb: ".turnin 3378", measured_yd: 0.002,
    },
    Landmark {
        zone: "Undercity", ui_map_id: 1458, continent: 0,
        pct: (69.79, 43.16), spawn: (1601.6899, 203.6220), tol_yd: 1.0,
        npc: "Royal Overseer Bauhaus", npc_entry: 10781,
        cite: "The Burning Crusade.lua:63550", verb: ".turnin 5023", measured_yd: 0.027,
    },
    Landmark {
        zone: "Eversong Woods", ui_map_id: 1941, continent: 530,
        pct: (61.38, 53.98), spawn: (9269.2305, -7510.4902), tol_yd: 1.0,
        npc: "Perascamin", npc_entry: 16280,
        cite: "The Burning Crusade.lua:47933", verb: ".target Perascamin (.train 33388, Riding Trainer)", measured_yd: 0.096,
    },
    // tol 10 yd: flight-master approach point, not the NPC's own tile.
    Landmark {
        zone: "Ghostlands", ui_map_id: 1942, continent: 530,
        pct: (45.6, 30.6), spawn: (7595.1602, -6782.2402), tol_yd: 10.0,
        npc: "Skymaster Sunwing", npc_entry: 16189,
        cite: "The Burning Crusade.lua:93431", verb: ".fp Tranquillien (Dragonhawk Master)", measured_yd: 6.131,
    },
    Landmark {
        zone: "Azuremyst Isle", ui_map_id: 1943, continent: 530,
        pct: (48.391, 51.771), spawn: (-4199.1099, -12469.9004), tol_yd: 1.0,
        npc: "Anchorite Fateema", npc_entry: 17214,
        cite: "A-1-11-Draenei.lua:514", verb: ".accept 9463", measured_yd: 0.018,
    },
    Landmark {
        zone: "Hellfire Peninsula", ui_map_id: 1944, continent: 530,
        pct: (54.29, 63.58), spawn: (-708.2970, 2735.7400), tol_yd: 1.0,
        npc: "Father Malgor Devidicus", npc_entry: 16825,
        cite: "The Burning Crusade.lua:27936", verb: ".turnin 10058", measured_yd: 0.014,
    },
    Landmark {
        zone: "Zangarmarsh", ui_map_id: 1946, continent: 530,
        pct: (41.215, 28.673), spawn: (974.2530, 7403.0898), tol_yd: 1.0,
        npc: "Timothy Daniels", npc_entry: 18019,
        cite: "The Burning Crusade.lua:8857", verb: ".accept 9794", measured_yd: 0.021,
    },
    Landmark {
        zone: "The Exodar", ui_map_id: 1947, continent: 530,
        pct: (38.367, 82.564), spawn: (-4191.5098, -11471.7998), tol_yd: 1.0,
        npc: "Jol", npc_entry: 17509,
        cite: "A-1-11-Draenei.lua:1832", verb: ".accept 9598", measured_yd: 0.020,
    },
    Landmark {
        zone: "Shadowmoon Valley", ui_map_id: 1948, continent: 530,
        pct: (38.786, 54.212), spawn: (-3935.7100, 2091.7800), tol_yd: 1.0,
        npc: "Gryphonrider Kieran", npc_entry: 22042,
        cite: "The Burning Crusade.lua:42036", verb: ".accept 10569", measured_yd: 0.023,
    },
    Landmark {
        zone: "Blade's Edge Mountains", ui_map_id: 1949, continent: 530,
        pct: (61.979, 39.476), spawn: (2980.5801, 5483.4302), tol_yd: 1.0,
        npc: "Tree Warden Chawn", npc_entry: 22007,
        cite: "The Burning Crusade.lua:37961", verb: ".turnin 10748", measured_yd: 0.057,
    },
    Landmark {
        zone: "Bloodmyst Isle", ui_map_id: 1950, continent: 530,
        pct: (53.245, 57.741), spawn: (-2014.2200, -11812.0996), tol_yd: 1.0,
        npc: "Morae", npc_entry: 17434,
        cite: "A-1-11-Draenei.lua:1621", verb: ".accept 9629", measured_yd: 0.027,
    },
    Landmark {
        zone: "Nagrand", ui_map_id: 1951, continent: 530,
        pct: (60.655, 22.654), spawn: (-792.7670, 6944.6401), tol_yd: 1.0,
        npc: "Elementalist Untrag", npc_entry: 18071,
        cite: "The Burning Crusade.lua:33744", verb: ".accept 9818", measured_yd: 0.012,
    },
    Landmark {
        zone: "Terokkar Forest", ui_map_id: 1952, continent: 530,
        pct: (57.502, 55.775), spawn: (-3007.8999, 3978.2200), tol_yd: 1.0,
        npc: "Lieutenant Gravelhammer", npc_entry: 18713,
        cite: "The Burning Crusade.lua:31662", verb: ".accept 10038", measured_yd: 0.005,
    },
    Landmark {
        zone: "Netherstorm", ui_map_id: 1953, continent: 530,
        pct: (66.39, 67.3), spawn: (2954.9099, 1782.1200), tol_yd: 1.0,
        npc: "Sab'aoth", npc_entry: 22479,
        cite: "The Burning Crusade.lua:40086", verb: ".accept 10924", measured_yd: 0.037,
    },
    // tol 15 yd: one shared goto serves four consecutive vendor turn-ins.
    Landmark {
        zone: "Silvermoon City", ui_map_id: 1954, continent: 530,
        pct: (56.6, 53.6), spawn: (9730.4600, -7086.0098), tol_yd: 15.0,
        npc: "Sorim Lightsong", npc_entry: 20612,
        cite: "The Burning Crusade.lua:92782", verb: ".turnin 10359", measured_yd: 9.190,
    },
    Landmark {
        zone: "Shattrath City", ui_map_id: 1955, continent: 530,
        pct: (50.24, 45.36), spawn: (-1868.9500, 5478.9702), tol_yd: 1.0,
        npc: "Spymistress Mehlisah Highcrown", npc_entry: 18893,
        cite: "The Burning Crusade.lua:6941", verb: ".turnin 10091", measured_yd: 0.032,
    },
];

/// The expansion's whole claim, checked one zone at a time: a percentage the guides really wrote
/// lands on the NPC the guides really mean.
///
/// Each row is an independent check of a bound nobody hand-verified — the corpus supplies the
/// percentage, `tbcmangos.sqlite` supplies the position, and neither knows about the DBC.
#[test]
fn every_navigated_zone_lowers_onto_its_landmark() {
    let mut failures: Vec<String> = Vec::new();
    for lm in LANDMARKS {
        let Some(map) = zone_map_for(lm.zone) else {
            failures.push(format!(
                "{}: not in the zone table, so `{}` cannot be lowered at all \
                 (corpus {}, aiming at {} #{})",
                lm.zone, lm.zone, lm.cite, lm.npc, lm.npc_entry
            ));
            continue;
        };
        if map.continent != lm.continent {
            failures.push(format!(
                "{}: continent {} but {} #{} spawns on map {} ({})",
                lm.zone, map.continent, lm.npc, lm.npc_entry, lm.continent, lm.cite
            ));
        }
        let got = map.to_world(lm.pct.0, lm.pct.1);
        let off = yards(got, lm.spawn);
        if off > lm.tol_yd {
            failures.push(format!(
                "{}: {:?} lowered to {:?}, {:.1} yd from {} #{} at {:?} \
                 (tolerance {:.1} yd, measured {:.3} yd; {} — {})",
                lm.zone, lm.pct, got, off, lm.npc, lm.npc_entry, lm.spawn,
                lm.tol_yd, lm.measured_yd, lm.cite, lm.verb
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} landmarks failed:\n  {}",
        failures.len(), LANDMARKS.len(), failures.join("\n  ")
    );
}

/// Every landmark reaches the same bound through its numeric spelling.
#[test]
fn landmarks_resolve_identically_through_their_ui_map_id() {
    for lm in LANDMARKS {
        let by_name = zone_map_for(lm.zone)
            .unwrap_or_else(|| panic!("{:?} is not in the table ({})", lm.zone, lm.cite));
        let by_id = zone_map_for(&lm.ui_map_id.to_string())
            .unwrap_or_else(|| panic!("ui map id {} ({}) is not in the table", lm.ui_map_id, lm.zone));
        assert_eq!(by_name, by_id, "{:?} and ui map id {} disagree", lm.zone, lm.ui_map_id);
    }
}


// ---------------------------------------------------------------------------------------------
// CLOSURE: what the table must keep refusing.
// ---------------------------------------------------------------------------------------------

/// An unknown zone yields no position, and this must survive the expansion.
///
/// `None` is the diagnostic: `project_builder.rs` turns it into `UNMAPPED_GOTO_ZONE` and
/// `route.rs` into `LoweringError::UnknownZone`. Guessing instead once produced 522 travel
/// actions aimed at meaningless coordinates — ADR 06 invariant 3, a percentage must never
/// survive compilation.
#[test]
fn an_unknown_zone_yields_no_position() {
    for zone in [
        "Northrend",            // a real zone, but not in 2.4.3 client data
        "Icecrown",             // ditto
        "Deeprun Tram",         // a subzone, never a WorldMapArea row
        "Gadgetzan",            // AreaTable 976; `.subzone` payloads are AreaTable ids, not UiMapIDs
        "",
        "   ",
    ] {
        assert!(
            zone_map_for(zone).is_none(),
            "{zone:?} resolved to a position; an unknown zone must produce a diagnostic, not a guess"
        );
    }
}

/// A UiMapID that names nothing must not resolve either — including the ones the block rule
/// leaves as gaps.
#[test]
fn an_unknown_ui_map_id_yields_no_position() {
    for id in ["0", "1", "1410", "1462", "1940", "1958", "4294967295"] {
        assert!(zone_map_for(id).is_none(), "ui map id {id} resolved but names no zone");
    }
    // The corpus's own bad line: `.goto 81,53.21,32.48` writes DBC id 81 where a UiMapID belongs.
    // Read as a UiMapID it is nothing; the step means 1451 (Silithus). Resolving 81 to
    // StonetalonMountains — whose *DBC* id is 81 — lands 8,613 yd from the NPC the step names.
    assert!(
        zone_map_for("81").is_none(),
        "`81` is a DBC record id, not a UiMapID; resolving it silently relocates the step"
    );
}

/// The alias table is closed. A spelling nobody listed is an error, never a nearest match.
///
/// A fuzzy or prefix match that binds the wrong zone does not fail — it sends the character to
/// another continent and the symptom is a long walk. These pairs are the ones a substring or
/// edit-distance matcher gets wrong, and each is a real name in the DBC.
#[test]
fn the_alias_table_is_closed_against_fuzzy_matches() {
    // (spelling, the row it must NOT be confused with, the continent that confusion would give)
    const COLLISIONS: &[(&str, &str, u32, u32)] = &[
        // `Alterac` is a Hillsbrad-adjacent zone on map 0; `AlteracValley` is a battleground on
        // map 30. Prefix-matching one onto the other is a cross-map error.
        ("AlteracValley", "Alterac", 30, 0),
        ("Alterac", "AlteracValley", 0, 30),
        // `Arathi` (map 0) against `ArathiBasin` (map 529).
        ("ArathiBasin", "Arathi", 529, 0),
        ("Arathi", "ArathiBasin", 0, 529),
        // `Netherstorm` (map 530) against `NetherstormArena` (map 566).
        ("NetherstormArena", "Netherstorm", 566, 530),
        ("Netherstorm", "NetherstormArena", 530, 566),
    ];
    for &(spelling, confusable, want, wrong) in COLLISIONS {
        let m = zone_map_for(spelling)
            .unwrap_or_else(|| panic!("{spelling:?} is a real DBC row and must resolve"));
        assert_eq!(
            m.continent, want,
            "{spelling:?} resolved onto {confusable:?}'s continent {wrong} instead of {want}"
        );
    }

    // Near-miss spellings. `Stranglethon Vale` is a real corpus typo (one use, in a `.zone` tag,
    // never as a `.goto` field 0) — a fuzzy matcher would bind it and nobody would ever learn the
    // guide has a typo.
    for typo in [
        "Stranglethon Vale",
        "Elwyn Forest",
        "Nagrandd",
        "Dun Morogth",
        "Zangarmash",
    ] {
        assert!(
            zone_map_for(typo).is_none(),
            "{typo:?} matched a zone; an unlisted spelling must be an error, not the nearest row"
        );
    }
}

/// Blizzard's own misspellings are aliases, not normalisation targets.
///
/// The DBC internal names carry typos the corpus does not repeat — `Hilsbrad` (one L),
/// `Aszhara` (transposed), `Ogrimmar` (no R), `Darnassis` (final S), and `Expansion01` for
/// Outland. Both spellings must resolve, and to the same row: normalising case and punctuation
/// alone cannot bridge these, so each needs an explicit alias.
#[test]
fn blizzard_internal_typos_and_display_names_resolve_to_one_row() {
    const PAIRS: &[(&str, &str)] = &[
        ("Hillsbrad Foothills", "Hilsbrad"),
        ("Azshara", "Aszhara"),
        ("Orgrimmar", "Ogrimmar"),
        ("Darnassus", "Darnassis"),
        ("Eastern Kingdoms", "Azeroth"),
        ("Stranglethorn Vale", "Stranglethorn"),
        ("Hellfire Peninsula", "Hellfire"),
        ("Dustwallow Marsh", "Dustwallow"),
        ("The Barrens", "Barrens"),
        ("The Hinterlands", "Hinterlands"),
        ("Tirisfal Glades", "Tirisfal"),
        ("Silverpine Forest", "Silverpine"),
        ("Redridge Mountains", "Redridge"),
        ("Alterac Mountains", "Alterac"),
        ("Elwynn Forest", "Elwynn"),
        ("Un'Goro Crater", "UngoroCrater"),
        ("Blade's Edge Mountains", "BladesEdgeMountains"),
    ];
    for &(display, internal) in PAIRS {
        let a = zone_map_for(display)
            .unwrap_or_else(|| panic!("corpus spelling {display:?} does not resolve"));
        let b = zone_map_for(internal)
            .unwrap_or_else(|| panic!("DBC internal name {internal:?} does not resolve"));
        assert_eq!(a, b, "{display:?} and {internal:?} are the same zone but gave different bounds");
    }
}

/// The raw-world form must never reach the percentage lookup.
///
/// `.goto 1439/1,x,y` is already in the server's frame; its second field is the *display* map, so
/// treating the whole token as a zone key would be wrong twice over. 895 corpus lines use it.
#[test]
fn the_raw_world_form_is_not_a_zone_key() {
    for token in ["1439/1", "1947/1", "1944/530", "1415/0"] {
        assert!(
            zone_map_for(token).is_none(),
            "{token:?} is the raw-world form and must not resolve as a percentage zone"
        );
    }
}

