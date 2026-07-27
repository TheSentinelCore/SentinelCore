//! The spawn→zone index: which creature and gameobject entries are spawned in which zone.
//!
//! `creature` carries map + position and no zone, and `creature_zone` has zero rows in this
//! snapshot, so `GET /zone/{id}/spawns` cannot be answered from SQL. It is answered from
//! `sentinel/kernel/catalogs/spawn_zones.json`, which `sentinel/tools/regen_zone_catalog.py`
//! derives from the client's own terrain the way mangos does at runtime — grid tile, area bit,
//! `AreaTable` parent — for all 109,352 creature and 72,385 gameobject spawns.
//!
//! The catalog is `include_str!`'d for the same reason [`crate::zone_names`] is: the derivation
//! needs 381 MB of terrain tiles, the QueryServer must not open them per request, and there is no
//! working directory the server can rely on.
//!
//! **Entries and counts, not GUIDs.** Both endpoints that read this aggregate per entry
//! immediately, so a 109k-row GUID→zone map would be committed data with no reader. Positions
//! come from `creature`/`gameobject` at query time — `GET /spawns/{type}/{entry}` per entry, and
//! `GET /spawns/nearby` per radius, both of which do have position columns to filter on.

use serde::Deserialize;
use std::collections::HashMap;
use std::sync::OnceLock;

const SPAWN_ZONES_JSON: &str = include_str!("../../sentinel/kernel/catalogs/spawn_zones.json");

/// `zone id → entry → spawn count`, for one spawn table. Keys arrive as strings because JSON
/// object keys are strings; they are parsed once, here, rather than at every lookup.
pub type ZoneIndex = HashMap<u32, HashMap<u32, u32>>;

#[derive(Debug, Deserialize)]
struct RawIndex {
    creatures: HashMap<String, HashMap<String, u32>>,
    objects: HashMap<String, HashMap<String, u32>>,
}

pub struct SpawnZones {
    pub creatures: ZoneIndex,
    pub objects: ZoneIndex,
}

impl SpawnZones {
    /// Whether any spawn table places anything in this zone. Distinct from "there is no such
    /// zone", which [`crate::zone_names::zone_exists`] answers — an empty but real zone is a 200
    /// with empty arrays, not a 404.
    pub fn has_zone(&self, zone: u32) -> bool {
        self.creatures.contains_key(&zone) || self.objects.contains_key(&zone)
    }
}

fn parse_section(raw: HashMap<String, HashMap<String, u32>>) -> ZoneIndex {
    raw.into_iter()
        .filter_map(|(zone, entries)| {
            let zone: u32 = zone.parse().ok()?;
            let entries = entries
                .into_iter()
                .filter_map(|(entry, count)| Some((entry.parse::<u32>().ok()?, count)))
                .collect();
            Some((zone, entries))
        })
        .collect()
}

/// The parsed index, built once. A malformed catalog panics: it is a committed generated
/// artifact, so a parse failure means the tree is broken, not that the request was.
pub fn index() -> &'static SpawnZones {
    static INDEX: OnceLock<SpawnZones> = OnceLock::new();
    INDEX.get_or_init(|| {
        let raw: RawIndex = serde_json::from_str(SPAWN_ZONES_JSON).expect(
            "sentinel/kernel/catalogs/spawn_zones.json is malformed — regenerate the catalog",
        );
        SpawnZones {
            creatures: parse_section(raw.creatures),
            objects: parse_section(raw.objects),
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zone_names::zone_exists;

    #[test]
    fn every_indexed_zone_is_a_zone_the_catalog_can_name() {
        // An index keyed by an id zones.json does not carry would make /zone/{id}/spawns answer
        // with spawns for a zone it must 404 — the two catalogs come out of one generator run and
        // this is where a hand-patched one shows up.
        for zone in index().creatures.keys().chain(index().objects.keys()) {
            assert!(zone_exists(*zone), "zone {zone} is indexed but unnamed");
        }
    }

    #[test]
    fn elwynn_forest_carries_the_creatures_it_should() {
        let elwynn = index().creatures.get(&12).expect("Elwynn Forest has spawns");
        // Hogger (448) is the canonical Elwynn elite; 299 Defias Smuggler the canonical trash.
        // Named entries rather than a total, so the assertion survives a snapshot refresh.
        assert!(elwynn.get(&448).copied().unwrap_or(0) > 0, "Hogger lives in Elwynn");
        assert!(elwynn.get(&299).copied().unwrap_or(0) > 0, "Defias Smugglers do too");
        assert!(index().has_zone(12));
        assert!(!index().has_zone(99_999_999));
    }

    #[test]
    fn the_index_accounts_for_essentially_every_spawn() {
        // 8% unresolved was the symptom of the generator missing the instance-map fallback
        // (instances ship no terrain tiles at all). Anything past a rounding error means the
        // derivation regressed and whole zones are silently empty.
        let indexed: u32 = index()
            .creatures
            .values()
            .flat_map(|entries| entries.values())
            .sum();
        assert!(
            indexed >= 109_000,
            "only {indexed} creature spawns are indexed of 109,352"
        );
    }
}
