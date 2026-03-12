use std::collections::BTreeSet;

use crate::config::Config;
use crate::error::AppError;

pub const NPC_FLAG_VENDOR: i64 = 0x80;
pub const NPC_FLAG_VENDOR_AMMO: i64 = 0x100;
pub const NPC_FLAG_VENDOR_FOOD: i64 = 0x200;
pub const NPC_FLAG_VENDOR_POISON: i64 = 0x400;
pub const NPC_FLAG_VENDOR_REAGENT: i64 = 0x800;
pub const NPC_FLAG_REPAIR: i64 = 0x1000;
pub const NPC_FLAG_FLIGHT_MASTER: i64 = 0x2000;
pub const NPC_FLAG_TRAINER: i64 = 0x10;
pub const NPC_FLAG_CLASS_TRAINER: i64 = 0x20;
pub const NPC_FLAG_PROF_TRAINER: i64 = 0x40;
pub const NPC_FLAG_INNKEEPER: i64 = 0x10000;

pub const VENDOR_MASK: i64 = NPC_FLAG_VENDOR
    | NPC_FLAG_VENDOR_AMMO
    | NPC_FLAG_VENDOR_FOOD
    | NPC_FLAG_VENDOR_POISON
    | NPC_FLAG_VENDOR_REAGENT;

pub const TRAINER_MASK: i64 = NPC_FLAG_TRAINER | NPC_FLAG_CLASS_TRAINER | NPC_FLAG_PROF_TRAINER;

pub fn validate_limit(limit: Option<u32>, cfg: &Config) -> Result<u32, AppError> {
    let limit = limit.unwrap_or(50);
    if limit == 0 || limit > cfg.limits.max_limit {
        return Err(AppError::invalid_params(format!(
            "limit must be between 1 and {}",
            cfg.limits.max_limit
        )));
    }
    Ok(limit)
}

pub fn validate_radius(radius: f64, cfg: &Config) -> Result<f64, AppError> {
    if radius <= 0.0 || radius > cfg.limits.max_radius {
        return Err(AppError::invalid_params(format!(
            "radius must be > 0 and <= {}",
            cfg.limits.max_radius
        )));
    }
    Ok(radius)
}

pub fn parse_faction_filter(faction: Option<&str>) -> Result<Option<String>, AppError> {
    let Some(raw) = faction else {
        return Ok(None);
    };

    let value = raw.trim().to_ascii_lowercase();
    if value.is_empty() {
        return Ok(None);
    }

    match value.as_str() {
        "alliance" | "a" => Ok(Some("alliance".to_string())),
        "horde" | "h" => Ok(Some("horde".to_string())),
        "neutral" | "n" => Ok(Some("neutral".to_string())),
        _ => {
            if let Ok(numeric) = value.parse::<i64>() {
                if numeric == 469 {
                    return Ok(Some("alliance".to_string()));
                }
                if numeric == 67 {
                    return Ok(Some("horde".to_string()));
                }
                if numeric == 0 {
                    return Ok(Some("neutral".to_string()));
                }
                return Ok(None);
            }

            Err(AppError::new(
                crate::error::ErrorCode::FactionFilterUnsupported,
                "faction must be alliance|horde|neutral or a numeric faction/team id",
                None,
            ))
        }
    }
}

pub fn parse_trainer_type(value: Option<&str>) -> Result<Option<String>, AppError> {
    let Some(raw) = value else {
        return Ok(None);
    };
    let normalized = raw.trim().to_ascii_lowercase();
    match normalized.as_str() {
        "class" | "profession" | "any" => Ok(Some(normalized)),
        _ => Err(AppError::invalid_params(
            "trainer_type must be class|profession|any",
        )),
    }
}

pub fn parse_entity_types(csv: &str) -> Result<Vec<String>, AppError> {
    let mut out = BTreeSet::new();
    for value in csv.split(',') {
        let normalized = value.trim().to_ascii_lowercase();
        if normalized.is_empty() {
            continue;
        }
        match normalized.as_str() {
            "vendor" | "trainer" | "flight_master" | "innkeeper" => {
                out.insert(normalized);
            }
            _ => {
                return Err(AppError::invalid_params(
                    "types must be csv subset of vendor,trainer,flight_master,innkeeper",
                ));
            }
        }
    }

    if out.is_empty() {
        return Err(AppError::invalid_params("types is required"));
    }

    Ok(out.into_iter().collect())
}

pub fn can_sell(npc_flags: i64) -> bool {
    (npc_flags & VENDOR_MASK) != 0
}

pub fn can_repair(npc_flags: i64) -> bool {
    (npc_flags & NPC_FLAG_REPAIR) != 0
}

pub fn is_flight_master(npc_flags: i64) -> bool {
    (npc_flags & NPC_FLAG_FLIGHT_MASTER) != 0
}

pub fn is_innkeeper(npc_flags: i64) -> bool {
    (npc_flags & NPC_FLAG_INNKEEPER) != 0
}

pub fn is_trainer(npc_flags: i64) -> bool {
    (npc_flags & TRAINER_MASK) != 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn role_flags_are_classified() {
        assert!(can_sell(NPC_FLAG_VENDOR));
        assert!(can_repair(NPC_FLAG_REPAIR));
        assert!(is_flight_master(NPC_FLAG_FLIGHT_MASTER));
        assert!(is_innkeeper(NPC_FLAG_INNKEEPER));
        assert!(is_trainer(NPC_FLAG_TRAINER));
        assert!(!is_trainer(NPC_FLAG_VENDOR));
    }

    #[test]
    fn parse_faction_filter_accepts_numeric_values() {
        assert_eq!(
            parse_faction_filter(Some("469")).unwrap(),
            Some("alliance".to_string())
        );
        assert_eq!(
            parse_faction_filter(Some("67")).unwrap(),
            Some("horde".to_string())
        );
        assert_eq!(
            parse_faction_filter(Some("0")).unwrap(),
            Some("neutral".to_string())
        );
        assert_eq!(parse_faction_filter(Some("189")).unwrap(), None);
        assert_eq!(parse_faction_filter(Some("1")).unwrap(), None);
    }
}
