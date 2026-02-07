//! Zone boundary database
//!
//! Maps UiMapID (used by GatherMate2 Era/TBC) to world coordinate boundaries.
//!
//! # Coordinate System
//!
//! GatherMate2 stores coordinates as packed integers in XXXXYYYY00 format.
//! After decoding, we get normalized map coordinates (0.0-1.0).
//!
//! These must be converted to WoW world coordinates using zone boundaries:
//! - world_x = loc_top + (loc_bottom - loc_top) * map_x
//! - world_y = loc_left + (loc_right - loc_left) * map_y
//!
//! Note: In WoW coordinate system:
//! - X = North-South (increasing = North)
//! - Y = West-East (increasing = West)
//! - Z = Height

use serde::{Deserialize, Serialize};

/// Game version for profile compatibility
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
pub enum GameVersion {
    /// Classic Anniversary (1.15.x)
    #[default]
    Era,
    /// The Burning Crusade Classic
    Tbc,
}

impl GameVersion {
    pub fn as_str(&self) -> &'static str {
        match self {
            GameVersion::Era => "Classic Era",
            GameVersion::Tbc => "The Burning Crusade",
        }
    }
}

/// A rectangular area within a zone to exclude from route generation
/// (e.g., cities embedded within outdoor zones)
#[derive(Debug, Clone)]
pub struct ExclusionZone {
    pub name: &'static str,
    /// World coordinate boundaries (X = North-South, Y = West-East)
    pub x_min: f32,
    pub x_max: f32,
    pub y_min: f32,
    pub y_max: f32,
}

impl ExclusionZone {
    /// Check if a world coordinate falls within this exclusion zone
    pub fn contains(&self, world_x: f32, world_y: f32) -> bool {
        world_x >= self.x_min && world_x <= self.x_max
            && world_y >= self.y_min && world_y <= self.y_max
    }
}

/// Zone boundary information for coordinate conversion
#[derive(Debug, Clone)]
pub struct ZoneBounds {
    /// Modern UiMapID (used by GatherMate2 Era/TBC)
    pub ui_map_id: u32,
    /// Zone display name
    pub name: &'static str,
    /// Parent continent: 0 = Eastern Kingdoms, 1 = Kalimdor, 530 = Outland
    pub continent_id: u32,
    /// Navigation map ID for GatherBuddy (same as continent_id for ground zones)
    pub map_id: u32,
    /// World coordinate: Top (North) boundary - X axis
    pub loc_top: f32,
    /// World coordinate: Bottom (South) boundary - X axis
    pub loc_bottom: f32,
    /// World coordinate: Left (West) boundary - Y axis
    pub loc_left: f32,
    /// World coordinate: Right (East) boundary - Y axis
    pub loc_right: f32,
    /// Default ground height for the zone
    pub default_z: f32,
    /// Game version this zone belongs to
    pub game_version: GameVersion,
    /// Areas within this zone to exclude (e.g., cities)
    pub exclusion_zones: &'static [ExclusionZone],
}

impl ZoneBounds {
    /// Convert normalized map coordinates (0.0-1.0) to world coordinates
    pub fn to_world_coords(&self, map_x: f32, map_y: f32) -> (f32, f32, f32) {
        // map_x goes from 0 (top/north) to 1 (bottom/south)
        // map_y goes from 0 (left/west) to 1 (right/east)
        let world_x = self.loc_top + (self.loc_bottom - self.loc_top) * map_x;
        let world_y = self.loc_left + (self.loc_right - self.loc_left) * map_y;
        (world_x, world_y, self.default_z)
    }

    /// Get zone width in yards
    pub fn width(&self) -> f32 {
        (self.loc_right - self.loc_left).abs()
    }

    /// Get zone height in yards
    pub fn height(&self) -> f32 {
        (self.loc_bottom - self.loc_top).abs()
    }
}

