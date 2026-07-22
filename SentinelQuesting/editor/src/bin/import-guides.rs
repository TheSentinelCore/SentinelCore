//! Batch importer for RestedXP guides into Sentinel Questing projects.
//!
//! Usage:
//!   cargo run -p sentinel-editor --bin import-guides -- <guides_dir> <output_dir>
//!
//! Example:
//!   cargo run -p sentinel-editor --bin import-guides -- \
//!     "../sentinel/docs/adr/restedxp guides" ".questing/projects"
//!
//! This importer runs offline (no QueryServer needed). Unresolved NPCs/quests will
//! appear as diagnostic warnings in the output project - resolve them in the editor.
//!
//! Each guide file may bundle multiple `RegisterGuide([[ ... ]])` blocks (IF6, e.g. `The
//! Burning Crusade.lua`: 253 blocks in one file) — one Project JSON is written per guide block,
//! not one per file.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::fs;

use sentinel_importer::parse_guide_bundle;
use sentinel_queryclient::MemoryQueryClient;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: import-guides <guides_dir> <output_dir>");
        std::process::exit(1);
    }

    let guides_dir = PathBuf::from(&args[1]);
    let output_dir: PathBuf = args[2].clone().into();

    // Ensure output directory exists
    fs::create_dir_all(&output_dir)?;

    // Find all .lua guide files in the source directory
    let guide_files = find_guide_files(&guides_dir)?;

    if guide_files.is_empty() {
        eprintln!("No .lua guide files found in {:?}", guides_dir);
        std::process::exit(1);
    }

    println!("Found {} guide files to import", guide_files.len());

    // Use empty MemoryQueryClient (offline mode - unresolved references will be diagnostics)
    let client = MemoryQueryClient::new();

    // Tracked across the WHOLE run (not per guide file): header-less blocks from different
    // files can collide on the same default name just as easily as two blocks in one bundle
    // (CRITICAL 2 fix).
    let mut used_filenames: HashSet<String> = HashSet::new();
    let mut total_projects = 0usize;
    let mut all_failures: Vec<String> = Vec::new();
    for guide_path in &guide_files {
        let (written, failures) =
            import_guide(guide_path, &output_dir, &client, &mut used_filenames).await?;
        total_projects += written;
        all_failures.extend(failures);
    }

    if !all_failures.is_empty() {
        eprintln!("\n{} block(s) failed to import:", all_failures.len());
        for failure in &all_failures {
            eprintln!("  ✗ {failure}");
        }
    }

    println!(
        "\nImport complete! {} projects created from {} guide files in {:?}",
        total_projects, guide_files.len(), output_dir
    );

    // Exit-code convention (best-effort batch, matching this bin's existing non-strict style):
    // a run that wrote at least one project exits 0 even if some blocks failed (see warnings
    // above); only a run that wrote nothing at all, with failures recorded, is a hard failure.
    if total_projects == 0 && !all_failures.is_empty() {
        eprintln!("\nAll blocks failed to import.");
        std::process::exit(1);
    }
    Ok(())
}

fn find_guide_files(dir: &Path) -> Result<Vec<PathBuf>, std::io::Error> {
    let mut files = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().is_some_and(|e| e == "lua") {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                // Skip files that start with # (macOS resource forks)
                if !name.starts_with('#') {
                    files.push(path);
                }
            }
        }
    }
    Ok(files)
}

/// Disambiguate a candidate project filename stem against every name THIS FUNCTION HAS EVER
/// RETURNED — not just raw stems (CRITICAL 2 fix: header-less blocks all default to
/// `"Imported Guide"`, `project_builder.rs:852`, so multiple such blocks, whether in one bundle
/// or across different guide files, must not silently overwrite each other's output). Tracking
/// only stems left a loophole: a later block literally named e.g. `Foo-2` was never checked
/// against an EARLIER generated `Foo-2` and would silently collide with it (defect fix). Try the
/// bare stem, then `-2`, `-3`, ... until a name not yet returned is found; deterministic by
/// encounter order.
fn dedupe_filename(used: &mut HashSet<String>, stem: &str) -> String {
    let mut candidate = stem.to_string();
    let mut suffix = 2u32;
    while used.contains(&candidate) {
        candidate = format!("{stem}-{suffix}");
        suffix += 1;
    }
    used.insert(candidate.clone());
    candidate
}

