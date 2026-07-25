//! Identifier aliases and the two hand-written wire encodings the kernel artifact needs.
//!
//! ADR `07_RUNTIME_PROFILE_SCHEMA` §7.1 declares [`TaskId`] and then uses `QuestId`, `ItemId` and
//! `SpellId` without declaring them. All four are plain `u32` game/graph identifiers; they exist as
//! aliases so a signature says *which* id space it is talking about.
//!
//! Two fields in the artifact are byte arrays in Rust but **strings** on the wire, because §7.2
//! pins them that way:
//!
//! * [`RuntimeProfile::magic`](crate::kernel::RuntimeProfile::magic) — `{ "const": "SNTL" }`
//! * [`RuntimeProfile::schema_hash`](crate::kernel::RuntimeProfile::schema_hash) and
//!   [`ContentIntegrity::content_hash`](crate::kernel::ContentIntegrity::content_hash) —
//!   `{ "type": "string", "pattern": "^[0-9a-f]{64}$" }`
//!
//! The [`magic`] and [`hex32`] modules implement those encodings for `#[serde(with = "…")]`, and
//! both are **fail-closed on the way in** (C4, §5.4): a wrong magic, a wrong digest length, a
//! non-hex character, or an uppercase hex digit is a deserialization error, not a silent repair.

/// Index of a [`Task`](crate::kernel::Task) inside
/// [`RuntimeProfile::tasks`](crate::kernel::RuntimeProfile::tasks).
///
/// ADR 07 §7.1. Task order *is* the id: `tasks[i].id == i`. Guide labels (`#label`, 2,581 uses)
/// are resolved to this index by the compiler and never reach the artifact (§4.2).
pub type TaskId = u32;

/// A MaNGOS `quest_template.entry`.
///
/// Resolved offline from the corpus quest arguments (`.accept`, `.turnin`, `.complete`,
/// `.isOnQuest`, …) and verified against `tbcmangos.sqlite` (§7.3.2).
pub type QuestId = u32;

/// A MaNGOS `item_template.entry`.
///
/// Source commands: `.use`, `.collect`, `.itemcount`, `.destroy`, `.equip`, `.bankwithdraw`,
/// `.bankdeposit` (§4.1).
pub type ItemId = u32;

/// A spell id.
///
/// Source commands: `.cast` / `.usespell` (the action side), `.aura` (the aura test) and `.train`
/// in its 2-argument condition form (§4.1).
pub type SpellId = u32;

/// The four container magic bytes, `b"SNTL"` (§7.1, §6.2.5).
pub const MAGIC: [u8; 4] = *b"SNTL";

/// The wire spelling of [`MAGIC`]. §7.2 pins `"magic": { "const": "SNTL" }`.
pub const MAGIC_STR: &str = "SNTL";

/// `#[serde(with = …)]` codec mapping `[u8; 4]` to and from the JSON string `"SNTL"`.
///
/// Any other four bytes are rejected on deserialization. This is the cheapest possible instance of
/// the C4 refuse-don't-degrade rule (§5.4): a file that is not a Sentinel kernel artifact fails at
/// the first field rather than producing a half-populated profile.
pub mod magic {
    use super::{MAGIC, MAGIC_STR};
    use serde::de::Error as _;
    use serde::{Deserialize, Deserializer, Serializer};

    /// Emits the fixed string `"SNTL"`.
    ///
    /// An in-memory value that is not [`MAGIC`] is a programming error in the producer, and is
    /// reported as a serialization error rather than written out as an unloadable artifact.
    pub fn serialize<S>(value: &[u8; 4], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        if value != &MAGIC {
            return Err(serde::ser::Error::custom(format!(
                "kernel profile magic must be {MAGIC_STR:?}, got {value:?}"
            )));
        }
        serializer.serialize_str(MAGIC_STR)
    }

