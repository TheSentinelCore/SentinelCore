//! The measured zone→world coordinate transform.
//!
//! RestedXP authors most coordinates as **zone-relative percentages** (`.goto Darkshore,40.77,78.56`,
//! both axes in `0..100`). Nothing downstream can use those: the navmesh, the server and both
//! artifact models speak world coordinates. The conversion needs a per-zone bounds table, and there
//! is exactly one such table in this repository — it lives here because two independent lowerings
//! need it and a second copy could drift from the first:
//!
//! * `sentinel-importer` (`project_builder::build_travel_position`) → the ADR-05 `Position`.
//! * `sentinel-compiler` (`kernel::parse_movement`) → the ADR-07 [`kernel::Point`](crate::kernel::Point).
//!
//! A zone absent from the table produces **no position and no guess** — ADR 06 invariant 3: a
//! percentage must never survive compilation. Emitting the raw percentages once produced 522 travel
//! actions aimed at meaningless coordinates. Coverage is therefore a hard ceiling on how much of the
//! guide corpus can compile at all, which is why the table carries every zone the client knows
//! rather than only the ones someone got round to transcribing.
//!
//! # This table is generated. Do not hand-edit it.
//!
//! [`ZONE_TABLE`] is emitted by `SentinelQuesting/tools/gen_zone_table.py` and checked in as source.
//! The DBC it reads lives under `Emulators/` and is deliberately **not** a build input — nothing in
//! the build graph opens it, and regenerating is a manual, auditable act:
//!
//! ```text
//! python3 SentinelQuesting/tools/gen_zone_table.py     # rewrites this file's ZONE_TABLE
//! cargo test -p sentinel-models --test zone_table      # re-proves it against the world DB
//! ```
//!
//! ## Where the numbers come from
//!
//! `Emulators/Mangos - Classic TBC/extracted/dbc/WorldMapArea.dbc` — a `WDBC` file of 68 records ×
//! 9 fields × 36 bytes, plus a 778-byte string block. It is read through the Mangos
//! `WorldMapAreaEntry` layout (`src/game/Server/DBCStructure.h`) and its `"xinxffffi"` format string
//! (`DBCfmt.h`): `[0] id [1] map_id [2] area_id [3] internal_name [4] locLeft [5] locRight
//! [6] locTop [7] locBottom [8] virtual_map_id`. The four bounds are stored as raw int32 bit
//! patterns and must be reinterpreted as `f32`, never cast.
//!
//! This is the same file the previous nine hand-written rows came from: 34 of their 36 bound values
//! are bit-identical to it. The other two were transcription casualties, not a second measurement —
//! `DunMorogh.top` had been written `-3877.083`, which is the DBC value printed at 7 significant
//! digits and lands 1 ULP low, and `Stormwind.right` had been written `36.7006`, the same value at
//! 6 digits and 8 ULP low. Both are now emitted at full round-trip precision, moving them 0.00024 yd
//! and 0.00003 yd respectively. Every value here is the shortest decimal that round-trips through
//! `f32`, so re-running the generator is a no-op and any real diff is a real change.
//!
//! ## `continent` is `map_id`, never `virtual_map_id`
//!
//! Seven records carry `virtual_map_id != -1`. That field is a **UI display** convention — where the
//! client draws the zone on the world map — and it is not the map the character stands on.
//! `TheExodar`, `AzuremystIsle` and `BloodmystIsle` display on map 1 while every one of their
//! creature spawns is on 530; `EversongWoods`, `Ghostlands`, `SilvermoonCity` and `Sunwell` display
//! on map 0, likewise all on 530. The corpus writes the *display* map in its raw-world form
//! (`.goto 1947/1,…` for The Exodar), so a regeneration that reaches for the nearest available map
//! field loads Kalimdor for Azuremyst and Eastern Kingdoms for Eversong. Nothing errors — the
//! character simply walks, on the wrong continent, forever. The rows below are annotated where the
//! trap exists, and `tests/zone_table.rs` checks each against where the world DB actually puts that
//! zone's creatures.
//!
//! ## UI map ids are recovered, not read
//!
//! Field 0 of a `.goto` is sometimes a bare number (`.goto 1426,…`, 2,053 corpus lines). Those are
//! Classic **UiMapIDs**, which postdate 2.4.3 and appear nowhere in the client data — the DBC record
//! id for Dun Morogh is 1, its `AreaTable` id is 1, and the guides write 1426. They are recovered by
//! the rule that they form two contiguous blocks in DBC-id order, vanilla based at **1411** and TBC
//! at **1941**; the generator asserts this reproduces all nine ids that were already known before
//! it will emit anything. Six ids are never spelled numerically by the corpus and so rest on the
//! block rule alone: the four battlegrounds/arena, `Expansion01` and `Sunwell`.
//!
//! A UiMapID is a **lookup key only** and must never reach a compiled coordinate — what lands in the
//! artifact is [`ZoneMap::continent`].

