//! Sentinel Questing Compiler CLI
//! Compiles Project JSON to Runtime Profile JSON

use std::path::PathBuf;
use std::fs;

use sentinel_compiler::Compiler;

fn main() {
    // Use env args or default paths
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: {} <input_project.json> <output_profile.json>", args[0]);
        eprintln!("  Default: uses sentinel-questing/importer/fixtures/A-1-11-Human.lua");
        std::process::exit(1);
    }

    let input_path = PathBuf::from(&args[1]);
    let output_path = PathBuf::from(&args[2]);

    // Read input
    let project_json = match fs::read_to_string(&input_path) {
        Ok(j) => j,
        Err(e) => {
            eprintln!("Failed to read project: {}", e);
            std::process::exit(1);
        }
    };

    // Parse project (using sentinel-models)
    let project: sentinel_models::authoring::Project = match serde_json::from_str(&project_json) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("Failed to parse project: {}", e);
            std::process::exit(1);
        }
    };

    // Compile to runtime profile
    let profile = match Compiler::compile(&project) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("Compilation failed: {}", e);
            std::process::exit(1);
        }
    };

    // Write output
    let profile_json = match serde_json::to_string_pretty(&profile) {
        Ok(j) => j,
        Err(e) => {
            eprintln!("Failed to serialize profile: {}", e);
            std::process::exit(1);
        }
    };

    if let Err(e) = fs::write(&output_path, profile_json) {
        eprintln!("Failed to write profile: {}", e);
        std::process::exit(1);
    }

    println!("Compiled {} operations to {}", profile.operations.len(), output_path.display());
}