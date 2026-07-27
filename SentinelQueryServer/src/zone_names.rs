//! Zone-id → display-name map for `quest_template.ZoneOrSort`.
//!
//! `ZoneOrSort` is an overloaded column. A **positive** value is an `AreaTable` area id and names
//! the zone the quest belongs to; a **non-positive** value is a *sort* bucket (class, profession,
//! seasonal event) with no area behind it. `zone_name` therefore returns `""` for anything `<= 0`
//! rather than guessing — `QuestSummary.zone` carries that empty string straight to the panel.
//!
//! # This table is generated. Do not hand-edit it.
//!
//! Rows are the 139 distinct positive `ZoneOrSort` values in this snapshot's `quest_template`,
//! resolved against `Emulators/Mangos - Classic TBC/extracted/dbc/AreaTable.dbc` — a `WDBC` file
//! read through the mangos `AreaTableEntryfmt` layout (`src/game/Server/DBCfmt.h`:
//! `"iiinixxxxxissssssssssssssssxiiiiixx"`), taking field 0 as the area id and field 11 as the
//! enUS name from the string block. Every one of the 139 resolved; there is no fallback row.
//!
//! The DBC is deliberately not a build input — nothing in the build graph opens it, exactly as
//! `sentinel_models::zone::ZONE_TABLE` treats `WorldMapArea.dbc`. `sentinel/tools/regen_zone_catalog.py`
//! subsumes this extraction when the Lua-side zone catalog lands.
//!
//! Two ids can share a name (`4095`/`4131` are both "Magisters' Terrace" — the outdoor area and
//! the instance); that is the client's own data, not a de-duplication bug.

