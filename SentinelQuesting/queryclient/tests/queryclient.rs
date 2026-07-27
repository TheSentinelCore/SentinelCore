//! Phase 2 acceptance tests for the QueryClient (trait + in-memory reference implementation).

use sentinel_queryclient::{
    HttpQueryClient, MemoryQueryClient, NpcDetail, QueryClient, QueryClientError, QuestDetail,
    VendorInfo, WorldPos,
};

fn sample_client() -> MemoryQueryClient {
    MemoryQueryClient::new()
        .with_quest(QuestDetail {
            id: 54,
            title: "A Threat Within".into(),
            level: 1,
            min_level: 1,
            required_quests: vec![],
            next_quests: vec![],
            giver_entry: Some(197),
            finisher_entry: Some(197),
            objectives: vec!["Kill 8 Kobold Vermin".into()],
            structured_objectives: vec![],
        })
        .with_npc(NpcDetail {
            entry: 197,
            name: "Marshal Dughan".into(),
            faction: "Alliance".into(),
            positions: vec![WorldPos {
                map: 0,
                x: 1.0,
                y: 2.0,
                z: 3.0,
            }],
            roles: vec!["QuestGiver".into(), "Vendor".into()],
            ..Default::default()
        })
        .with_vendor(VendorInfo {
            entry: 197,
            name: "Marshal Dughan".into(),
            sells: vec![],
            repairs: true,
        })
}

#[tokio::test]
async fn get_quest_resolves_detail() {
    let c = sample_client();
    let q = c.get_quest(54).await.unwrap();
    assert_eq!(q.title, "A Threat Within");
    assert_eq!(q.giver_entry, Some(197));
}

#[tokio::test]
async fn search_quests_filters_case_insensitive() {
    let c = sample_client();
    let hits = c.search_quests("threat").await.unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].id, 54);
    let none = c.search_quests("zzz").await.unwrap();
    assert!(none.is_empty());
}

#[tokio::test]
async fn get_npc_and_vendor_by_entry() {
    let c = sample_client();
    let npc = c.get_npc(197).await.unwrap();
    assert_eq!(npc.name, "Marshal Dughan");
    assert!(npc.roles.contains(&"QuestGiver".to_string()));
    let v = c.get_vendor(197).await.unwrap();
    assert!(v.repairs);
}

#[tokio::test]
async fn missing_entity_is_not_found() {
    let c = sample_client();
    assert!(c.get_quest(9999).await.is_err());
    assert!(c.get_npc(9999).await.is_err());
}

#[tokio::test]
async fn travel_estimate_is_deterministic() {
    let c = sample_client();
    let r = c
        .travel_estimate(sentinel_queryclient::TravelEstimateRequest {
            from: WorldPos {
                map: 0,
                x: 0.0,
                y: 0.0,
                z: 0.0,
            },
            to: WorldPos {
                map: 0,
                x: 7.0,
                y: 0.0,
                z: 0.0,
            },
        })
        .await
        .unwrap();
    assert_eq!(r.seconds, 1);
}

#[tokio::test]
async fn http_client_surfaces_transport_error() {
    // Port 1 is closed; the client should retry once then return a Transport error (no panic).
    let client = HttpQueryClient::new("http://127.0.0.1:1").with_retries(1);
    let err = client.get_quest(54).await.unwrap_err();
    assert!(
        matches!(err, QueryClientError::Transport(_)),
        "expected Transport error, got {err:?}"
    );
}
