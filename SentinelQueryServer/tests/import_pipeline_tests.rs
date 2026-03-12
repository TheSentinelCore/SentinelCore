mod common;

use rusqlite::Connection;
use sentinel_query_server::importer::validator::validate_runtime_db;
use sentinel_query_server::importer::Importer;

#[test]
fn missing_runtime_db_triggers_build_and_manifest() {
    let temp = tempfile::tempdir().expect("tempdir");
    let config = common::make_config(temp.path());

    assert!(!config.paths.runtime_db.exists());

    let importer = Importer::new(config.clone());
    let runtime = importer
        .ensure_runtime_db()
        .expect("import should build runtime db");

    assert!(runtime.exists());

    let manifest = validate_runtime_db(&runtime).expect("runtime db should validate");
    assert_eq!(manifest.source, "cmangos");
    assert_eq!(manifest.game_version, "tbc");
    assert!(manifest.dataset_version.contains("importer-v1"));
}

#[test]
fn failed_import_leaves_previous_active_db_untouched() {
    let temp = tempfile::tempdir().expect("tempdir");
    let mut config = common::make_config(temp.path());

    let importer = Importer::new(config.clone());
    let runtime = importer
        .ensure_runtime_db()
        .expect("first import should succeed");

    let old_manifest = validate_runtime_db(&runtime).expect("runtime should validate");

    let bad_dump = temp.path().join("broken.sql");
    std::fs::write(&bad_dump, "CREATE TABLE broken (id INTEGER;\n")
        .expect("should write broken dump");

    config.paths.source_dump_sql = bad_dump;
    let bad_importer = Importer::new(config);

    let err = bad_importer
        .rebuild_runtime_db()
        .expect_err("import should fail");
    assert_eq!(err.code.as_str(), "DATASET_INVALID");

    let manifest_after =
        validate_runtime_db(&runtime).expect("active runtime db should remain valid");
    assert_eq!(old_manifest.dataset_version, manifest_after.dataset_version);

    let conn = Connection::open(&runtime).expect("runtime db should remain openable");
    let table_exists: i64 = conn
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='creature')",
            [],
            |row| row.get(0),
        )
        .expect("query should work");
    assert_eq!(table_exists, 1);
}
