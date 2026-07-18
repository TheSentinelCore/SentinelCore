use std::collections::HashMap;

use sentinel_schema::{
    ActionPayload, CreatureReference, GameObjectReference, NpcReference, Profile, QuestReference,
};

use crate::diagnostics::{Diagnostic, Severity, Stage};
use crate::query_client::QueryClient;

/// Intermediate representation after Stage 2.
/// Each action has been validated against QueryServer.
#[derive(Debug, Clone)]
pub struct ResolvedProfile {
    pub profile: Profile,
    pub resolved_npcs: HashMap<u32, ResolvedNpc>,
    pub resolved_quests: HashMap<u32, ResolvedQuest>,
    pub resolved_creatures: HashMap<u32, ResolvedCreature>,
}

#[derive(Debug, Clone)]
pub struct ResolvedNpc {
    pub reference: NpcReference,
    pub verified: bool, // true if QueryServer confirmed the data
}

#[derive(Debug, Clone)]
pub struct ResolvedQuest {
    pub reference: QuestReference,
    pub verified: bool,
}

#[derive(Debug, Clone)]
pub struct ResolvedCreature {
    pub reference: CreatureReference,
    pub verified: bool,
}

/// Resolution cache keyed by (entry_id, db_version).
/// When `db_version` matches, skip re-resolving.
#[derive(Debug, Clone)]
pub struct ResolutionCache {
    pub db_version: String,
    pub npcs: HashMap<u32, ResolvedNpc>,
    pub quests: HashMap<u32, ResolvedQuest>,
    pub creatures: HashMap<u32, ResolvedCreature>,
}

impl ResolutionCache {
    pub fn new(db_version: impl Into<String>) -> Self {
        Self {
            db_version: db_version.into(),
            npcs: HashMap::new(),
            quests: HashMap::new(),
            creatures: HashMap::new(),
        }
    }

    pub fn matches_version(&self, db_version: &str) -> bool {
        self.db_version == db_version
    }
}

/// Collect all unique NPC entry IDs referenced across all actions in a profile.
fn collect_npc_entries(profile: &Profile) -> Vec<u32> {
    let mut seen = std::collections::HashSet::new();
    let mut entries = Vec::new();

    for op in &profile.operations {
        for action in &op.actions {
            for npc in extract_npc_references(&action.payload) {
                if seen.insert(npc.entry) {
                    entries.push(npc.entry);
                }
            }
        }
    }

    entries
}

/// Collect all unique Quest IDs referenced across all actions.
fn collect_quest_ids(profile: &Profile) -> Vec<u32> {
    let mut seen = std::collections::HashSet::new();
    let mut ids = Vec::new();

    for op in &profile.operations {
        for action in &op.actions {
            for quest_id in extract_quest_references(&action.payload) {
                if seen.insert(quest_id) {
                    ids.push(quest_id);
                }
            }
        }
    }

    ids
}

/// Collect all unique Creature entry IDs referenced across all actions.
fn collect_creature_entries(profile: &Profile) -> Vec<u32> {
    let mut seen = std::collections::HashSet::new();
    let mut entries = Vec::new();

    for op in &profile.operations {
        for action in &op.actions {
            for creature in extract_creature_references(&action.payload) {
                if seen.insert(creature.entry) {
                    entries.push(creature.entry);
                }
            }
        }
    }

    entries
}

/// Collect all unique GameObject entry IDs referenced across all actions.
fn collect_gameobject_entries(profile: &Profile) -> Vec<u32> {
    let mut seen = std::collections::HashSet::new();
    let mut entries = Vec::new();

    for op in &profile.operations {
        for action in &op.actions {
            for go in extract_gameobject_references(&action.payload) {
                if seen.insert(go.entry) {
                    entries.push(go.entry);
                }
            }
        }
    }

    entries
}

/// Extract NPC references from an ActionPayload.
fn extract_npc_references(payload: &ActionPayload) -> Vec<&NpcReference> {
    match payload {
        ActionPayload::PickupQuest(a) => vec![&a.npc],
        ActionPayload::TurnInQuest(a) => vec![&a.npc],
        ActionPayload::Escort(a) => vec![&a.npc],
        ActionPayload::TalkToNpc(a) => vec![&a.npc],
        ActionPayload::Train(a) => vec![&a.trainer],
        ActionPayload::Mailbox(a) => vec![&a.mailbox],
        ActionPayload::Bank(a) => vec![&a.banker],
        ActionPayload::DeathSkip(a) => vec![&a.spirit_healer],
        ActionPayload::UseItem(a) => a.target.iter().collect(),
        ActionPayload::Vendor(a) => vec![&a.vendor.npc],
        ActionPayload::Repair(a) => vec![&a.vendor.npc],
        _ => vec![],
    }
}

