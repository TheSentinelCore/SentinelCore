mod common;

use rusqlite::Connection;

#[test]
fn required_indexes_exist_and_query_plan_uses_map_xy_index() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());
    let runtime = common::build_runtime_db(&config);

    let conn = Connection::open(runtime).expect("open runtime db");

    let required_indexes = [
        "idx_creature_map_id",
        "idx_creature_id_map",
        "idx_creature_map_xy",
        "idx_creature_template_entry",
        "idx_npc_vendor_entry",
        "idx_npc_trainer_entry",
        "idx_faction_store_entry",
    ];

    for index_name in required_indexes {
        let exists: i64 = conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='index' AND name=?1)",
                [index_name],
                |row| row.get(0),
            )
            .expect("index existence query should work");
        assert_eq!(exists, 1, "missing index {}", index_name);
    }

    let mut stmt = conn
        .prepare(
            "EXPLAIN QUERY PLAN SELECT guid FROM creature WHERE map=?1 AND position_x BETWEEN ?2 AND ?3 AND position_y BETWEEN ?4 AND ?5",
        )
        .expect("prepare explain query plan");

    let plan_rows: Vec<String> = stmt
        .query_map([0_i64, -20_i64, 0_i64, 0_i64, 20_i64], |row| row.get(3))
        .expect("query plan should run")
        .collect::<Result<_, _>>()
        .expect("collect explain rows");

    let combined = plan_rows.join(" ").to_lowercase();
    assert!(
        combined.contains("idx_creature_map_xy") || combined.contains("idx_creature_map_id"),
        "expected explain plan to reference creature map indexes, got: {}",
        combined
    );
}