/// `(area_id, enUS name)`, sorted ascending by id so lookup can binary-search.
const ZONE_NAMES: &[(u32, &str)] = &[
    (1, "Dun Morogh"),
    (3, "Badlands"),
    (4, "Blasted Lands"),
    (8, "Swamp of Sorrows"),
    (9, "Northshire Valley"),
    (10, "Duskwood"),
    (11, "Wetlands"),
    (12, "Elwynn Forest"),
    (14, "Durotar"),
    (15, "Dustwallow Marsh"),
    (16, "Azshara"),
    (17, "The Barrens"),
    (19, "Zul'Gurub"),
    (24, "Northshire Abbey"),
    (25, "Blackrock Mountain"),
    (28, "Western Plaguelands"),
    (33, "Stranglethorn Vale"),
    (35, "Booty Bay"),
    (36, "Alterac Mountains"),
    (38, "Loch Modan"),
    (40, "Westfall"),
    (41, "Deadwind Pass"),
    (44, "Redridge Mountains"),
    (45, "Arathi Highlands"),
    (46, "Burning Steppes"),
    (47, "The Hinterlands"),
    (51, "Searing Gorge"),
    (85, "Tirisfal Glades"),
    (130, "Silverpine Forest"),
    (132, "Coldridge Valley"),
    (133, "Gnomeregan"),
    (139, "Eastern Plaguelands"),
    (141, "Teldrassil"),
    (148, "Darkshore"),
    (151, "Designer Island"),
    (154, "Deathknell"),
    (188, "Shadowglen"),
    (209, "Shadowfang Keep"),
    (215, "Mulgore"),
    (220, "Red Cloud Mesa"),
    (221, "Camp Narache"),
    (236, "Shadowfang Keep"),
    (267, "Hillsbrad Foothills"),
    (279, "Dalaran"),
    (331, "Ashenvale"),
    (357, "Feralas"),
    (361, "Felwood"),
    (363, "Valley of Trials"),
    (400, "Thousand Needles"),
    (405, "Desolace"),
    (406, "Stonetalon Mountains"),
    (440, "Tanaris"),
    (490, "Un'Goro Crater"),
    (493, "Moonglade"),
    (618, "Winterspring"),
    (702, "Rut'theran Village"),
    (717, "The Stockade"),
    (718, "Wailing Caverns"),
    (719, "Blackfathom Deeps"),
    (722, "Razorfen Downs"),
    (796, "Scarlet Monastery"),
    (978, "Zul'Farrak"),
    (1116, "Feathermoon Stronghold"),
    (1377, "Silithus"),
    (1417, "Sunken Temple"),
    (1497, "Undercity"),
    (1517, "Uldaman"),
    (1519, "Stormwind City"),
    (1537, "Ironforge"),
    (1581, "The Deadmines"),
    (1583, "Blackrock Spire"),
    (1584, "Blackrock Depths"),
    (1637, "Orgrimmar"),
    (1638, "Thunder Bluff"),
    (1657, "Darnassus"),
    (1717, "Razorfen Kraul"),
    (1769, "Timbermaw Hold"),
    (1941, "Caverns of Time"),
    (1977, "Zul'Gurub"),
    (2017, "Stratholme"),
    (2057, "Scholomance"),
    (2079, "Alcaz Island"),
    (2100, "Maraudon"),
    (2159, "Onyxia's Lair"),
    (2257, "Deeprun Tram"),
    (2300, "Caverns of Time"),
    (2367, "Old Hillsbrad Foothills"),
    (2437, "Ragefire Chasm"),
    (2557, "Dire Maul"),
    (2562, "Karazhan"),
    (2597, "Alterac Valley"),
    (2677, "Blackwing Lair"),
    (2717, "Molten Core"),
    (2839, "Alterac Valley"),
    (3277, "Warsong Gulch"),
    (3358, "Arathi Basin"),
    (3428, "Ahn'Qiraj"),
    (3429, "Ruins of Ahn'Qiraj"),
    (3430, "Eversong Woods"),
    (3431, "Sunstrider Isle"),
    (3433, "Ghostlands"),
    (3456, "Naxxramas"),
    (3483, "Hellfire Peninsula"),
    (3487, "Silvermoon City"),
    (3518, "Nagrand"),
    (3519, "Terokkar Forest"),
    (3520, "Shadowmoon Valley"),
    (3521, "Zangarmarsh"),
    (3522, "Blade's Edge Mountains"),
    (3523, "Netherstorm"),
    (3524, "Azuremyst Isle"),
    (3525, "Bloodmyst Isle"),
    (3526, "Ammen Vale"),
    (3535, "Hellfire Citadel"),
    (3545, "Hellfire Citadel"),
    (3557, "The Exodar"),
    (3606, "Hyjal Summit"),
    (3607, "Serpentshrine Cavern"),
    (3679, "Skettis"),
    (3688, "Auchindoun"),
    (3696, "The Barrier Hills"),
    (3703, "Shattrath City"),
    (3715, "The Steamvault"),
    (3716, "The Underbog"),
    (3717, "The Slave Pens"),
    (3789, "Shadow Labyrinth"),
    (3790, "Auchenai Crypts"),
    (3792, "Mana-Tombs"),
    (3805, "Zul'Aman"),
    (3820, "Eye of the Storm"),
    (3836, "Magtheridon's Lair"),
    (3840, "The Black Temple"),
    (3842, "Tempest Keep"),
    (3845, "Tempest Keep"),
    (3905, "Coilfang Reservoir"),
    (3917, "Auchindoun"),
    (4080, "Isle of Quel'Danas"),
    (4095, "Magisters' Terrace"),
    (4131, "Magisters' Terrace"),
];

/// Resolve a raw `quest_template.ZoneOrSort` to a zone name.
///
/// Returns `""` for sort buckets (`<= 0`) and for area ids absent from the table, so callers never
/// have to distinguish "no zone" from "unknown zone" — neither is renderable.
pub fn zone_name(zone_or_sort: i64) -> &'static str {
    if zone_or_sort <= 0 {
        return "";
    }
    let key = zone_or_sort as u32;
    match ZONE_NAMES.binary_search_by_key(&key, |(id, _)| *id) {
        Ok(i) => ZONE_NAMES[i].1,
        Err(_) => "",
    }
}

#[cfg(test)]
mod tests {
    use super::{zone_name, ZONE_NAMES};

    #[test]
    fn table_is_sorted_so_binary_search_is_valid() {
        assert!(ZONE_NAMES.windows(2).all(|w| w[0].0 < w[1].0));
        assert!(ZONE_NAMES.iter().all(|(_, n)| !n.is_empty()));
    }

    #[test]
    fn known_zones_resolve() {
        assert_eq!(zone_name(12), "Elwynn Forest");
        assert_eq!(zone_name(3483), "Hellfire Peninsula");
        assert_eq!(zone_name(1), "Dun Morogh");
    }

    #[test]
    fn sort_buckets_and_unknown_ids_resolve_to_empty() {
        // Negative ZoneOrSort is a class/profession/seasonal sort bucket, not an area.
        assert_eq!(zone_name(-22), "");
        assert_eq!(zone_name(0), "");
        assert_eq!(zone_name(999_999), "");
    }
}