/// Extract Quest ID references from an ActionPayload.
fn extract_quest_references(payload: &ActionPayload) -> Vec<u32> {
    match payload {
        ActionPayload::PickupQuest(a) => vec![a.quest.id],
        ActionPayload::TurnInQuest(a) => vec![a.quest.id],
        _ => vec![],
    }
}

/// Extract Creature references from an ActionPayload.
fn extract_creature_references(payload: &ActionPayload) -> Vec<&CreatureReference> {
    match payload {
        ActionPayload::GrindArea(a) => a.targets.iter().collect(),
        ActionPayload::KillTarget(a) => a.targets.iter().collect(),
        _ => vec![],
    }
}

/// Extract GameObject references from an ActionPayload.
fn extract_gameobject_references(payload: &ActionPayload) -> Vec<&GameObjectReference> {
    match payload {
        ActionPayload::LootObject(a) => a.objects.iter().collect(),
        _ => vec![],
    }
}

/// Stage 2: Resolve all references against QueryServer.
///
/// For every NPC reference in the profile, check the database via QueryClient.
/// Results are cached by entry ID. If the same NPC appears in multiple actions,
/// it is only resolved once.
///
/// Error codes:
/// - C-2001 — NPC entry not found in database
/// - C-2002 — Quest ID not found in database
/// - C-2003 — Creature entry not found in database
/// - C-2004 — GameObject entry not found in database
/// - C-2005 — QueryServer unreachable
/// - C-2006 — NPC data mismatch (position/name differs from profile)
pub fn resolve(
    profile: &Profile,
    query_client: &dyn QueryClient,
) -> Result<ResolvedProfile, Vec<Diagnostic>> {
    let mut diagnostics: Vec<Diagnostic> = Vec::new();

    // Build a lookup from the profile's own NPC library
    let profile_npcs: HashMap<u32, &NpcReference> =
        profile.npc_library.iter().map(|n| (n.entry, n)).collect();

    // Collect unique references to resolve
    let npc_entries = collect_npc_entries(profile);
    let quest_ids = collect_quest_ids(profile);
    let creature_entries = collect_creature_entries(profile);
    let gameobject_entries = collect_gameobject_entries(profile);

    // Resolve NPCs
    let mut resolved_npcs: HashMap<u32, ResolvedNpc> = HashMap::new();
    for &entry in &npc_entries {
        // Skip if already resolved (cache within this call)
        if resolved_npcs.contains_key(&entry) {
            continue;
        }

        match query_client.get_npc(entry) {
            Ok(db_npc) => {
                let mut verified = true;

                // Check for data mismatch (C-2006)
                if let Some(profile_npc) = profile_npcs.get(&entry) {
                    let name_mismatch = profile_npc.name != db_npc.name;
                    let pos_mismatch = (profile_npc.position.x - db_npc.position.x).abs() > f32::EPSILON
                        || (profile_npc.position.y - db_npc.position.y).abs() > f32::EPSILON
                        || (profile_npc.position.z - db_npc.position.z).abs() > f32::EPSILON;
                    if name_mismatch || pos_mismatch {
                        diagnostics.push(
                            Diagnostic::warning(
                                "C-2006",
                                Stage::ReferenceResolution,
                                format!(
                                    "NPC data mismatch for entry {}: profile has '{}' at ({}, {}, {}), database has '{}' at ({}, {}, {})",
                                    entry,
                                    profile_npc.name,
                                    profile_npc.position.x, profile_npc.position.y, profile_npc.position.z,
                                    db_npc.name,
                                    db_npc.position.x, db_npc.position.y, db_npc.position.z,
                                ),
                            )
                            .with_entity(format!("NPC entry {}", entry))
                            .with_fix("Update the NPC position/name in the profile to match the database value"),
                        );
                        verified = false;
                    }
                }

                resolved_npcs.insert(entry, ResolvedNpc {
                    reference: db_npc,
                    verified,
                });
            }
            Err(e) => {
                let err_msg = format!("{}", e);
                if err_msg.contains("not found") || err_msg.contains("404") || err_msg.contains("No such") {
                    // C-2001: NPC entry not found
                    diagnostics.push(
                        Diagnostic::error(
                            "C-2001",
                            Stage::ReferenceResolution,
                            format!("NPC entry {} not found in database", entry),
                        )
                        .with_entity(format!("NPC entry {}", entry))
                        .with_fix("Verify the NPC entry ID is correct for your game version"),
                    );
                } else {
                    // C-2005: QueryServer unreachable
                    diagnostics.push(
                        Diagnostic::error(
                            "C-2005",
                            Stage::ReferenceResolution,
                            format!("QueryServer unreachable while resolving NPC entry {}: {}", entry, e),
                        )
                        .with_entity(format!("NPC entry {}", entry)),
                    );
                }
            }
        }
    }

    // If QueryServer is unreachable for any resolve call, we could continue
    // trying other lookups, but hard errors are already collected.

    // Resolve Quests
    let mut resolved_quests: HashMap<u32, ResolvedQuest> = HashMap::new();
    for &id in &quest_ids {
        if resolved_quests.contains_key(&id) {
            continue;
        }

        match query_client.get_quest(id) {
            Ok(db_quest) => {
                resolved_quests.insert(id, ResolvedQuest {
                    reference: db_quest,
                    verified: true,
                });
            }
            Err(e) => {
                let err_msg = format!("{}", e);
                if err_msg.contains("not found") || err_msg.contains("404") || err_msg.contains("No such") {
                    // C-2002: Quest ID not found
                    diagnostics.push(
                        Diagnostic::error(
                            "C-2002",
                            Stage::ReferenceResolution,
                            format!("Quest ID {} not found in database", id),
                        )
                        .with_entity(format!("Quest ID {}", id))
                        .with_fix("Verify the quest ID is correct for your game version"),
                    );
                } else {
                    // C-2005: QueryServer unreachable
                    diagnostics.push(
                        Diagnostic::error(
                            "C-2005",
                            Stage::ReferenceResolution,
                            format!("QueryServer unreachable while resolving quest {}: {}", id, e),
                        )
                        .with_entity(format!("Quest ID {}", id)),
                    );
                }
            }
        }
    }

    // Resolve Creatures
    let mut resolved_creatures: HashMap<u32, ResolvedCreature> = HashMap::new();
    for &entry in &creature_entries {
        if resolved_creatures.contains_key(&entry) {
            continue;
        }

        match query_client.get_creature(entry) {
            Ok(db_creature) => {
                resolved_creatures.insert(entry, ResolvedCreature {
                    reference: db_creature,
                    verified: true,
                });
            }
            Err(e) => {
                let err_msg = format!("{}", e);
                if err_msg.contains("not found") || err_msg.contains("404") || err_msg.contains("No such") {
                    // C-2003: Creature entry not found
                    diagnostics.push(
                        Diagnostic::error(
                            "C-2003",
                            Stage::ReferenceResolution,
                            format!("Creature entry {} not found in database", entry),
                        )
                        .with_entity(format!("Creature entry {}", entry))
                        .with_fix("Verify the creature entry ID is correct for your game version"),
                    );
                } else {
                    diagnostics.push(
                        Diagnostic::error(
                            "C-2005",
                            Stage::ReferenceResolution,
                            format!("QueryServer unreachable while resolving creature {}: {}", entry, e),
                        )
                        .with_entity(format!("Creature entry {}", entry)),
                    );
                }
            }
        }
    }

    // Resolve GameObjects — just check existence for now
    for &_entry in &gameobject_entries {
        // QueryClient doesn't have get_gameobject, so we try get_npc (wrong)...
        // Actually, we only check game objects from LootObject action.
        // The QueryClient trait doesn't have a dedicated game object method,
        // so we'll check creature table as a proxy or just warn.
        // For now, we skip game object resolution since QueryClient doesn't
        // expose a method for it — this is a known limitation.
    }

    // Check for errors
    if diagnostics.iter().any(|d| d.severity == Severity::Error) {
        Err(diagnostics)
    } else {
        Ok(ResolvedProfile {
            profile: profile.clone(),
            resolved_npcs,
            resolved_quests,
            resolved_creatures,
        })
    }
}

