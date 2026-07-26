//! `EntityRef` — the one pointer shape from authored intent to a game entity (ADR 09a §1.2).
//!
//! `{ "ref": "npc:823", "label": "Deputy Willem" }`. The `ref` is authoritative; `label` is a
//! cached display string refreshed on resolve so the IDE and `git diff` read without a database
//! round-trip. Nothing may resolve against `label`.

use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use thiserror::Error;

/// The entity kinds a `ref` may name (ADR 09a §1.2). Closed on purpose: an unrecognised kind is
/// an authoring error that must surface, and a `ref` that silently became a default would point
/// the resolver at the wrong table.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum EntityKind {
    Npc,
    Quest,
    Item,
    Object,
    Area,
    Spell,
    Map,
}

impl EntityKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            EntityKind::Npc => "npc",
            EntityKind::Quest => "quest",
            EntityKind::Item => "item",
            EntityKind::Object => "object",
            EntityKind::Area => "area",
            EntityKind::Spell => "spell",
            EntityKind::Map => "map",
        }
    }
}

impl fmt::Display for EntityKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for EntityKind {
    type Err = EntityRefError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "npc" => Ok(EntityKind::Npc),
            "quest" => Ok(EntityKind::Quest),
            "item" => Ok(EntityKind::Item),
            "object" => Ok(EntityKind::Object),
            "area" => Ok(EntityKind::Area),
            "spell" => Ok(EntityKind::Spell),
            "map" => Ok(EntityKind::Map),
            other => Err(EntityRefError::UnknownKind {
                kind: other.to_string(),
            }),
        }
    }
}

/// Every way a `<kind>:<id>` string can fail to be a reference. Typed rather than a bool so the
/// editor can say *which* half is wrong, and so no parse path can end in a silent default.
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum EntityRefError {
    #[error("entity ref `{text}` is missing the `<kind>:<id>` separator")]
    MissingSeparator { text: String },

    #[error(
        "unknown entity kind `{kind}` (expected one of npc, quest, item, object, area, spell, map)"
    )]
    UnknownKind { kind: String },

    #[error("entity ref id `{id}` is not a non-negative integer")]
    InvalidId { id: String },
}

/// A pointer from authored intent to a game entity.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct EntityRef {
    pub kind: EntityKind,
    pub id: u32,
    /// Cached display string. Never authoritative — refreshed on every resolve.
    pub label: String,
}

impl EntityRef {
    pub fn new(kind: EntityKind, id: u32, label: impl Into<String>) -> Self {
        Self {
            kind,
            id,
            label: label.into(),
        }
    }

    /// Parse the authoritative `<kind>:<id>` half. The label is not involved.
    pub fn parse(text: &str) -> Result<Self, EntityRefError> {
        let (kind, id) = text
            .split_once(':')
            .ok_or_else(|| EntityRefError::MissingSeparator {
                text: text.to_string(),
            })?;
        let kind: EntityKind = kind.parse()?;
        let id: u32 = id
            .parse()
            .map_err(|_| EntityRefError::InvalidId { id: id.to_string() })?;
        Ok(Self {
            kind,
            id,
            label: String::new(),
        })
    }

    pub fn as_ref_string(&self) -> String {
        format!("{}:{}", self.kind, self.id)
    }
}

/// The on-wire shape. `EntityRef` keeps `kind`/`id` split in memory so callers cannot forget to
/// parse, but the JSON stays the single `ref` string the ADR fixes.
#[derive(Serialize, Deserialize)]
struct EntityRefWire {
    #[serde(rename = "ref")]
    reference: String,
    #[serde(default)]
    label: String,
}

impl Serialize for EntityRef {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        EntityRefWire {
            reference: self.as_ref_string(),
            label: self.label.clone(),
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for EntityRef {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let wire = EntityRefWire::deserialize(deserializer)?;
        let mut parsed = EntityRef::parse(&wire.reference).map_err(serde::de::Error::custom)?;
        parsed.label = wire.label;
        Ok(parsed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_every_documented_kind() {
        for (text, kind) in [
            ("npc:823", EntityKind::Npc),
            ("quest:783", EntityKind::Quest),
            ("item:2589", EntityKind::Item),
            ("object:1617", EntityKind::Object),
            ("area:12", EntityKind::Area),
            ("spell:8690", EntityKind::Spell),
            ("map:0", EntityKind::Map),
        ] {
            let parsed = EntityRef::parse(text).expect("documented kind must parse");
            assert_eq!(parsed.kind, kind);
        }
    }

    #[test]
    fn exposes_the_numeric_id_behind_the_ref() {
        let parsed = EntityRef::parse("npc:823").unwrap();
        assert_eq!(parsed.id, 823);
        assert_eq!(parsed.kind, EntityKind::Npc);
    }

    #[test]
    fn rejects_unknown_kind_instead_of_defaulting() {
        let err = EntityRef::parse("mount:823").unwrap_err();
        assert!(matches!(err, EntityRefError::UnknownKind { .. }), "{err:?}");
    }

    #[test]
    fn rejects_missing_separator() {
        let err = EntityRef::parse("npc823").unwrap_err();
        assert!(
            matches!(err, EntityRefError::MissingSeparator { .. }),
            "{err:?}"
        );
    }

    #[test]
    fn rejects_non_numeric_id() {
        let err = EntityRef::parse("npc:willem").unwrap_err();
        assert!(matches!(err, EntityRefError::InvalidId { .. }), "{err:?}");
    }

    #[test]
    fn serializes_as_ref_plus_cached_label() {
        let entity = EntityRef::new(EntityKind::Npc, 823, "Deputy Willem");
        let json = serde_json::to_value(&entity).unwrap();
        assert_eq!(
            json,
            serde_json::json!({ "ref": "npc:823", "label": "Deputy Willem" })
        );
    }

    #[test]
    fn deserializing_an_invalid_ref_fails_loudly() {
        let err = serde_json::from_str::<EntityRef>(r#"{"ref":"mount:1","label":"x"}"#)
            .expect_err("an unknown kind must not deserialize into a default");
        assert!(err.to_string().contains("mount"), "{err}");
    }

    #[test]
    fn round_trips_through_json() {
        let entity = EntityRef::new(EntityKind::Quest, 783, "Kobold Camp Cleanup");
        let json = serde_json::to_string(&entity).unwrap();
        let back: EntityRef = serde_json::from_str(&json).unwrap();
        assert_eq!(back, entity);
    }

    #[test]
    fn label_is_not_part_of_identity_but_travels_with_the_ref() {
        // `label` is a cached display string; it is refreshed on resolve and must never be read
        // as authoritative. It still round-trips so `git diff` stays readable.
        let stale = EntityRef::new(EntityKind::Npc, 823, "Deputy Willem (old)");
        assert_eq!(stale.as_ref_string(), "npc:823");
    }
}
