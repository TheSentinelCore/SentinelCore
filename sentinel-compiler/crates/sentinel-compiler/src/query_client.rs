use sentinel_schema::{NpcReference, QuestReference, VendorEntry, CreatureReference};

/// Client for querying the game database via QueryServer.
///
/// Used by Stage 2 (Reference Resolution) and Stage 6 (Optimization).
/// This is a trait contract — the implementation lives in the query server
/// adapter layer. The compiler depends only on this interface.
pub trait QueryClient: Send + Sync {
    fn get_npc(&self, entry: u32) -> anyhow::Result<NpcReference>;
    fn get_quest(&self, id: u32) -> anyhow::Result<QuestReference>;
    fn get_vendor(&self, entry: u32) -> anyhow::Result<VendorEntry>;
    fn get_creature(&self, entry: u32) -> anyhow::Result<CreatureReference>;
    fn search_npcs(&self, query: &str) -> anyhow::Result<Vec<NpcReference>>;
    fn get_route(
        &self,
        from_map: u32,
        from_x: f32,
        from_y: f32,
        to_map: u32,
        to_x: f32,
        to_y: f32,
    ) -> anyhow::Result<Vec<(f32, f32, f32)>>;
}