// ===========================================================================
// Tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::{
        action::{
            Action, GoToAction, GrindAreaAction, KillTargetAction, PickupQuestAction,
            StopCondition, TalkToNpcAction, WaitAction,
        },
        geometry::{Polygon, Waypoint},
        CreatureReference, NpcReference, Operation, Profile, QuestReference, VendorEntry,
    };

    // -----------------------------------------------------------------------
    // Mock QueryClient
    // -----------------------------------------------------------------------

    struct MockQueryClient {
        npcs: HashMap<u32, NpcReference>,
        quests: HashMap<u32, QuestReference>,
        creatures: HashMap<u32, CreatureReference>,
        #[allow(dead_code)]
        fail_all: bool,
    }

    impl MockQueryClient {
        #[allow(dead_code)]
        fn new() -> Self {
            Self {
                npcs: HashMap::new(),
                quests: HashMap::new(),
                creatures: HashMap::new(),
                fail_all: false,
            }
        }

        fn with_npc(mut self, entry: u32, npc: NpcReference) -> Self {
            self.npcs.insert(entry, npc);
            self
        }

        #[allow(dead_code)]
        fn with_quest(mut self, id: u32, quest: QuestReference) -> Self {
            self.quests.insert(id, quest);
            self
        }

        fn with_creature(mut self, entry: u32, creature: CreatureReference) -> Self {
            self.creatures.insert(entry, creature);
            self
        }

        #[allow(dead_code)]
        fn fail_all(mut self) -> Self {
            self.fail_all = true;
            self
        }
    }

    impl QueryClient for MockQueryClient {
        fn get_npc(&self, entry: u32) -> anyhow::Result<NpcReference> {
            if self.fail_all {
                return Err(anyhow::anyhow!("connection refused"));
            }
            self.npcs
                .get(&entry)
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("NPC {} not found", entry))
        }

        fn get_quest(&self, id: u32) -> anyhow::Result<QuestReference> {
            if self.fail_all {
                return Err(anyhow::anyhow!("connection refused"));
            }
            self.quests
                .get(&id)
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("Quest {} not found", id))
        }

        fn get_vendor(&self, entry: u32) -> anyhow::Result<VendorEntry> {
            if self.fail_all {
                return Err(anyhow::anyhow!("connection refused"));
            }
            Err(anyhow::anyhow!("Vendor {} not found", entry))
        }

        fn get_creature(&self, entry: u32) -> anyhow::Result<CreatureReference> {
            if self.fail_all {
                return Err(anyhow::anyhow!("connection refused"));
            }
            self.creatures
                .get(&entry)
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("Creature {} not found", entry))
        }

        fn search_npcs(&self, _query: &str) -> anyhow::Result<Vec<NpcReference>> {
            Ok(Vec::new())
        }

        fn get_route(
            &self,
            _from_map: u32,
            _from_x: f32,
            _from_y: f32,
            _to_map: u32,
            _to_x: f32,
            _to_y: f32,
        ) -> anyhow::Result<Vec<(f32, f32, f32)>> {
            Ok(Vec::new())
        }
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    fn test_npc(entry: u32, name: &str) -> NpcReference {
        NpcReference::new(
            entry,
            name,
            "Elwynn",
            Waypoint::new(0, "Elwynn", -8949.0, -132.0, 83.0, 5.0),
        )
    }

    fn test_quest(id: u32, title: &str) -> QuestReference {
        QuestReference::new(id, title, 197, 197)
    }

    fn test_creature(entry: u32, name: &str) -> CreatureReference {
        CreatureReference::new(entry, name)
    }

    fn empty_profile() -> Profile {
        Profile::new("Test", "Agent")
    }

    // -----------------------------------------------------------------------
    // test_resolve_valid_npc — Profile with NPC in library + in database
    // -----------------------------------------------------------------------

    #[test]
    fn test_resolve_valid_npc() {
        let npc = test_npc(197, "Marshal McBride");
        let mut profile = empty_profile();
        profile.npc_library = vec![npc.clone()];
        let mut op = Operation::new("Op1");
        op.actions = vec![Action::new(
            "Talk",
            ActionPayload::TalkToNpc(TalkToNpcAction {
                npc: npc.clone(),
                gossip_option: None,
            }),
        )];
        profile.operations = vec![op];

        let client = MockQueryClient::new().with_npc(197, npc);

        let result = resolve(&profile, &client);
        assert!(result.is_ok(), "Expected Ok but got Err: {:?}", result.err());

        let resolved = result.unwrap();
        assert!(resolved.resolved_npcs.contains_key(&197));
        assert!(resolved.resolved_npcs[&197].verified);
    }

    // -----------------------------------------------------------------------
    // test_resolve_missing_npc — C-2001 error (NPC not found in database)
    // -----------------------------------------------------------------------

    #[test]
    fn test_resolve_missing_npc() {
        let npc = test_npc(999, "Unknown NPC");
        let mut profile = empty_profile();
        profile.npc_library = vec![npc.clone()];
        let mut op = Operation::new("Op1");
        op.actions = vec![Action::new(
            "Talk",
            ActionPayload::TalkToNpc(TalkToNpcAction {
                npc: npc.clone(),
                gossip_option: None,
            }),
        )];
        profile.operations = vec![op];

        // Mock client with no NPCs — the mock returns "NPC {} not found"
        // which contains "not found", so this will be C-2001
        let client = MockQueryClient::new();

        let result = resolve(&profile, &client);
        assert!(result.is_err(), "Expected Err but got Ok");

        let diags = result.unwrap_err();
        assert!(
            diags.iter().any(|d| d.code == "C-2001"),
            "Expected C-2001 (NPC not found), got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }

    // -----------------------------------------------------------------------
    // test_resolve_missing_quest — C-2002 error
    // -----------------------------------------------------------------------

    #[test]
    fn test_resolve_missing_quest() {
        let npc = test_npc(197, "Marshal McBride");
        let quest = test_quest(999999, "Nonexistent");

        let mut profile = empty_profile();
        profile.npc_library = vec![npc.clone()];
        profile.quest_library = vec![quest.clone()];
        let mut op = Operation::new("Op1");
        op.actions = vec![Action::new(
            "Pickup",
            ActionPayload::PickupQuest(PickupQuestAction {
                quest: quest.clone(),
                npc: npc.clone(),
                auto_complete_previous: false,
            }),
        )];
        profile.operations = vec![op];

        // Mock has NPC but not quest
        let client = MockQueryClient::new()
            .with_npc(197, npc);

        let result = resolve(&profile, &client);
        assert!(result.is_err(), "Expected Err but got Ok");

        let diags = result.unwrap_err();
        // Mock returns "Quest {} not found" which contains "not found"
        assert!(
            diags.iter().any(|d| d.code == "C-2002"),
            "Expected C-2002 (Quest not found), got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }

    // -----------------------------------------------------------------------
    // test_resolve_empty_profile — Empty profile → success
    // -----------------------------------------------------------------------

    #[test]
    fn test_resolve_empty_profile() {
        let profile = empty_profile();
        let client = MockQueryClient::new();

        let result = resolve(&profile, &client);
        assert!(result.is_ok());

        let resolved = result.unwrap();
        assert!(resolved.resolved_npcs.is_empty());
        assert!(resolved.resolved_quests.is_empty());
        assert!(resolved.resolved_creatures.is_empty());
    }

    // -----------------------------------------------------------------------
    // test_resolution_cache_hits — Same NPC resolved twice → one call
    // -----------------------------------------------------------------------

    #[test]
    fn test_resolution_cache_hits() {
        let npc = test_npc(197, "Marshal McBride");
        let mut profile = empty_profile();
        profile.npc_library = vec![npc.clone()];

        // Two actions referencing the same NPC
        let mut op = Operation::new("Op1");
        op.actions = vec![
            Action::new(
                "Talk1",
                ActionPayload::TalkToNpc(TalkToNpcAction {
                    npc: npc.clone(),
                    gossip_option: None,
                }),
            ),
            Action::new(
                "Talk2",
                ActionPayload::TalkToNpc(TalkToNpcAction {
                    npc: npc.clone(),
                    gossip_option: Some("greeting".to_string()),
                }),
            ),
        ];
        profile.operations = vec![op];

        // Use a counting client wrapper to verify only one call
        struct CountingClient {
            inner: MockQueryClient,
            npc_calls: std::sync::atomic::AtomicU32,
        }

        impl QueryClient for CountingClient {
            fn get_npc(&self, entry: u32) -> anyhow::Result<NpcReference> {
                self.npc_calls
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                self.inner.get_npc(entry)
            }

            fn get_quest(&self, id: u32) -> anyhow::Result<QuestReference> {
                self.inner.get_quest(id)
            }

            fn get_vendor(&self, entry: u32) -> anyhow::Result<VendorEntry> {
                self.inner.get_vendor(entry)
            }

            fn get_creature(&self, entry: u32) -> anyhow::Result<CreatureReference> {
                self.inner.get_creature(entry)
            }

            fn search_npcs(&self, query: &str) -> anyhow::Result<Vec<NpcReference>> {
                self.inner.search_npcs(query)
            }

            fn get_route(
                &self,
                from_map: u32,
                from_x: f32,
                from_y: f32,
                to_map: u32,
                to_x: f32,
                to_y: f32,
            ) -> anyhow::Result<Vec<(f32, f32, f32)>> {
                self.inner.get_route(from_map, from_x, from_y, to_map, to_x, to_y)
            }
        }

        let client = CountingClient {
            inner: MockQueryClient::new().with_npc(197, npc),
            npc_calls: std::sync::atomic::AtomicU32::new(0),
        };

        let result = resolve(&profile, &client);
        assert!(result.is_ok());

        // Should have made exactly 1 call (cached after first)
        assert_eq!(
            client
                .npc_calls
                .load(std::sync::atomic::Ordering::SeqCst),
            1
        );
    }

    // -----------------------------------------------------------------------
    // test_npc_data_mismatch — Profile position differs from DB → C-2006
    // -----------------------------------------------------------------------

    #[test]
    fn test_npc_data_mismatch() {
        // NPC in profile at one position
        let profile_npc = NpcReference::new(
            197,
            "Marshal McBride",
            "Elwynn",
            Waypoint::new(0, "Elwynn", 0.0, 0.0, 0.0, 5.0), // different position
        );

        // NPC in database at different position
        let db_npc = NpcReference::new(
            197,
            "Marshal McBride",
            "Elwynn",
            Waypoint::new(0, "Elwynn", -8949.0, -132.0, 83.0, 5.0),
        );

        let mut profile = empty_profile();
        profile.npc_library = vec![profile_npc];
        let mut op = Operation::new("Op1");
        op.actions = vec![Action::new(
            "Talk",
            ActionPayload::TalkToNpc(TalkToNpcAction {
                npc: NpcReference::new(
                    197,
                    "Marshal McBride",
                    "Elwynn",
                    Waypoint::new(0, "Elwynn", 0.0, 0.0, 0.0, 5.0),
                ),
                gossip_option: None,
            }),
        )];
        profile.operations = vec![op];

        let client = MockQueryClient::new().with_npc(197, db_npc);

        let result = resolve(&profile, &client);
        assert!(result.is_ok(), "Mismatch is warning, not error");

        let resolved = result.unwrap();
        assert!(resolved.resolved_npcs.contains_key(&197));
        // Should NOT be verified due to position mismatch
        assert!(!resolved.resolved_npcs[&197].verified);
    }

    // -----------------------------------------------------------------------
    // test_resolve_creature — Creature resolution
    // -----------------------------------------------------------------------

    #[test]
    fn test_resolve_creature() {
        let creature = test_creature(101, "Wolf");
        let mut profile = empty_profile();
        let mut op = Operation::new("Op1");
        op.actions = vec![Action::new(
            "Kill",
            ActionPayload::KillTarget(KillTargetAction {
                targets: vec![creature.clone()],
                amount: Some(10),
            }),
        )];
        profile.operations = vec![op];

        let client = MockQueryClient::new().with_creature(101, creature);

        let result = resolve(&profile, &client);
        assert!(result.is_ok());

        let resolved = result.unwrap();
        assert!(resolved.resolved_creatures.contains_key(&101));
    }

    // -----------------------------------------------------------------------
    // test_resolve_missing_creature — C-2003 error
    // -----------------------------------------------------------------------

    #[test]
    fn test_resolve_missing_creature() {
        let creature = test_creature(99999, "Mystery Beast");
        let mut profile = empty_profile();
        let mut op = Operation::new("Op1");
        op.actions = vec![Action::new(
            "Grind",
            ActionPayload::GrindArea(GrindAreaAction {
                polygon: Polygon::new(vec![
                    Waypoint::new(0, "Zone", 0.0, 0.0, 0.0, 5.0),
                    Waypoint::new(0, "Zone", 1.0, 0.0, 0.0, 5.0),
                    Waypoint::new(0, "Zone", 0.5, 1.0, 0.0, 5.0),
                ]),
                targets: vec![creature],
                stop_condition: StopCondition::Manual,
                loot: vec![],
            }),
        )];
        profile.operations = vec![op];

        // Empty client — mock returns "Creature {} not found" which contains
        // "not found", so this will be C-2003
        let client = MockQueryClient::new();

        let result = resolve(&profile, &client);
        assert!(result.is_err());

        let diags = result.unwrap_err();
        assert!(
            diags.iter().any(|d| d.code == "C-2003"),
            "Expected C-2003 (Creature not found), got codes: {:?}",
            diags.iter().map(|d| &d.code).collect::<Vec<_>>()
        );
    }

    // -----------------------------------------------------------------------
    // test_mixed_valid_and_invalid — Some valid, some missing
    // -----------------------------------------------------------------------

    #[test]
    fn test_mixed_valid_and_invalid() {
        let npc_valid = test_npc(197, "Marshal McBride");
        let npc_invalid = test_npc(999, "Unknown");

        let mut profile = empty_profile();
        profile.npc_library = vec![npc_valid.clone(), npc_invalid.clone()];

        let mut op = Operation::new("Op1");
        op.actions = vec![
            Action::new(
                "TalkToValid",
                ActionPayload::TalkToNpc(TalkToNpcAction {
                    npc: npc_valid,
                    gossip_option: None,
                }),
            ),
            Action::new(
                "TalkToInvalid",
                ActionPayload::TalkToNpc(TalkToNpcAction {
                    npc: npc_invalid,
                    gossip_option: None,
                }),
            ),
        ];
        profile.operations = vec![op];

        let client = MockQueryClient::new().with_npc(197, test_npc(197, "Marshal McBride"));

        let result = resolve(&profile, &client);
        assert!(result.is_err(), "Expected error due to missing NPC");

        let diags = result.unwrap_err();
        // One should be the missing NPC error
        assert!(!diags.is_empty());
    }

    // -----------------------------------------------------------------------
    // test_name_mismatch_creates_warning — C-2006 for name mismatch
    // -----------------------------------------------------------------------

    #[test]
    fn test_name_mismatch_creates_warning() {
        let profile_npc = NpcReference::new(
            197,
            "Old Name",
            "Elwynn",
            Waypoint::new(0, "Elwynn", -8949.0, -132.0, 83.0, 5.0),
        );

        let db_npc = NpcReference::new(
            197,
            "New Name",
            "Elwynn",
            Waypoint::new(0, "Elwynn", -8949.0, -132.0, 83.0, 5.0),
        );

        let mut profile = empty_profile();
        profile.npc_library = vec![profile_npc];
        let mut op = Operation::new("Op1");
        op.actions = vec![Action::new(
            "Talk",
            ActionPayload::TalkToNpc(TalkToNpcAction {
                npc: NpcReference::new(
                    197,
                    "Old Name",
                    "Elwynn",
                    Waypoint::new(0, "Elwynn", -8949.0, -132.0, 83.0, 5.0),
                ),
                gossip_option: None,
            }),
        )];
        profile.operations = vec![op];

        let client = MockQueryClient::new().with_npc(197, db_npc);

        let result = resolve(&profile, &client);
        assert!(result.is_ok(), "Name mismatch should be warning, not error");

        // But the resolved entry should have verified=false
        let resolved = result.unwrap();
        assert!(!resolved.resolved_npcs[&197].verified);
    }

    // -----------------------------------------------------------------------
    // test_resolve_with_go_to_action_no_references — ensure no false positives
    // -----------------------------------------------------------------------

    #[test]
    fn test_resolve_with_no_reference_actions() {
        let mut profile = empty_profile();
        let mut op = Operation::new("Op1");
        op.actions = vec![
            Action::new(
                "GoToSpot",
                ActionPayload::GoTo(GoToAction {
                    destination: Waypoint::new(0, "Elwynn", 0.0, 0.0, 0.0, 5.0),
                    arrival_radius: 2.0,
                }),
            ),
            Action::new(
                "Wait",
                ActionPayload::Wait(WaitAction { duration_ms: 5000 }),
            ),
        ];
        profile.operations = vec![op];

        let client = MockQueryClient::new();
        let result = resolve(&profile, &client);
        assert!(result.is_ok());

        let resolved = result.unwrap();
        assert!(resolved.resolved_npcs.is_empty());
        assert!(resolved.resolved_quests.is_empty());
        assert!(resolved.resolved_creatures.is_empty());
    }
}