    /// Accepts only the exact string `"SNTL"`.
    pub fn deserialize<'de, D>(deserializer: D) -> Result<[u8; 4], D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = String::deserialize(deserializer)?;
        if raw.as_bytes() == MAGIC {
            Ok(MAGIC)
        } else {
            Err(D::Error::custom(format!(
                "kernel profile magic must be {MAGIC_STR:?}, got {raw:?}"
            )))
        }
    }
}

/// `#[serde(with = …)]` codec mapping `[u8; 32]` to and from a 64-character **lowercase** hex
/// string, the shape §7.2 pins with `"pattern": "^[0-9a-f]{64}$"`.
///
/// Deserialization rejects the wrong length, any non-hex byte, and uppercase hex digits. Uppercase
/// is rejected deliberately: two spellings of one digest would make the cross-artifact equality
/// check of §5.4.1 (profile vs sidecar index vs `.save.json`) depend on how the text was written.
///
/// Computing the digests is out of scope here — this module only moves bytes across the wire.
pub mod hex32 {
    use serde::de::Error as _;
    use serde::{Deserialize, Deserializer, Serializer};

    /// Wire width of a 32-byte digest rendered as hex.
    const WIDTH: usize = 64;
    const LOWER_DIGITS: &[u8; 16] = b"0123456789abcdef";

    /// Renders a 32-byte digest as 64 lowercase hex characters.
    pub fn encode(value: &[u8; 32]) -> String {
        let mut out = String::with_capacity(WIDTH);
        for byte in value {
            out.push(LOWER_DIGITS[usize::from(byte >> 4)] as char);
            out.push(LOWER_DIGITS[usize::from(byte & 0x0f)] as char);
        }
        out
    }

    /// Parses exactly 64 lowercase hex characters into a 32-byte digest.
    ///
    /// Returns `None` for any other input, including uppercase hex and a `0x` prefix.
    pub fn decode(text: &str) -> Option<[u8; 32]> {
        let bytes = text.as_bytes();
        if bytes.len() != WIDTH {
            return None;
        }
        let mut out = [0u8; 32];
        for (index, slot) in out.iter_mut().enumerate() {
            let high = nibble(bytes[index * 2])?;
            let low = nibble(bytes[index * 2 + 1])?;
            *slot = (high << 4) | low;
        }
        Some(out)
    }

    /// Lowercase-only hex nibble. `b'A'..=b'F'` is intentionally *not* accepted.
    fn nibble(byte: u8) -> Option<u8> {
        match byte {
            b'0'..=b'9' => Some(byte - b'0'),
            b'a'..=b'f' => Some(byte - b'a' + 10),
            _ => None,
        }
    }

    /// Serializes as a 64-character lowercase hex string.
    pub fn serialize<S>(value: &[u8; 32], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&encode(value))
    }

    /// Deserializes a 64-character lowercase hex string, refusing anything else.
    pub fn deserialize<'de, D>(deserializer: D) -> Result<[u8; 32], D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = String::deserialize(deserializer)?;
        decode(&raw).ok_or_else(|| {
            D::Error::custom(format!(
                "expected a 64-character lowercase hex digest matching ^[0-9a-f]{{64}}$, got {raw:?}"
            ))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex32_round_trips_lowercase() {
        let mut digest = [0u8; 32];
        for (index, slot) in digest.iter_mut().enumerate() {
            *slot = index as u8;
        }
        let text = hex32::encode(&digest);
        assert_eq!(text.len(), 64);
        assert!(text.starts_with("000102030405060708090a0b0c0d0e0f"));
        assert_eq!(hex32::decode(&text), Some(digest));
    }

    #[test]
    fn hex32_rejects_uppercase_wrong_length_and_non_hex() {
        assert_eq!(hex32::decode(&"AB".repeat(32)), None, "uppercase");
        assert_eq!(hex32::decode(&"ab".repeat(31)), None, "too short");
        assert_eq!(hex32::decode(&"ab".repeat(33)), None, "too long");
        assert_eq!(hex32::decode(&"zz".repeat(32)), None, "non-hex");
    }

    #[test]
    fn magic_constants_agree() {
        assert_eq!(MAGIC_STR.as_bytes(), &MAGIC);
    }
}
