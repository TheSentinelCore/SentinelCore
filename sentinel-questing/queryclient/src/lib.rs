//! Typed client for the Sentinel QueryServer (ADR `01_ARCHITECTURE` §10, ADR `05` Part 5).
//!
//! The crate defines the [`QueryClient`] **trait** — the contract every transport implements —
//! and a working, dependency-free [`MemoryQueryClient`] used for offline development and tests.
//! The importer, validator, and compiler depend only on the trait, never on a concrete transport,
//! so a network [`HttpQueryClient`](crate::http::HttpQueryClient) (added next) slots in behind it
//! without touching downstream code.

pub mod error;
pub mod http;
pub mod memory;
pub mod models;

pub use error::QueryClientError;
pub use http::HttpQueryClient;
pub use memory::MemoryQueryClient;
pub use models::*;

use async_trait::async_trait;

/// Contract implemented by every QueryServer transport (ADR `01_ARCHITECTURE` §10 endpoints).
///
/// All methods are async: the primary transport is HTTP, but the trait is transport-agnostic.
#[async_trait]
pub trait QueryClient: Send + Sync {
    /// `GET /quests/search?q=`
    async fn search_quests(&self, query: &str) -> Result<Vec<QuestSummary>, QueryClientError>;
    /// `GET /quest/{id}`
    async fn get_quest(&self, id: u32) -> Result<QuestDetail, QueryClientError>;
    /// `GET /npc/search?q=`
    async fn search_npcs(&self, query: &str) -> Result<Vec<NpcSummary>, QueryClientError>;
    /// `GET /npc/{entry}`
    async fn get_npc(&self, entry: u32) -> Result<NpcDetail, QueryClientError>;
    /// `GET /vendor/{entry}`
    async fn get_vendor(&self, entry: u32) -> Result<VendorInfo, QueryClientError>;
    /// `GET /trainer/{entry}`
    async fn get_trainer(&self, entry: u32) -> Result<TrainerInfo, QueryClientError>;
    /// `GET /flight/{entry}`
    async fn get_flight(&self, entry: u32) -> Result<FlightInfo, QueryClientError>;
    /// `GET /object/{entry}`
    async fn get_object(&self, entry: u32) -> Result<ObjectInfo, QueryClientError>;
    /// `GET /creatures/polygon?entry=`
    async fn creatures_polygon(
        &self,
        creature_entry: u32,
    ) -> Result<CreaturePolygon, QueryClientError>;
    /// `POST /validate`
    async fn validate(&self, req: ValidateRequest) -> Result<ValidateResponse, QueryClientError>;
    /// `POST /travel/estimate`
    async fn travel_estimate(
        &self,
        req: TravelEstimateRequest,
    ) -> Result<TravelEstimateResponse, QueryClientError>;
}
