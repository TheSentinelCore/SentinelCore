//! Batch importer for RestedXP guides into Sentinel Questing projects.
//!
//! Usage:
//!   cargo run -p sentinel-editor --bin import-guides -- <guides_dir> <output_dir> [query_url]
//!
//! Example (live QueryServer resolution, CL3):
//!   cargo run -p sentinel-editor --bin import-guides -- \
//!     "../sentinel/docs/adr/restedxp guides" ".questing/projects"
//!
//! By default this importer resolves NPC/quest/object references against a live
//! `SentinelQueryServer` at `http://127.0.0.1:3030` (overridable via the `SENTINEL_QUERY_URL` env
//! var or an optional third positional argument). Unresolved references (e.g. no server running,
//! or an entity genuinely absent from the DB) still surface as diagnostic warnings in the output
//! project - resolve them in the editor.
//!
//! Each guide file may bundle multiple `RegisterGuide([[ ... ]])` blocks (IF6, e.g. `The
//! Burning Crusade.lua`: 253 blocks in one file) — one Project JSON is written per guide block,
//! not one per file.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::fs;

use sentinel_importer::parse_guide_bundle;
use sentinel_models::authoring::Project;
use sentinel_queryclient::{HttpQueryClient, QueryClient};

const DEFAULT_QUERY_URL: &str = "http://127.0.0.1:3030";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 || args.len() > 4 {
        eprintln!("Usage: import-guides <guides_dir> <output_dir> [query_url]");
        std::process::exit(1);
    }

    let guides_dir = PathBuf::from(&args[1]);
    let output_dir: PathBuf = args[2].clone().into();
    let query_url = args
        .get(3)
        .cloned()
        .or_else(|| std::env::var("SENTINEL_QUERY_URL").ok())
        .unwrap_or_else(|| DEFAULT_QUERY_URL.to_string());

    // Ensure output directory exists
    fs::create_dir_all(&output_dir)?;

    // Find all .lua guide files in the source directory
    let guide_files = find_guide_files(&guides_dir)?;

    if guide_files.is_empty() {
        eprintln!("No .lua guide files found in {:?}", guides_dir);
        std::process::exit(1);
    }

    println!("Found {} guide files to import", guide_files.len());
    println!("Resolving references against QueryServer at {query_url}");

    // Live QueryServer resolution (CL3): NPC/quest/object references resolve to concrete
    // entries/coordinates instead of the empty offline MemoryQueryClient. References that remain
    // unresolved after a live lookup still surface as diagnostics, never as silently zeroed
    // defaults (per compiler-condition-lowering spec, "Resolution Against a Live QueryServer").
    let client = HttpQueryClient::new(query_url);

    let (built_projects, all_failures) = run_import(&guide_files, &output_dir, &client).await;
    let total_projects = built_projects.len();

    if !all_failures.is_empty() {
        eprintln!("\n{} block(s) failed to import:", all_failures.len());
        for failure in &all_failures {
            eprintln!("  ✗ {failure}");
        }
    }

    // CL5: corpus-wide coverage report alongside the regenerated projects.
    let coverage = sentinel_importer::CoverageReport::from_projects(&built_projects);
    let coverage_path = output_dir.join("coverage_report.json");
    match serde_json::to_string_pretty(&coverage) {
        Ok(json) => {
            if let Err(e) = fs::write(&coverage_path, json) {
                eprintln!("  (failed to write {:?}: {e})", coverage_path);
            }
        }
        Err(e) => eprintln!("  (failed to serialize coverage report: {e})"),
    }
    println!("\n{}", coverage.text_summary());

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

/// Runs the import loop across every guide file. A file-level failure (missing file, permission
/// denied, unreadable for any other reason) is recorded as a failure and does NOT abort the
/// remaining files in the batch — matching `import_guide`'s own per-block isolation contract, one
/// level up (file level, not just block level). Also seeds filename disambiguation from any
/// `.json` files already present in `output_dir`, so re-running the importer into the same
/// directory disambiguates instead of silently overwriting prior output (F9).
async fn run_import(
    guide_files: &[PathBuf],
    output_dir: &Path,
    client: &dyn QueryClient,
) -> (Vec<Project>, Vec<String>) {
    // Tracked across the WHOLE run (not per guide file): header-less blocks from different
    // files can collide on the same default name just as easily as two blocks in one bundle
    // (CRITICAL 2 fix), and a re-run must not collide with a PRIOR run's output either.
    let mut used_filenames = seed_used_filenames_from_existing_output(output_dir);
    let mut built_projects: Vec<Project> = Vec::new();
    let mut all_failures: Vec<String> = Vec::new();
    for guide_path in guide_files {
        match import_guide(guide_path, output_dir, client, &mut used_filenames).await {
            Ok((projects, failures)) => {
                built_projects.extend(projects);
                all_failures.extend(failures);
            }
            Err(e) => {
                let msg = format!("{}: {e}", guide_path.display());
                eprintln!("✗ {msg}");
                all_failures.push(msg);
            }
        }
    }
    (built_projects, all_failures)
}

