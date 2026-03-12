use std::sync::Arc;

use serde::Serialize;

use crate::error::AppError;
use crate::models::UnifiedEntity;
use crate::storage::query::{decode_unified_cursor, encode_unified_cursor};
use crate::storage::repositories::flight_master::{FlightMasterRepository, UtilityNearbyQuery};
use crate::storage::repositories::innkeeper::InnkeeperRepository;
use crate::storage::repositories::trainer::{TrainerNearbyQuery, TrainerRepository};
use crate::storage::repositories::vendor::{VendorNearbyQuery, VendorRepository};
use crate::storage::SqliteStore;

const ENDPOINT_UNIFIED_NEARBY: &str = "entities_nearby";
const INTERNAL_MERGE_LIMIT: u32 = 20000;

#[derive(Debug, Clone)]
pub struct UnifiedNearbyQuery {
    pub x: f64,
    pub y: f64,
    pub radius: f64,
    pub limit: u32,
    pub cursor: Option<String>,
    pub dataset_version: String,
    pub types: Vec<String>,
    pub require_sell: bool,
    pub require_repair: bool,
    pub faction: Option<String>,
    pub trainer_type: Option<String>,
    pub class_id: Option<i64>,
    pub profession_id: Option<i64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct UnifiedNearbyResponse {
    pub items: Vec<UnifiedEntity>,
    pub next_cursor: Option<String>,
    pub count: usize,
}

#[derive(Clone)]
pub struct EntityRepository {
    store: Arc<SqliteStore>,
}

impl EntityRepository {
    pub fn new(store: Arc<SqliteStore>) -> Self {
        Self { store }
    }

