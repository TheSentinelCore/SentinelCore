//! Root Profile — Volume 5 §"Root Profile"
//! 
//! The canonical authoring schema. Editor owns this. Compiler reads it.
//! Runtime never mutates it.
//! 
//! See: docs/adr/005-schema.md, docs/adr/007-operations.md

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::enums::{GameVersion, Faction, Race, Class};
use crate::operation::Operation;
use crate::reference::{NpcReference, QuestReference, VendorEntry};
use crate::blueprint::BlueprintReference;
use crate::variable::Variable;
use crate::metadata::{Metadata, ProfileSettings, LevelRange};

/// Root Profile — Volume 5 §"Root Profile"
/// 
/// Top-level container for all authoring data.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Profile {
    pub schema_version: String,
    pub profile_id: Uuid,
    pub name: String,
    pub author: String,
    pub description: String,
    pub game: GameVersion,
    pub faction: Faction,
    pub race: Option<Race>,
    pub class: Option<Class>,
    pub level_range: LevelRange,
    pub tags: Vec<String>,
    pub metadata: Metadata,
    pub settings: ProfileSettings,
    pub variables: Vec<Variable>,
    pub npc_library: Vec<NpcReference>,
    pub quest_library: Vec<QuestReference>,
    pub vendor_library: Vec<VendorEntry>,
    pub blueprints: Vec<BlueprintReference>,
    pub operations: Vec<Operation>,
}

impl Profile {
    pub fn new(name: impl Into<String>, author: impl Into<String>) -> Self {
        Self {
            schema_version: "1.0.0".to_string(),
            profile_id: Uuid::new_v4(),
            name: name.into(),
            author: author.into(),
            description: String::new(),
            game: GameVersion::TbcClassic,
            faction: Faction::Alliance,
            race: None,
            class: None,
            level_range: LevelRange::default(),
            tags: Vec::new(),
            metadata: Metadata::default(),
            settings: ProfileSettings::default(),
            variables: Vec::new(),
            npc_library: Vec::new(),
            quest_library: Vec::new(),
            vendor_library: Vec::new(),
            blueprints: Vec::new(),
            operations: Vec::new(),
        }
    }
    
    pub fn with_faction(mut self, faction: Faction) -> Self {
        self.faction = faction;
        self
    }
    
    pub fn with_race(mut self, race: Race) -> Self {
        self.race = Some(race);
        self
    }
    
    pub fn with_class(mut self, class: Class) -> Self {
        self.class = Some(class);
        self
    }
    
    pub fn with_level_range(mut self, min: u8, max: u8) -> Self {
        self.level_range = LevelRange::new(min, max);
        self
    }
    
    pub fn with_description(mut self, desc: impl Into<String>) -> Self {
        self.description = desc.into();
        self
    }
    
    pub fn add_operation(mut self, op: Operation) -> Self {
        self.operations.push(op);
        self
    }
    
    pub fn add_npc(mut self, npc: NpcReference) -> Self {
        self.npc_library.push(npc);
        self
    }
    
    pub fn add_quest(mut self, quest: QuestReference) -> Self {
        self.quest_library.push(quest);
        self
    }
    
    pub fn add_blueprint(mut self, bp: BlueprintReference) -> Self {
        self.blueprints.push(bp);
        self
    }
}