/// Seeds `used_filenames` with the stem of every `.json` file already present in `output_dir`
/// (F9): without this, re-running the importer against the same output directory would silently
/// overwrite previous output instead of disambiguating with `-2`, `-3`, ... Best-effort: an
/// unreadable/missing `output_dir` (shouldn't happen — `main` creates it first) just yields no
/// seeded names rather than failing the run.
fn seed_used_filenames_from_existing_output(output_dir: &Path) -> HashSet<String> {
    let mut used = HashSet::new();
    if let Ok(entries) = fs::read_dir(output_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|e| e == "json") {
                if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                    used.insert(stem.to_string());
                }
            }
        }
    }
    used
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
    // fs::read_dir order is unspecified; sort so batch imports are reproducible — the
    // guide-file order decides which of two same-named blocks wins the base filename vs `-2`.
    files.sort();
    Ok(files)
}

/// Sanitizes a candidate filename stem (typically derived from a guide's `#name` header) so it
/// can never escape `output_dir` — a malicious/malformed header like `../../evil` or a bare `..`
/// must not be able to write outside the intended directory. Replaces path separators (`/` and
/// `\`, for cross-platform safety) and any residual `..` traversal sequences with `_`, then strips
/// leading dots so the result can't resolve to a hidden file or a parent-directory reference.
fn sanitize_filename_stem(stem: &str) -> String {
    let no_separators: String = stem
        .chars()
        .map(|c| if c == '/' || c == '\\' { '_' } else { c })
        .collect();
    let no_traversal = no_separators.replace("..", "_");
    let trimmed = no_traversal.trim_start_matches('.');
    if trimmed.is_empty() {
        "unnamed".to_string()
    } else {
        trimmed.to_string()
    }
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
/// Returns the projects actually written plus any recorded failure messages.
async fn import_guide(
    guide_path: &Path,
    output_dir: &Path,
    client: &dyn QueryClient,
    used_filenames: &mut HashSet<String>,
) -> Result<(Vec<Project>, Vec<String>), Box<dyn std::error::Error>> {
    let source = fs::read_to_string(guide_path)?;

    let mut written = Vec::new();
    let mut failures = Vec::new();

    for (block_idx, result) in parse_guide_bundle(&source).into_iter().enumerate() {
        let outcome: Result<Project, String> = async {
            let parsed = result.map_err(|e| e.to_string())?;
            let project = sentinel_importer::ProjectBuilder::build(
                &parsed,
                guide_path.to_string_lossy().as_ref(),
                client,
            ).await.map_err(|e| e.to_string())?;

            let raw_stem = project.metadata.name.replace(' ', "-");
            let safe_stem = sanitize_filename_stem(&raw_stem);
            let stem = dedupe_filename(used_filenames, &safe_stem);
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
            Ok(project)
        }.await;

        match outcome {
            Ok(project) => written.push(project),
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
    use sentinel_queryclient::MemoryQueryClient;

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

        assert_eq!(written.len(), 1, "the well-formed block must still produce output");
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

        assert_eq!(written.len(), 2);
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

        assert_eq!(written.len(), 3, "all three blocks must be written, none silently overwritten");
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

    #[test]
    fn find_guide_files_is_deterministically_sorted() {
        // Batch import must be reproducible regardless of the filesystem's directory
        // enumeration order: when two blocks (across different guide files) sanitize to the
        // same project name, which one wins the base filename vs `-2` is decided purely by
        // guide-file processing order. `fs::read_dir` yields entries in an unspecified order,
        // so the order must be sorted to be stable across machines and runs.
        let dir = tempfile::tempdir().unwrap();
        for name in ["c.lua", "a.lua", "b.lua"] {
            fs::write(dir.path().join(name), "RXPGuides.RegisterGuide([[\n#name X\n]])").unwrap();
        }
        // Non-.lua files must be excluded regardless.
        fs::write(dir.path().join("notes.txt"), "x").unwrap();

        let files = find_guide_files(dir.path()).unwrap();
        let names: Vec<String> = files
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            names,
            vec!["a.lua".to_string(), "b.lua".to_string(), "c.lua".to_string()],
            "guide files must be processed in a stable, sorted order"
        );
    }

    #[tokio::test]
    async fn path_traversal_name_is_sanitized_and_stays_inside_output_dir() {
        // F9: a malicious/malformed `#name` header (e.g. from a hand-edited or untrusted guide
        // file) must never let the written project escape `output_dir` via `..` or a path
        // separator.
        let dir = tempfile::tempdir().unwrap();
        let guide_path = dir.path().join("bundle.lua");
        fs::write(
            &guide_path,
            "RXPGuides.RegisterGuide([[\n#name ../evil\nstep\n.accept 1\n]]);",
        ).unwrap();
        let output_dir = dir.path().join("out");
        fs::create_dir_all(&output_dir).unwrap();

        let client = MemoryQueryClient::new();
        let mut used = HashSet::new();
        let (written, failures) = import_guide(&guide_path, &output_dir, &client, &mut used)
            .await
            .unwrap();

        assert_eq!(written.len(), 1);
        assert!(failures.is_empty());

        // Nothing must have escaped into the tempdir root (one level above output_dir).
        assert!(
            !dir.path().join("evil.json").exists(),
            "sanitized stem must not resolve to a path outside output_dir"
        );
        // Exactly one file must land INSIDE output_dir.
        let entries: Vec<_> = fs::read_dir(&output_dir).unwrap().collect();
        assert_eq!(entries.len(), 1, "the sanitized project must be written inside output_dir");
    }

    #[tokio::test]
    async fn unreadable_file_is_recorded_as_a_failure_and_does_not_abort_remaining_files() {
        // F9: a file-level read failure (missing file, permission denied, etc.) previously
        // propagated via `?` straight out of `main`, aborting the WHOLE run — later guide files
        // in the batch were never even attempted, and the final summary never printed.
        let dir = tempfile::tempdir().unwrap();
        let good_path = dir.path().join("good.lua");
        fs::write(
            &good_path,
            "RXPGuides.RegisterGuide([[\n#name Good\nstep\n.accept 1\n]]);",
        ).unwrap();
        let missing_path = dir.path().join("missing.lua"); // deliberately never created

        let output_dir = dir.path().join("out");
        fs::create_dir_all(&output_dir).unwrap();
        let client = MemoryQueryClient::new();

        let (written, failures) = run_import(
            &[missing_path.clone(), good_path.clone()],
            &output_dir,
            &client,
        ).await;

        assert_eq!(written.len(), 1, "the readable file must still import despite an earlier unreadable one");
        assert_eq!(failures.len(), 1, "the unreadable file must be recorded as a failure, not silently swallowed");
        assert!(failures[0].contains(&missing_path.display().to_string()));
        assert!(fs::read(output_dir.join("Good.json")).is_ok());
    }

    #[tokio::test]
    async fn rerunning_into_the_same_output_dir_disambiguates_instead_of_overwriting() {
        // F9: `used_filenames` was previously fresh (empty) on every invocation, so re-running
        // the importer against an output directory that already holds a prior run's output would
        // silently overwrite it instead of disambiguating like an in-run collision would.
        let dir = tempfile::tempdir().unwrap();
        let guide_path = dir.path().join("bundle.lua");
        fs::write(
            &guide_path,
            "RXPGuides.RegisterGuide([[\n#name Foo\nstep\n.accept 1\n]]);",
        ).unwrap();
        let output_dir = dir.path().join("out");
        fs::create_dir_all(&output_dir).unwrap();
        let client = MemoryQueryClient::new();

        // First invocation.
        run_import(&[guide_path.clone()], &output_dir, &client).await;
        assert!(fs::read(output_dir.join("Foo.json")).is_ok());

        // Second invocation, simulating a re-run of the binary against the same output_dir.
        run_import(&[guide_path.clone()], &output_dir, &client).await;

        assert!(fs::read(output_dir.join("Foo.json")).is_ok(), "first run's output must survive a re-run");
        assert!(
            fs::read(output_dir.join("Foo-2.json")).is_ok(),
            "a re-run must disambiguate as Foo-2, not silently overwrite Foo.json from the prior run"
        );
    }
}