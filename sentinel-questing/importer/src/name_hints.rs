//! Name hint extraction from guide notes (Wave 3).
//!
//! Extracts NPC names from RestedXP color codes in notes and text.
//! Format: `|cRXP_FRIENDLY_Name|r` or `|cRXP_ENEMY_Name|r`
//!
//! These hints provide fallback NPC names for resolution when no explicit `.target` exists.

/// Extract NPC name hints from RestedXP styled text.
/// Finds patterns like `|cRXP_FRIENDLY_Name|r` and returns the cleaned name.
pub fn extract_npc_name_hints(text: &str) -> Vec<String> {
    let mut names = Vec::new();
    // Match |cRXP_FRIENDLY_Name|r or |cRXP_ENEMY_Name|r patterns
    // The format is: |c followed by RXP_..._ then the name, then |r
    let re = regex::Regex::new(r"\|cRXP_(?:FRIENDLY|ENEMY)_([^|]+)\|r").unwrap();
    for cap in re.captures_iter(text) {
        if let Some(name) = cap.get(1) {
            // Clean up the name - remove quotes if present (e.g., "Auntie" Bernice -> Auntie Bernice)
            let cleaned = name.as_str().replace('"', "");
            if !cleaned.is_empty() {
                names.push(cleaned);
            }
        }
    }
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_single_friendly_name() {
        let text = "Talk to |cRXP_FRIENDLY_Dane Winslow|r";
        let hints = extract_npc_name_hints(text);
        assert_eq!(hints, vec!["Dane Winslow"]);
    }

    #[test]
    fn extracts_multiple_names() {
        let text = "Talk to |cRXP_FRIENDLY_A|r and |cRXP_ENEMY_B|r";
        let hints = extract_npc_name_hints(text);
        assert_eq!(hints, vec!["A", "B"]);
    }

    #[test]
    fn handles_quotes_in_names() {
        let text = "Talk to |cRXP_FRIENDLY_\"Auntie\" Bernice|r";
        let hints = extract_npc_name_hints(text);
        assert_eq!(hints, vec!["Auntie Bernice"]);
    }
}