/// Import every `RegisterGuide` block in `guide_path` (IF6: a file may bundle several guides),
/// writing one Project JSON per block. A per-block parse/build/write failure is recorded and
/// does NOT abort the remaining blocks in this file, matching `parse_guide_bundle`'s own
/// per-block isolation contract (`lib.rs:157-165`) instead of contradicting it (CRITICAL 1 fix).
/// Returns the number of projects actually written plus any recorded failure messages.
async fn import_guide(
    guide_path: &Path,
    output_dir: &Path,
    client: &MemoryQueryClient,
    used_filenames: &mut HashSet<String>,
) -> Result<(usize, Vec<String>), Box<dyn std::error::Error>> {
    let source = fs::read_to_string(guide_path)?;

    let mut written = 0usize;
    let mut failures = Vec::new();

    for (block_idx, result) in parse_guide_bundle(&source).into_iter().enumerate() {
        let outcome: Result<(), String> = async {
            let parsed = result.map_err(|e| e.to_string())?;
            let project = sentinel_importer::ProjectBuilder::build(
                &parsed,
                guide_path.to_string_lossy().as_ref(),
                client,
            ).await.map_err(|e| e.to_string())?;

            let stem = dedupe_filename(used_filenames, &project.metadata.name.replace(' ', "-"));
            let output_path = output_dir.join(format!("{stem}.json"));
            let json = serde_json::to_string_pretty(&project).map_err(|e| e.to_string())?;
            fs::write(&output_path, json).map_err(|e| e.to_string())?;

            println!("✓ Imported: {:?} → {:?}", guide_path.file_name().unwrap(), output_path.file_name().unwrap());
            let unresolved_count = project.diagnostics.iter()
                .filter(|d| d.code.starts_with("UNRESOLVED_"))
                .count();
            if unresolved_count > 0 {
                println!("  ({} unresolved references - resolve in editor)", unresolved_count);
            }
            Ok(())
        }.await;

        match outcome {
            Ok(()) => written += 1,
            Err(e) => {
                let msg = format!("{}: block {block_idx}: {e}", guide_path.display());
                eprintln!("✗ {msg}");
                failures.push(msg);
            }
        }
    }

    Ok((written, failures))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn one_bad_block_does_not_abort_the_rest() {
        // CRITICAL 1: a malformed second block must not abort the well-formed first block, nor
        // (transitively, via main's own `?`) any other guide file in the run.
        let dir = tempfile::tempdir().unwrap();
        let guide_path = dir.path().join("bundle.lua");
        fs::write(
            &guide_path,
            "RXPGuides.RegisterGuide([[\n#name Good\nstep\n.accept 1\n]]);\n\
             RXPGuides.RegisterGuide([[\n#name Bad\nstep\n.accept 1\n", // never closes
        ).unwrap();
        let output_dir = dir.path().join("out");
        fs::create_dir_all(&output_dir).unwrap();

        let client = MemoryQueryClient::new();
        let mut used = HashSet::new();
        let (written, failures) = import_guide(&guide_path, &output_dir, &client, &mut used)
            .await
            .expect("file-level read must still succeed");

        assert_eq!(written, 1, "the well-formed block must still produce output");
        assert_eq!(failures.len(), 1, "the malformed block must be recorded, not silently dropped");
        assert!(fs::read(output_dir.join("Good.json")).is_ok());
    }

    #[tokio::test]
    async fn header_less_blocks_get_distinct_filenames() {
        // CRITICAL 2: two header-less blocks both default to "Imported Guide" and must not
        // silently overwrite each other.
        let dir = tempfile::tempdir().unwrap();
        let guide_path = dir.path().join("bundle.lua");
        fs::write(
            &guide_path,
            "RXPGuides.RegisterGuide([[\nstep\n.accept 1\n]]);\n\
             RXPGuides.RegisterGuide([[\nstep\n.accept 2\n]]);",
        ).unwrap();
        let output_dir = dir.path().join("out");
        fs::create_dir_all(&output_dir).unwrap();

        let client = MemoryQueryClient::new();
        let mut used = HashSet::new();
        let (written, failures) = import_guide(&guide_path, &output_dir, &client, &mut used)
            .await
            .unwrap();

        assert_eq!(written, 2);
        assert!(failures.is_empty());
        assert!(fs::read(output_dir.join("Imported-Guide.json")).is_ok());
        assert!(fs::read(output_dir.join("Imported-Guide-2.json")).is_ok());
    }

    #[tokio::test]
    async fn generated_name_collision_with_literal_name_is_disambiguated() {
        // Defect: two "Foo" blocks generate "Foo" and "Foo-2"; a third block LITERALLY named
        // "Foo-2" must not silently reuse/overwrite the already-generated Foo-2.json.
        let dir = tempfile::tempdir().unwrap();
        let guide_path = dir.path().join("bundle.lua");
        fs::write(
            &guide_path,
            "RXPGuides.RegisterGuide([[\n#name Foo\nstep\n.accept 1\n]]);\n\
             RXPGuides.RegisterGuide([[\n#name Foo\nstep\n.accept 2\n]]);\n\
             RXPGuides.RegisterGuide([[\n#name Foo-2\nstep\n.accept 3\n]]);",
        ).unwrap();
        let output_dir = dir.path().join("out");
        fs::create_dir_all(&output_dir).unwrap();

        let client = MemoryQueryClient::new();
        let mut used = HashSet::new();
        let (written, failures) = import_guide(&guide_path, &output_dir, &client, &mut used)
            .await
            .unwrap();

        assert_eq!(written, 3, "all three blocks must be written, none silently overwritten");
        assert!(failures.is_empty());
        assert!(fs::read(output_dir.join("Foo.json")).is_ok());
        assert!(fs::read(output_dir.join("Foo-2.json")).is_ok());
        assert!(
            fs::read(output_dir.join("Foo-2-2.json")).is_ok(),
            "the literal 'Foo-2' block must not collide with the already-generated Foo-2.json"
        );

        let files_on_disk = fs::read_dir(&output_dir).unwrap().count();
        assert_eq!(files_on_disk, 3, "written count must equal actual files on disk, no silent overwrite");
    }
}