/// A zone's linear bounds plus the continent the resulting coordinate belongs to.
///
/// [`continent`](Self::continent) is the id the navmesh and the server use — Eastern Kingdoms `0`,
/// Kalimdor `1`, Outland `530`, and a handful of battleground maps — and it is what lands in the
/// artifact. It is the DBC's `map_id`; see the module docs for why `virtual_map_id` must never be
/// substituted for it.
///
/// Axis convention (Mangos `DBCStores.cpp::Zone2MapCoordinates`, verified against world-DB spawns):
/// world **X** interpolates along the map's **y** axis, world **Y** along the map's **x** axis. The
/// two are not interchangeable — under the reversed reading two adjacent Darkshore steps lower
/// 6,911 yd apart instead of 385.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ZoneMap {
    /// Continent/map id the navmesh and server use. The DBC's `map_id`.
    pub continent: u32,
    /// world X at map y = 0 (`locTop`)
    pub top: f32,
    /// world Y at map x = 0 (`locLeft`)
    pub left: f32,
    /// world X at map y = 1 (`locBottom`)
    pub bottom: f32,
    /// world Y at map x = 1 (`locRight`)
    pub right: f32,
}

impl ZoneMap {
    /// Convert zone-relative percentages (`0..100`) to world `(x, y)`.
    pub fn to_world(&self, pct_x: f32, pct_y: f32) -> (f32, f32) {
        let mx = pct_x / 100.0;
        let my = pct_y / 100.0;
        (
            self.top + my * (self.bottom - self.top),
            self.left + mx * (self.right - self.left),
        )
    }
}

