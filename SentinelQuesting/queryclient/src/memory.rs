//! In-memory [`QueryClient`] implementation — real, dependency-free, used for offline dev and tests.
//!
//! It is *not* a stub: it performs genuine lookups/filters over the data it holds and implements
//! every trait method. It is the contract's reference implementation and stands in for the HTTP
//! transport when no server is available.

use async_trait::async_trait;

use super::{error::QueryClientError, models::*, QueryClient};

#[derive(Debug, Clone, Default)]
pub struct MemoryQueryClient {
    quests: Vec<QuestDetail>,
    npcs: Vec<NpcDetail>,
    vendors: Vec<VendorInfo>,
    trainers: Vec<TrainerInfo>,
    flights: Vec<FlightInfo>,
    objects: Vec<ObjectInfo>,
    creature_polygons: Vec<CreaturePolygon>,
    item_sources: Vec<(u32, Vec<u32>)>,
}

impl MemoryQueryClient {
    pub fn new() -> Self {
        Self::default()
    }

    /// Builder-style insertion used by tests and offline fixtures.
    pub fn with_quest(mut self, q: QuestDetail) -> Self {
        self.quests.push(q);
        self
    }

    pub fn with_npc(mut self, n: NpcDetail) -> Self {
        self.npcs.push(n);
        self
    }

    pub fn with_vendor(mut self, v: VendorInfo) -> Self {
        self.vendors.push(v);
        self
    }

    pub fn with_trainer(mut self, t: TrainerInfo) -> Self {
        self.trainers.push(t);
        self
    }

    pub fn with_flight(mut self, f: FlightInfo) -> Self {
        self.flights.push(f);
        self
    }

    pub fn with_object(mut self, o: ObjectInfo) -> Self {
        self.objects.push(o);
        self
    }

    pub fn with_creature_polygon(mut self, p: CreaturePolygon) -> Self {
        self.creature_polygons.push(p);
        self
    }

    /// Register the creatures whose loot yields `item` (Level-1 enrichment fixture).
    pub fn with_item_sources(mut self, item: u32, sources: Vec<u32>) -> Self {
        self.item_sources.push((item, sources));
        self
    }
}

#[async_trait]
impl QueryClient for MemoryQueryClient {
    async fn search_quests(&self, query: &str) -> Result<Vec<QuestSummary>, QueryClientError> {
        let q = query.to_ascii_lowercase();
        Ok(self
            .quests
            .iter()
            .filter(|d| d.title.to_ascii_lowercase().contains(&q))
            .map(|d| QuestSummary {
                id: d.id,
                title: d.title.clone(),
                level: d.level,
                min_level: d.min_level,
            })
            .collect())
    }

    async fn get_quest(&self, id: u32) -> Result<QuestDetail, QueryClientError> {
        self.quests
            .iter()
            .find(|d| d.id == id)
            .cloned()
            .ok_or_else(|| QueryClientError::NotFound(format!("quest {id}")))
    }

    async fn search_npcs(&self, query: &str) -> Result<Vec<NpcSummary>, QueryClientError> {
        let q = query.to_ascii_lowercase();
        Ok(self
            .npcs
            .iter()
            .filter(|d| d.name.to_ascii_lowercase().contains(&q))
            .map(|d| NpcSummary {
                entry: d.entry,
                name: d.name.clone(),
                faction: d.faction.clone(),
            })
            .collect())
    }

    async fn get_npc(&self, entry: u32) -> Result<NpcDetail, QueryClientError> {
        self.npcs
            .iter()
            .find(|d| d.entry == entry)
            .cloned()
            .ok_or_else(|| QueryClientError::NotFound(format!("npc {entry}")))
    }

    async fn get_vendor(&self, entry: u32) -> Result<VendorInfo, QueryClientError> {
        self.vendors
            .iter()
            .find(|d| d.entry == entry)
            .cloned()
            .ok_or_else(|| QueryClientError::NotFound(format!("vendor {entry}")))
    }

    async fn get_trainer(&self, entry: u32) -> Result<TrainerInfo, QueryClientError> {
        self.trainers
            .iter()
            .find(|d| d.entry == entry)
            .cloned()
            .ok_or_else(|| QueryClientError::NotFound(format!("trainer {entry}")))
    }

    async fn get_flight(&self, entry: u32) -> Result<FlightInfo, QueryClientError> {
        self.flights
            .iter()
            .find(|d| d.entry == entry)
            .cloned()
            .ok_or_else(|| QueryClientError::NotFound(format!("flight {entry}")))
    }

    async fn get_object(&self, entry: u32) -> Result<ObjectInfo, QueryClientError> {
        self.objects
            .iter()
            .find(|d| d.entry == entry)
            .cloned()
            .ok_or_else(|| QueryClientError::NotFound(format!("object {entry}")))
    }

    async fn get_item_sources(&self, item: u32) -> Result<Vec<u32>, QueryClientError> {
        // An unknown item legitimately has no sources; that is data, not an error.
        Ok(self
            .item_sources
            .iter()
            .find(|(i, _)| *i == item)
            .map(|(_, s)| s.clone())
            .unwrap_or_default())
    }

    async fn creatures_polygon(
        &self,
        creature_entry: u32,
    ) -> Result<CreaturePolygon, QueryClientError> {
        self.creature_polygons
            .iter()
            .find(|d| d.creature_entry == creature_entry)
            .cloned()
            .ok_or_else(|| QueryClientError::NotFound(format!("creature polygon {creature_entry}")))
    }

    async fn validate(&self, _req: ValidateRequest) -> Result<ValidateResponse, QueryClientError> {
        // Reference resolution against real world data is the server's job; the in-memory client
        // has nothing to validate against, so it returns a clean bill of health.
        Ok(ValidateResponse {
            diagnostics: Vec::new(),
        })
    }

    async fn travel_estimate(
        &self,
        req: TravelEstimateRequest,
    ) -> Result<TravelEstimateResponse, QueryClientError> {
        let d = distance(&req.from, &req.to);
        // Assume a nominal 7 yd/s ground speed (TBC run speed ballpark); pure estimate.
        let seconds = (d / 7.0).ceil() as u64;
        Ok(TravelEstimateResponse { seconds })
    }
}

fn distance(a: &WorldPos, b: &WorldPos) -> f32 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    let dz = a.z - b.z;
    (dx * dx + dy * dy + dz * dz).sqrt()
}
