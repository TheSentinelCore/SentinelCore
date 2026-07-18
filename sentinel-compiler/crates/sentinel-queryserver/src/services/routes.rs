//! Route Analysis Service — Volume 4 §17

use anyhow::Result;
use sentinel_schema::Waypoint;

use super::ServiceState;
use crate::models::*;

#[derive(Clone)]
pub struct RouteService {
    #[allow(dead_code)]
    state: ServiceState,
}

impl RouteService {
    pub fn new(state: ServiceState) -> Self {
        Self { state }
    }

    pub async fn analyze_route(
        &self,
        request: crate::api::routes::RouteAnalysisRequest,
    ) -> Result<RouteAnalysis> {
        self.analyze(request.waypoints).await
    }

    pub async fn analyze(&self, _waypoints: Vec<Waypoint>) -> Result<RouteAnalysis> {
        Ok(RouteAnalysis {
            distance: 0.0,
            travel_time_sec: 0.0,
            elevation_change: 0.0,
            zone_crossings: 0,
            suggested_split: None,
        })
    }
}
