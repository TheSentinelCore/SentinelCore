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

use std::path::{Path, PathBuf};
use std::fs;

use sentinel_importer::parse_guide;
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

    for guide_path in &guide_files {
        import_guide(guide_path, &output_dir, &client).await?;
    }

    println!("\nImport complete! {} projects created in {:?}", guide_files.len(), output_dir);
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

async fn import_guide(
    guide_path: &Path,
    output_dir: &Path,
    client: &MemoryQueryClient,
) -> Result<(), Box<dyn std::error::Error>> {
    let source = fs::read_to_string(guide_path)?;

    // Parse the guide using the importer
    let parsed = parse_guide(&source)
        .map_err(|e| format!("Failed to parse {}: {}", guide_path.display(), e))?;

    // Build project with memory client (offline mode - returns NotFound for all lookups)
    let project = sentinel_importer::ProjectBuilder::build(
        &parsed,
        guide_path.to_string_lossy().as_ref(),
        client,
    ).await?;

    // Generate output filename from guide name (extract from header or use file stem)
    let project_name = project.metadata.name.replace(' ', "-");
    let output_path = output_dir.join(format!("{}.json", project_name));

    // Serialize to pretty JSON
    let json = serde_json::to_string_pretty(&project)?;
    fs::write(&output_path, json)?;

    println!("✓ Imported: {:?} → {:?}", guide_path.file_name().unwrap(), output_path.file_name().unwrap());

    // Report unresolved references
    let unresolved_count = project.diagnostics.iter()
        .filter(|d| d.code.starts_with("UNRESOLVED_"))
        .count();
    if unresolved_count > 0 {
        println!("  ({} unresolved references - resolve in editor)", unresolved_count);
    }

    Ok(())
}