/// Zone table: `(ui_map_id, aliases, bounds)` — one row per `WorldMapArea.dbc` record.
///
/// The first alias is always the DBC internal name. Any further alias is a spelling
/// [`normalized_eq`] cannot bridge, and every one of them is a token the guide corpus actually
/// writes: Blizzard's own misspellings (`Hilsbrad`, `Aszhara`, `Ogrimmar`, `Darnassis`), display
/// names that carry an article or a region word the internal name drops (`The Barrens`,
/// `Stranglethorn Vale`, `Hellfire Peninsula`), and RestedXP's two spellings of the Stormwind city
/// map. Nothing here is a nearest match — see `tests/zone_table.rs`, which pins the pairs a prefix
/// or edit-distance matcher gets wrong (`Alterac` vs `AlteracValley`, `Netherstorm` vs
/// `NetherstormArena`) and the corpus typos that must stay unresolved.
///
/// GENERATED by `SentinelQuesting/tools/gen_zone_table.py` from
/// `Emulators/Mangos - Classic TBC/extracted/dbc/WorldMapArea.dbc`. Edit the generator, not this.
pub const ZONE_TABLE: &[(u32, &[&str], ZoneMap)] = &[
    // Durotar  (WorldMapArea id 4, area 14)
    (1411, &["Durotar"],
     ZoneMap { continent: 1, top: 1808.3333, left: -1962.4999, bottom: -1716.6666, right: -7249.9995 }),
    // Mulgore  (WorldMapArea id 9, area 215)
    (1412, &["Mulgore"],
     ZoneMap { continent: 1, top: -272.91666, left: 2047.9166, bottom: -3697.9165, right: -3089.5833 }),
    // Barrens  (WorldMapArea id 11, area 17)
    (1413, &["Barrens", "The Barrens"],
     ZoneMap { continent: 1, top: 1612.4999, left: 2622.9165, bottom: -5143.75, right: -7510.4165 }),
    // Kalimdor  (WorldMapArea id 13, area 0)
    (1414, &["Kalimdor"],
     ZoneMap { continent: 1, top: 12799.9, left: 17066.6, bottom: -11733.3, right: -19733.21 }),
    // Azeroth  (WorldMapArea id 14, area 0)
    (1415, &["Azeroth", "Eastern Kingdoms"],
     ZoneMap { continent: 0, top: 11176.344, left: 18171.97, bottom: -15973.344, right: -22569.21 }),
    // Alterac  (WorldMapArea id 15, area 36)
    (1416, &["Alterac", "Alterac Mountains"],
     ZoneMap { continent: 0, top: 1500.0, left: 783.3333, bottom: -366.66666, right: -2016.6666 }),
    // Arathi  (WorldMapArea id 16, area 45)
    (1417, &["Arathi", "Arathi Highlands"],
     ZoneMap { continent: 0, top: -133.33333, left: -866.6666, bottom: -2533.3333, right: -4466.6665 }),
    // Badlands  (WorldMapArea id 17, area 3)
    (1418, &["Badlands"],
     ZoneMap { continent: 0, top: -5889.583, left: -2079.1665, bottom: -7547.9165, right: -4566.6665 }),
    // BlastedLands  (WorldMapArea id 19, area 4)
    (1419, &["BlastedLands"],
     ZoneMap { continent: 0, top: -10566.666, left: -1241.6666, bottom: -12800.0, right: -4591.6665 }),
    // Tirisfal  (WorldMapArea id 20, area 85)
    (1420, &["Tirisfal", "Tirisfal Glades"],
     ZoneMap { continent: 0, top: 3837.4998, left: 3033.3333, bottom: 824.99994, right: -1485.4166 }),
    // Silverpine  (WorldMapArea id 21, area 130)
    (1421, &["Silverpine", "Silverpine Forest"],
     ZoneMap { continent: 0, top: 1666.6666, left: 3449.9998, bottom: -1133.3333, right: -750.0 }),
    // WesternPlaguelands  (WorldMapArea id 22, area 28)
    (1422, &["WesternPlaguelands"],
     ZoneMap { continent: 0, top: 3366.6665, left: 416.66666, bottom: 499.99997, right: -3883.3333 }),
    // EasternPlaguelands  (WorldMapArea id 23, area 139)
    (1423, &["EasternPlaguelands"],
     ZoneMap { continent: 0, top: 3799.9998, left: -2185.4165, bottom: 1218.75, right: -6056.25 }),
    // Hilsbrad  (WorldMapArea id 24, area 267)
    (1424, &["Hilsbrad", "Hillsbrad Foothills"],
     ZoneMap { continent: 0, top: 400.0, left: 1066.6666, bottom: -1733.3333, right: -2133.3333 }),
    // Hinterlands  (WorldMapArea id 26, area 47)
    (1425, &["Hinterlands", "The Hinterlands"],
     ZoneMap { continent: 0, top: 1466.6666, left: -1575.0, bottom: -1100.0, right: -5425.0 }),
    // DunMorogh  (WorldMapArea id 27, area 1)
    (1426, &["DunMorogh"],
     ZoneMap { continent: 0, top: -3877.0833, left: 1802.0833, bottom: -7160.4165, right: -3122.9165 }),
    // SearingGorge  (WorldMapArea id 28, area 51)
    (1427, &["SearingGorge"],
     ZoneMap { continent: 0, top: -6100.0, left: -322.91666, bottom: -7587.4995, right: -2554.1665 }),
    // BurningSteppes  (WorldMapArea id 29, area 46)
    (1428, &["BurningSteppes"],
     ZoneMap { continent: 0, top: -7031.2495, left: -266.66666, bottom: -8983.333, right: -3195.8333 }),
    // Elwynn  (WorldMapArea id 30, area 12)
    (1429, &["Elwynn", "Elwynn Forest"],
     ZoneMap { continent: 0, top: -7939.583, left: 1535.4166, bottom: -10254.166, right: -1935.4166 }),
    // DeadwindPass  (WorldMapArea id 32, area 41)
    (1430, &["DeadwindPass"],
     ZoneMap { continent: 0, top: -9866.666, left: -833.3333, bottom: -11533.333, right: -3333.3333 }),
    // Duskwood  (WorldMapArea id 34, area 10)
    (1431, &["Duskwood"],
     ZoneMap { continent: 0, top: -9716.666, left: 833.3333, bottom: -11516.666, right: -1866.6666 }),
    // LochModan  (WorldMapArea id 35, area 38)
    (1432, &["LochModan"],
     ZoneMap { continent: 0, top: -4487.5, left: -1993.7499, bottom: -6327.083, right: -4752.083 }),
    // Redridge  (WorldMapArea id 36, area 44)
    (1433, &["Redridge", "Redridge Mountains"],
     ZoneMap { continent: 0, top: -8575.0, left: -1570.8333, bottom: -10022.916, right: -3741.6665 }),
    // Stranglethorn  (WorldMapArea id 37, area 33)
    (1434, &["Stranglethorn", "Stranglethorn Vale"],
     ZoneMap { continent: 0, top: -11168.75, left: 2220.8333, bottom: -15422.916, right: -4160.4165 }),
    // SwampOfSorrows  (WorldMapArea id 38, area 8)
    (1435, &["SwampOfSorrows"],
     ZoneMap { continent: 0, top: -9620.833, left: -2222.9165, bottom: -11150.0, right: -4516.6665 }),
    // Westfall  (WorldMapArea id 39, area 40)
    (1436, &["Westfall"],
     ZoneMap { continent: 0, top: -9400.0, left: 3016.6665, bottom: -11733.333, right: -483.3333 }),
    // Wetlands  (WorldMapArea id 40, area 11)
    (1437, &["Wetlands"],
     ZoneMap { continent: 0, top: -2147.9165, left: -389.5833, bottom: -4904.1665, right: -4525.0 }),
    // Teldrassil  (WorldMapArea id 41, area 141)
    (1438, &["Teldrassil"],
     ZoneMap { continent: 1, top: 11831.25, left: 3814.5833, bottom: 8437.5, right: -1277.0833 }),
    // Darkshore  (WorldMapArea id 42, area 148)
    (1439, &["Darkshore"],
     ZoneMap { continent: 1, top: 8333.333, left: 2941.6665, bottom: 3966.6665, right: -3608.3333 }),
    // Ashenvale  (WorldMapArea id 43, area 331)
    (1440, &["Ashenvale"],
     ZoneMap { continent: 1, top: 4672.9165, left: 1699.9999, bottom: 829.1666, right: -4066.6665 }),
    // ThousandNeedles  (WorldMapArea id 61, area 400)
    (1441, &["ThousandNeedles"],
     ZoneMap { continent: 1, top: -3966.6665, left: -433.3333, bottom: -6899.9995, right: -4833.333 }),
    // StonetalonMountains  (WorldMapArea id 81, area 406)
    (1442, &["StonetalonMountains"],
     ZoneMap { continent: 1, top: 2916.6665, left: 3245.8333, bottom: -339.5833, right: -1637.4999 }),
    // Desolace  (WorldMapArea id 101, area 405)
    (1443, &["Desolace"],
     ZoneMap { continent: 1, top: 452.0833, left: 4233.333, bottom: -2545.8333, right: -262.5 }),
    // Feralas  (WorldMapArea id 121, area 357)
    (1444, &["Feralas"],
     ZoneMap { continent: 1, top: -2366.6665, left: 5441.6665, bottom: -6999.9995, right: -1508.3333 }),
    // Dustwallow  (WorldMapArea id 141, area 15)
    (1445, &["Dustwallow", "Dustwallow Marsh"],
     ZoneMap { continent: 1, top: -2033.3333, left: -974.99994, bottom: -5533.333, right: -6225.0 }),
    // Tanaris  (WorldMapArea id 161, area 440)
    (1446, &["Tanaris"],
     ZoneMap { continent: 1, top: -5875.0, left: -218.74998, bottom: -10475.0, right: -7118.7495 }),
    // Aszhara  (WorldMapArea id 181, area 16)
    (1447, &["Aszhara", "Azshara"],
     ZoneMap { continent: 1, top: 5341.6665, left: -3277.0833, bottom: 1960.4166, right: -8347.916 }),
    // Felwood  (WorldMapArea id 182, area 361)
    (1448, &["Felwood"],
     ZoneMap { continent: 1, top: 7133.333, left: 1641.6666, bottom: 3299.9998, right: -4108.333 }),
    // UngoroCrater  (WorldMapArea id 201, area 490)
    (1449, &["UngoroCrater"],
     ZoneMap { continent: 1, top: -5966.6665, left: 533.3333, bottom: -8433.333, right: -3166.6665 }),
    // Moonglade  (WorldMapArea id 241, area 493)
    (1450, &["Moonglade"],
     ZoneMap { continent: 1, top: 8491.666, left: -1381.25, bottom: 6952.083, right: -3689.5833 }),
    // Silithus  (WorldMapArea id 261, area 1377)
    (1451, &["Silithus"],
     ZoneMap { continent: 1, top: -5958.334, left: 2537.5, bottom: -8281.25, right: -945.834 }),
    // Winterspring  (WorldMapArea id 281, area 618)
    (1452, &["Winterspring"],
     ZoneMap { continent: 1, top: 8533.333, left: -316.66666, bottom: 3799.9998, right: -7416.6665 }),
    // Stormwind  (WorldMapArea id 301, area 1519)
    (1453, &["Stormwind", "Stormwind City", "StormwindClassic"],
     ZoneMap { continent: 0, top: -8278.851, left: 1380.9714, bottom: -9175.205, right: 36.70063 }),
    // Ogrimmar  (WorldMapArea id 321, area 1637)
    (1454, &["Ogrimmar", "Orgrimmar"],
     ZoneMap { continent: 1, top: 2273.8772, left: -3680.601, bottom: 1338.4606, right: -5083.2056 }),
    // Ironforge  (WorldMapArea id 341, area 1537)
    (1455, &["Ironforge"],
     ZoneMap { continent: 0, top: -4569.241, left: -713.5914, bottom: -5096.8457, right: -1504.2164 }),
    // ThunderBluff  (WorldMapArea id 362, area 1638)
    (1456, &["ThunderBluff"],
     ZoneMap { continent: 1, top: -849.99994, left: 516.6666, bottom: -1545.8333, right: -527.0833 }),
    // Darnassis  (WorldMapArea id 381, area 1657)
    (1457, &["Darnassis", "Darnassus"],
     ZoneMap { continent: 1, top: 10238.316, left: 2938.3628, bottom: 9532.587, right: 1880.0295 }),
    // Undercity  (WorldMapArea id 382, area 1497)
    (1458, &["Undercity"],
     ZoneMap { continent: 0, top: 1877.9453, left: 873.1926, bottom: 1237.8412, right: -86.1824 }),
    // AlteracValley  (WorldMapArea id 401, area 2597)
    (1459, &["AlteracValley"],
     ZoneMap { continent: 30, top: 1085.4166, left: 1781.2499, bottom: -1739.5833, right: -2456.25 }),
    // WarsongGulch  (WorldMapArea id 443, area 3277)
    (1460, &["WarsongGulch"],
     ZoneMap { continent: 489, top: 1627.0833, left: 2041.6666, bottom: 862.49994, right: 895.8333 }),
    // ArathiBasin  (WorldMapArea id 461, area 3358)
    (1461, &["ArathiBasin"],
     ZoneMap { continent: 529, top: 1508.3333, left: 1858.3333, bottom: 337.5, right: 102.08333 }),
    // EversongWoods  (WorldMapArea id 462, area 3430) -- virtual_map_id 0 is DISPLAY ONLY; continent stays 530
    (1941, &["EversongWoods"],
     ZoneMap { continent: 530, top: 11041.666, left: -4487.5, bottom: 7758.333, right: -9412.5 }),
    // Ghostlands  (WorldMapArea id 463, area 3433) -- virtual_map_id 0 is DISPLAY ONLY; continent stays 530
    (1942, &["Ghostlands"],
     ZoneMap { continent: 530, top: 8266.666, left: -5283.333, bottom: 6066.6665, right: -8583.333 }),
    // AzuremystIsle  (WorldMapArea id 464, area 3524) -- virtual_map_id 1 is DISPLAY ONLY; continent stays 530
    (1943, &["AzuremystIsle"],
     ZoneMap { continent: 530, top: -2793.75, left: -10500.0, bottom: -5508.333, right: -14570.833 }),
    // Hellfire  (WorldMapArea id 465, area 3483)
    (1944, &["Hellfire", "Hellfire Peninsula"],
     ZoneMap { continent: 530, top: 1481.25, left: 5539.583, bottom: -1962.4999, right: 375.0 }),
    // Expansion01  (WorldMapArea id 466, area 0)
    (1945, &["Expansion01"],
     ZoneMap { continent: 530, top: 5821.3594, left: 12996.039, bottom: -5821.3594, right: -4468.039 }),
    // Zangarmarsh  (WorldMapArea id 467, area 3521)
    (1946, &["Zangarmarsh"],
     ZoneMap { continent: 530, top: 1935.4166, left: 9475.0, bottom: -1416.6666, right: 4447.9165 }),
    // TheExodar  (WorldMapArea id 471, area 3557) -- virtual_map_id 1 is DISPLAY ONLY; continent stays 530
    (1947, &["TheExodar"],
     ZoneMap { continent: 530, top: -3609.6833, left: -11066.367, bottom: -4314.371, right: -12123.138 }),
    // ShadowmoonValley  (WorldMapArea id 473, area 3520)
    (1948, &["ShadowmoonValley"],
     ZoneMap { continent: 530, top: -1947.9166, left: 4225.0, bottom: -5614.583, right: -1275.0 }),
    // BladesEdgeMountains  (WorldMapArea id 475, area 3522)
    (1949, &["BladesEdgeMountains"],
     ZoneMap { continent: 530, top: 4408.333, left: 8845.833, bottom: 791.6666, right: 3420.8333 }),
    // BloodmystIsle  (WorldMapArea id 476, area 3525) -- virtual_map_id 1 is DISPLAY ONLY; continent stays 530
    (1950, &["BloodmystIsle"],
     ZoneMap { continent: 530, top: -758.3333, left: -10075.0, bottom: -2933.3333, right: -13337.499 }),
    // Nagrand  (WorldMapArea id 477, area 3518)
    (1951, &["Nagrand"],
     ZoneMap { continent: 530, top: 41.666664, left: 10295.833, bottom: -3641.6665, right: 4770.833 }),
    // TerokkarForest  (WorldMapArea id 478, area 3519)
    (1952, &["TerokkarForest"],
     ZoneMap { continent: 530, top: -999.99994, left: 7083.333, bottom: -4600.0, right: 1683.3333 }),
    // Netherstorm  (WorldMapArea id 479, area 3523)
    (1953, &["Netherstorm"],
     ZoneMap { continent: 530, top: 5456.25, left: 5483.333, bottom: 1739.5833, right: -91.666664 }),
    // SilvermoonCity  (WorldMapArea id 480, area 3487) -- virtual_map_id 0 is DISPLAY ONLY; continent stays 530
    (1954, &["SilvermoonCity"],
     ZoneMap { continent: 530, top: 10153.709, left: -6400.75, bottom: 9346.938, right: -7612.2085 }),
    // ShattrathCity  (WorldMapArea id 481, area 3703)
    (1955, &["ShattrathCity"],
     ZoneMap { continent: 530, top: -1473.9545, left: 6135.259, bottom: -2344.7878, right: 4829.009 }),
    // NetherstormArena  (WorldMapArea id 482, area 3820)
    (1956, &["NetherstormArena"],
     ZoneMap { continent: 566, top: 2918.75, left: 2660.4165, bottom: 1404.1666, right: 389.5833 }),
    // Sunwell  (WorldMapArea id 499, area 4080) -- virtual_map_id 0 is DISPLAY ONLY; continent stays 530
    (1957, &["Sunwell"],
     ZoneMap { continent: 530, top: 13568.749, left: -5302.083, bottom: 11350.0, right: -8629.166 }),
];