    pub fn nearby_entities(
        &self,
        map_id: i64,
        query: &UnifiedNearbyQuery,
    ) -> Result<UnifiedNearbyResponse, AppError> {
        let vendor_repo = VendorRepository::new(self.store.clone());
        let trainer_repo = TrainerRepository::new(self.store.clone());
        let flight_repo = FlightMasterRepository::new(self.store.clone());
        let innkeeper_repo = InnkeeperRepository::new(self.store.clone());

        let mut combined: Vec<(f64, UnifiedEntity)> = Vec::new();

        if query.types.iter().any(|t| t == "vendor") {
            let vendors = vendor_repo.nearby_vendors(
                map_id,
                &VendorNearbyQuery {
                    x: query.x,
                    y: query.y,
                    radius: query.radius,
                    limit: INTERNAL_MERGE_LIMIT,
                    cursor: None,
                    dataset_version: query.dataset_version.clone(),
                    require_sell: query.require_sell,
                    require_repair: query.require_repair,
                    faction: query.faction.clone(),
                },
            )?;

            combined.extend(vendors.items.into_iter().filter_map(|vendor| {
                let distance = vendor.distance?;
                Some((
                    distance * distance,
                    UnifiedEntity {
                        entity_type: "vendor".to_string(),
                        guid: vendor.guid,
                        entry: vendor.entry,
                        name: vendor.name,
                        map_id: vendor.map_id,
                        x: vendor.x,
                        y: vendor.y,
                        z: vendor.z,
                        distance,
                        faction_id: vendor.faction_id,
                        faction_team: vendor.faction_team,
                        can_sell: Some(vendor.can_sell),
                        can_repair: Some(vendor.can_repair),
                        trainer_type: None,
                    },
                ))
            }));
        }

        if query.types.iter().any(|t| t == "trainer") {
            let trainers = trainer_repo.nearby_trainers(
                map_id,
                &TrainerNearbyQuery {
                    x: query.x,
                    y: query.y,
                    radius: query.radius,
                    limit: INTERNAL_MERGE_LIMIT,
                    cursor: None,
                    dataset_version: query.dataset_version.clone(),
                    trainer_type: query.trainer_type.clone(),
                    class_id: query.class_id,
                    profession_id: query.profession_id,
                },
            )?;

            combined.extend(trainers.items.into_iter().filter_map(|trainer| {
                let distance = trainer.distance?;
                Some((
                    distance * distance,
                    UnifiedEntity {
                        entity_type: "trainer".to_string(),
                        guid: trainer.guid,
                        entry: trainer.entry,
                        name: trainer.name,
                        map_id: trainer.map_id,
                        x: trainer.x,
                        y: trainer.y,
                        z: trainer.z,
                        distance,
                        faction_id: trainer.faction_id,
                        faction_team: trainer.faction_team,
                        can_sell: None,
                        can_repair: None,
                        trainer_type: Some(trainer.trainer_type),
                    },
                ))
            }));
        }

        if query.types.iter().any(|t| t == "flight_master") {
            let flights = flight_repo.nearby_flight_masters(
                map_id,
                &UtilityNearbyQuery {
                    x: query.x,
                    y: query.y,
                    radius: query.radius,
                    limit: INTERNAL_MERGE_LIMIT,
                    cursor: None,
                    dataset_version: query.dataset_version.clone(),
                },
            )?;

            combined.extend(flights.items.into_iter().filter_map(|entity| {
                let distance = entity.distance?;
                Some((
                    distance * distance,
                    UnifiedEntity {
                        entity_type: "flight_master".to_string(),
                        guid: entity.guid,
                        entry: entity.entry,
                        name: entity.name,
                        map_id: entity.map_id,
                        x: entity.x,
                        y: entity.y,
                        z: entity.z,
                        distance,
                        faction_id: entity.faction_id,
                        faction_team: entity.faction_team,
                        can_sell: None,
                        can_repair: None,
                        trainer_type: None,
                    },
                ))
            }));
        }

        if query.types.iter().any(|t| t == "innkeeper") {
            let inns = innkeeper_repo.nearby_innkeepers(
                map_id,
                &UtilityNearbyQuery {
                    x: query.x,
                    y: query.y,
                    radius: query.radius,
                    limit: INTERNAL_MERGE_LIMIT,
                    cursor: None,
                    dataset_version: query.dataset_version.clone(),
                },
            )?;

            combined.extend(inns.items.into_iter().filter_map(|entity| {
                let distance = entity.distance?;
                Some((
                    distance * distance,
                    UnifiedEntity {
                        entity_type: "innkeeper".to_string(),
                        guid: entity.guid,
                        entry: entity.entry,
                        name: entity.name,
                        map_id: entity.map_id,
                        x: entity.x,
                        y: entity.y,
                        z: entity.z,
                        distance,
                        faction_id: entity.faction_id,
                        faction_team: entity.faction_team,
                        can_sell: None,
                        can_repair: None,
                        trainer_type: None,
                    },
                ))
            }));
        }

        combined.sort_by(|(a_dist, a), (b_dist, b)| {
            a_dist
                .partial_cmp(b_dist)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.guid.cmp(&b.guid))
                .then_with(|| a.entity_type.cmp(&b.entity_type))
        });

        if let Some(raw_cursor) = &query.cursor {
            let (cursor_distance_sq, cursor_guid, cursor_type) =
                decode_unified_cursor(ENDPOINT_UNIFIED_NEARBY, &query.dataset_version, raw_cursor)?;
            combined.retain(|(distance_sq, item)| {
                *distance_sq > cursor_distance_sq
                    || (*distance_sq == cursor_distance_sq
                        && (item.guid > cursor_guid
                            || (item.guid == cursor_guid && item.entity_type > cursor_type)))
            });
        }

        let next_cursor = if combined.len() > query.limit as usize {
            let (distance_sq, item) = combined
                .drain(query.limit as usize..)
                .next()
                .expect("len > limit guarantees trailing row");

            Some(encode_unified_cursor(
                ENDPOINT_UNIFIED_NEARBY,
                &query.dataset_version,
                distance_sq,
                item.guid,
                &item.entity_type,
            )?)
        } else {
            None
        };

        let items: Vec<UnifiedEntity> = combined
            .into_iter()
            .take(query.limit as usize)
            .map(|(_, item)| item)
            .collect();

        Ok(UnifiedNearbyResponse {
            count: items.len(),
            items,
            next_cursor,
        })
    }
}