/// Static zone database
///
/// Maps UiMapID to zone boundaries extracted from WoW client data.
/// Source: WorldMapArea.dbc converted to UiMapID system
///
/// Zone boundaries are in WoW world coordinates:
/// - loc_top/loc_bottom = X boundaries (North-South)
/// - loc_left/loc_right = Y boundaries (West-East)
pub static ZONE_DATABASE: &[ZoneBounds] = &[
    // ============================================
    // Eastern Kingdoms (Continent ID: 0)
    // ============================================
    ZoneBounds {
        ui_map_id: 1416,
        name: "Alterac Mountains",
        continent_id: 0,
        map_id: 0,
        loc_top: 633.33,
        loc_bottom: -1700.00,
        loc_left: 500.00,
        loc_right: -2000.00,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1417,
        name: "Arathi Highlands",
        continent_id: 0,
        map_id: 0,
        loc_top: -575.00,
        loc_bottom: -3075.00,
        loc_left: -925.00,
        loc_right: -3425.00,
        default_z: 40.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1418,
        name: "Badlands",
        continent_id: 0,
        map_id: 0,
        loc_top: -3450.00,
        loc_bottom: -5116.67,
        loc_left: -4458.33,
        loc_right: -6125.00,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1419,
        name: "Blasted Lands",
        continent_id: 0,
        map_id: 0,
        loc_top: -10275.00,
        loc_bottom: -11775.00,
        loc_left: -10833.33,
        loc_right: -12333.33,
        default_z: 10.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1420,
        name: "Tirisfal Glades",
        continent_id: 0,
        map_id: 0,
        loc_top: 2866.67,
        loc_bottom: 666.67,
        loc_left: 1600.00,
        loc_right: -400.00,
        default_z: 50.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1421,
        name: "Silverpine Forest",
        continent_id: 0,
        map_id: 0,
        loc_top: 1400.00,
        loc_bottom: -266.67,
        loc_left: 2100.00,
        loc_right: 433.33,
        default_z: 40.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1422,
        name: "Western Plaguelands",
        continent_id: 0,
        map_id: 0,
        loc_top: 2466.67,
        loc_bottom: 800.00,
        loc_left: -1500.00,
        loc_right: -3166.67,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1423,
        name: "Eastern Plaguelands",
        continent_id: 0,
        map_id: 0,
        loc_top: 2400.00,
        loc_bottom: 566.67,
        loc_left: -2933.33,
        loc_right: -4766.67,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1424,
        name: "Hillsbrad Foothills",
        continent_id: 0,
        map_id: 0,
        loc_top: 1066.67,
        loc_bottom: -1733.33,
        loc_left: 400.00,
        loc_right: -2133.33,
        default_z: 30.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1425,
        name: "The Hinterlands",
        continent_id: 0,
        map_id: 0,
        loc_top: 200.00,
        loc_bottom: -1466.67,
        loc_left: -2600.00,
        loc_right: -4266.67,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1426,
        name: "Dun Morogh",
        continent_id: 0,
        map_id: 0,
        loc_top: -3877.08,
        loc_bottom: -7160.42,
        loc_left: 1802.08,
        loc_right: -3122.92,
        default_z: 500.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1427,
        name: "Searing Gorge",
        continent_id: 0,
        map_id: 0,
        loc_top: -5875.00,
        loc_bottom: -6958.33,
        loc_left: -6425.00,
        loc_right: -7508.33,
        default_z: 250.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1428,
        name: "Burning Steppes",
        continent_id: 0,
        map_id: 0,
        loc_top: -6683.33,
        loc_bottom: -8266.67,
        loc_left: -7016.67,
        loc_right: -8600.00,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1429,
        name: "Elwynn Forest",
        continent_id: 0,
        map_id: 0,
        loc_top: -7939.58,
        loc_bottom: -10254.17,
        loc_left: -1935.42,
        loc_right: 1535.42,
        default_z: 50.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1430,
        name: "Deadwind Pass",
        continent_id: 0,
        map_id: 0,
        loc_top: -9800.00,
        loc_bottom: -11133.33,
        loc_left: -9633.33,
        loc_right: -10966.67,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1431,
        name: "Duskwood",
        continent_id: 0,
        map_id: 0,
        loc_top: -9700.00,
        loc_bottom: -11533.33,
        loc_left: -200.00,
        loc_right: -2033.33,
        default_z: 40.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1432,
        name: "Loch Modan",
        continent_id: 0,
        map_id: 0,
        loc_top: -3277.08,
        loc_bottom: -5427.08,
        loc_left: -2860.42,
        loc_right: -5010.42,
        default_z: 200.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1433,
        name: "Redridge Mountains",
        continent_id: 0,
        map_id: 0,
        loc_top: -8600.00,
        loc_bottom: -10100.00,
        loc_left: -1966.67,
        loc_right: -3466.67,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1434,
        name: "Stranglethorn Vale",
        continent_id: 0,
        map_id: 0,
        loc_top: -11272.92,
        loc_bottom: -14860.42,
        loc_left: -1962.50,
        loc_right: -5550.00,
        default_z: 10.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1435,
        name: "Swamp of Sorrows",
        continent_id: 0,
        map_id: 0,
        loc_top: -9433.33,
        loc_bottom: -10850.00,
        loc_left: -9916.67,
        loc_right: -11333.33,
        default_z: 30.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1436,
        name: "Westfall",
        continent_id: 0,
        map_id: 0,
        loc_top: -9400.00,
        loc_bottom: -11733.33,
        loc_left: 3016.67,
        loc_right: -483.33,
        default_z: 20.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1437,
        name: "Wetlands",
        continent_id: 0,
        map_id: 0,
        loc_top: -2147.92,
        loc_bottom: -4904.17,
        loc_left: -389.58,
        loc_right: -4525.00,
        default_z: 10.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    // ============================================
    // Kalimdor (Continent ID: 1)
    // ============================================
    ZoneBounds {
        ui_map_id: 1411,
        name: "Durotar",
        continent_id: 1,
        map_id: 1,
        loc_top: 1808.33,
        loc_bottom: -1716.67,
        loc_left: -1962.50,
        loc_right: -7250.00,
        default_z: 20.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1412,
        name: "Mulgore",
        continent_id: 1,
        map_id: 1,
        loc_top: -272.92,
        loc_bottom: -3697.92,
        loc_left: 2047.92,
        loc_right: -3089.58,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1413,
        name: "The Barrens",
        continent_id: 1,
        map_id: 1,
        loc_top: 1612.50,
        loc_bottom: -5143.75,
        loc_left: 2622.92,
        loc_right: -7510.42,
        default_z: 30.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1438,
        name: "Teldrassil",
        continent_id: 1,
        map_id: 1,
        loc_top: 9962.50,
        loc_bottom: 7062.50,
        loc_left: 675.00,
        loc_right: -2225.00,
        default_z: 600.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1439,
        name: "Darkshore",
        continent_id: 1,
        map_id: 1,
        loc_top: 7391.67,
        loc_bottom: 3858.33,
        loc_left: 1262.50,
        loc_right: -2270.83,
        default_z: 10.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1440,
        name: "Ashenvale",
        continent_id: 1,
        map_id: 1,
        loc_top: 4041.67,
        loc_bottom: 1375.00,
        loc_left: 2025.00,
        loc_right: -4008.33,
        default_z: 30.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1441,
        name: "Thousand Needles",
        continent_id: 1,
        map_id: 1,
        loc_top: -3691.67,
        loc_bottom: -5691.67,
        loc_left: -4050.00,
        loc_right: -7050.00,
        default_z: -100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1442,
        name: "Stonetalon Mountains",
        continent_id: 1,
        map_id: 1,
        loc_top: 2916.67,
        loc_bottom: -339.58,
        loc_left: 3245.83,
        loc_right: -1637.50,
        default_z: 500.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1443,
        name: "Desolace",
        continent_id: 1,
        map_id: 1,
        loc_top: 2825.00,
        loc_bottom: 325.00,
        loc_left: 3266.67,
        loc_right: 766.67,
        default_z: 100.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1444,
        name: "Feralas",
        continent_id: 1,
        map_id: 1,
        loc_top: -2366.67,
        loc_bottom: -7000.00,
        loc_left: 5441.67,
        loc_right: -1508.33,
        default_z: 30.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1445,
        name: "Dustwallow Marsh",
        continent_id: 1,
        map_id: 1,
        loc_top: -3041.67,
        loc_bottom: -5708.33,
        loc_left: -2233.33,
        loc_right: -4900.00,
        default_z: 5.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1446,
        name: "Tanaris",
        continent_id: 1,
        map_id: 1,
        loc_top: -5875.00,
        loc_bottom: -10475.00,
        loc_left: -218.75,
        loc_right: -7118.75,
        default_z: 10.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1447,
        name: "Azshara",
        continent_id: 1,
        map_id: 1,
        loc_top: 4566.67,
        loc_bottom: 1733.33,
        loc_left: -2166.67,
        loc_right: -5000.00,
        default_z: 20.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1448,
        name: "Felwood",
        continent_id: 1,
        map_id: 1,
        loc_top: 5800.00,
        loc_bottom: 2800.00,
        loc_left: -2350.00,
        loc_right: -5350.00,
        default_z: 200.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1449,
        name: "Un'Goro Crater",
        continent_id: 1,
        map_id: 1,
        loc_top: -5275.00,
        loc_bottom: -7275.00,
        loc_left: -4216.67,
        loc_right: -6216.67,
        default_z: -50.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1451,
        name: "Silithus",
        continent_id: 1,
        map_id: 1,
        loc_top: -5800.00,
        loc_bottom: -10433.33,
        loc_left: 4641.67,
        loc_right: -2308.33,
        default_z: 30.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1452,
        name: "Winterspring",
        continent_id: 1,
        map_id: 1,
        loc_top: 7608.33,
        loc_bottom: 4241.67,
        loc_left: -3362.50,
        loc_right: -7395.83,
        default_z: 600.0,
        game_version: GameVersion::Era,
        exclusion_zones: &[],
    },
    // ============================================
    // TBC Outland (Continent ID: 530)
    // ============================================
    ZoneBounds {
        ui_map_id: 1944,
        name: "Hellfire Peninsula",
        continent_id: 530,
        map_id: 530,
        loc_top: 825.00,
        loc_bottom: -3275.00,
        loc_left: -5250.00,
        loc_right: -9350.00,
        default_z: 100.0,
        game_version: GameVersion::Tbc,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1946,
        name: "Zangarmarsh",
        continent_id: 530,
        map_id: 530,
        loc_top: 733.33,
        loc_bottom: -2600.00,
        loc_left: -1450.00,
        loc_right: -4783.33,
        default_z: 20.0,
        game_version: GameVersion::Tbc,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1948,
        name: "Terokkar Forest",
        continent_id: 530,
        map_id: 530,
        loc_top: -1666.67,
        loc_bottom: -5333.33,
        loc_left: -850.00,
        loc_right: -4516.67,
        default_z: 50.0,
        game_version: GameVersion::Tbc,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1951,
        name: "Nagrand",
        continent_id: 530,
        map_id: 530,
        loc_top: -575.00,
        loc_bottom: -3908.33,
        loc_left: 3366.67,
        loc_right: 33.33,
        default_z: 60.0,
        game_version: GameVersion::Tbc,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1952,
        name: "Blade's Edge Mountains",
        continent_id: 530,
        map_id: 530,
        loc_top: 3700.00,
        loc_bottom: 533.33,
        loc_left: -466.67,
        loc_right: -3633.33,
        default_z: 200.0,
        game_version: GameVersion::Tbc,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1953,
        name: "Netherstorm",
        continent_id: 530,
        map_id: 530,
        loc_top: 4866.67,
        loc_bottom: 1200.00,
        loc_left: -4466.67,
        loc_right: -8133.33,
        default_z: 300.0,
        game_version: GameVersion::Tbc,
        exclusion_zones: &[],
    },
    ZoneBounds {
        ui_map_id: 1950,
        name: "Shadowmoon Valley",
        continent_id: 530,
        map_id: 530,
        loc_top: -2166.67,
        loc_bottom: -5500.00,
        loc_left: -5016.67,
        loc_right: -8350.00,
        default_z: 100.0,
        game_version: GameVersion::Tbc,
        exclusion_zones: &[],
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_zone_by_id() {
        let elwynn = ZONE_DATABASE.iter().find(|z| z.ui_map_id == 1429);
        assert!(elwynn.is_some());
        assert_eq!(elwynn.unwrap().name, "Elwynn Forest");
    }

    #[test]
    fn test_coordinate_conversion() {
        let elwynn = ZONE_DATABASE.iter().find(|z| z.ui_map_id == 1429).unwrap();

        // Test corner conversion (0,0 should give top-left)
        let (x, y, z) = elwynn.to_world_coords(0.0, 0.0);
        assert!((x - elwynn.loc_top).abs() < 0.1);
        assert!((y - elwynn.loc_left).abs() < 0.1);

        // Test opposite corner (1,1 should give bottom-right)
        let (x, y, _z) = elwynn.to_world_coords(1.0, 1.0);
        assert!((x - elwynn.loc_bottom).abs() < 0.1);
        assert!((y - elwynn.loc_right).abs() < 0.1);
    }

    #[test]
    fn test_zone_dimensions() {
        let durotar = ZONE_DATABASE.iter().find(|z| z.ui_map_id == 1411).unwrap();
        assert!(durotar.width() > 0.0);
        assert!(durotar.height() > 0.0);
    }
}