/// Compare two zone spellings ignoring ASCII case and every non-alphanumeric character.
///
/// This is canonicalisation, not fuzzy matching: it bridges `Un'Goro Crater` → `UngoroCrater` and
/// `Dun Morogh` → `DunMorogh`, and nothing else. It has no notion of distance, prefix or
/// similarity, so `Zangarmash` still fails to find `Zangarmarsh` and `Alterac` can never reach
/// `AlteracValley`. Anything normalisation cannot reach needs an explicit alias in [`ZONE_TABLE`],
/// because a wrong binding is not an error — it is a character walking to another continent.
fn normalized_eq(a: &str, b: &str) -> bool {
    /// The significant bytes of a spelling, lazily. Non-ASCII bytes are never alphanumeric, so a
    /// typographic apostrophe drops out the same way a plain one does.
    fn key(s: &str) -> impl Iterator<Item = u8> + '_ {
        s.bytes().filter(u8::is_ascii_alphanumeric).map(|c| c.to_ascii_lowercase())
    }
    key(a).eq(key(b))
}

/// Look up a zone by name or by a bare UI map id — guides use both spellings for the same
/// percentage system (`.goto Elwynn Forest,…` and `.goto 1429,…`).
///
/// This resolves the *percentage* form only. A field 0 carrying a `/` (`1439/1`) is the raw-world
/// form and must never reach this function: its coordinates are already in the server's frame. It
/// is refused here anyway, since it parses as neither a number nor a name.
///
/// Returns `None` for anything unlisted, and `None` is the diagnostic — `project_builder` turns it
/// into `UNMAPPED_GOTO_ZONE` and `kernel::route` into `LoweringError::UnknownZone`.
pub fn zone_map_for(zone: &str) -> Option<ZoneMap> {
    let zone = zone.trim();
    if let Ok(ui_map_id) = zone.parse::<u32>() {
        return ZONE_TABLE.iter().find(|(id, _, _)| *id == ui_map_id).map(|(_, _, m)| *m);
    }
    // A spelling with no alphanumeric content normalises to nothing and would otherwise match any
    // equally-empty alias. There are none, but the guard keeps that an invariant of this function
    // rather than of the table.
    if !zone.bytes().any(|c| c.is_ascii_alphanumeric()) {
        return None;
    }
    ZONE_TABLE
        .iter()
        .find(|(_, names, _)| names.iter().any(|n| normalized_eq(n, zone)))
        .map(|(_, _, m)| *m)
}
