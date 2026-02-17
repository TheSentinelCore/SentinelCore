//! Build script for detour-sys.
//!
//! This script:
//! 1. Compiles the Detour C++ library and our C wrapper
//! 2. Generates Rust FFI bindings using bindgen

use std::env;
use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());

    // Paths to Detour source
    let detour_include = manifest_dir.join("recastnavigation/Detour/Include");
    let detour_source = manifest_dir.join("recastnavigation/Detour/Source");

    // Tell cargo to rerun if these files change
    println!("cargo:rerun-if-changed=wrapper.h");
    println!("cargo:rerun-if-changed=wrapper.cpp");
    println!("cargo:rerun-if-changed=recastnavigation/Detour/Source");
    println!("cargo:rerun-if-changed=recastnavigation/Detour/Include");

    // ==========================================================================
    // Compile Detour C++ library + our wrapper
    // ==========================================================================

    let mut build = cc::Build::new();

    // C++ standard
    build.cpp(true);

    // Use C++17 for modern features
    if cfg!(target_os = "windows") {
        build.flag("/std:c++17");
        build.flag("/EHsc"); // Enable C++ exceptions
    } else {
        build.flag("-std=c++17");
    }

    // CRITICAL: Enable 64-bit poly refs for WoW-scale worlds
    // This must match the dtPolyRef type in wrapper.h (uint64_t)
    build.define("DT_POLYREF64", "1");

    // Include paths
    build.include(&detour_include);
    build.include(&manifest_dir); // For wrapper.h

    // Detour source files
    build.file(detour_source.join("DetourAlloc.cpp"));
    build.file(detour_source.join("DetourAssert.cpp"));
    build.file(detour_source.join("DetourCommon.cpp"));
    build.file(detour_source.join("DetourNavMesh.cpp"));
    build.file(detour_source.join("DetourNavMeshBuilder.cpp"));
    build.file(detour_source.join("DetourNavMeshQuery.cpp"));
    build.file(detour_source.join("DetourNode.cpp"));

    // Our C wrapper
    build.file(manifest_dir.join("wrapper.cpp"));

    // Compile to static library
    build.compile("detour");

    // ==========================================================================
    // Generate Rust bindings with bindgen
    // ==========================================================================

    let bindings = bindgen::Builder::default()
        // Input header
        .header(manifest_dir.join("wrapper.h").to_string_lossy())
        // Include paths for bindgen's clang
        .clang_arg(format!("-I{}", detour_include.display()))
        .clang_arg(format!("-I{}", manifest_dir.display()))
        // Enable 64-bit poly refs
        .clang_arg("-DDT_POLYREF64=1")
        // Generate bindings for these functions
        .allowlist_function("wrapper_.*")
        .allowlist_function("dtStatus.*")
        // Generate bindings for these types
        .allowlist_type("dtNavMesh")
        .allowlist_type("dtNavMeshQuery")
        .allowlist_type("dtQueryFilter")
        .allowlist_type("dtPolyRef")
        .allowlist_type("dtTileRef")
        .allowlist_type("dtStatus")
        .allowlist_type("WrapperNavMeshParams")
        .allowlist_type("RandomFunc")
        // Generate bindings for these constants
        .allowlist_var("DT_.*")
        // Treat opaque types as opaque (we don't need their internals)
        .opaque_type("dtNavMesh")
        .opaque_type("dtNavMeshQuery")
        .opaque_type("dtQueryFilter")
        // Use core instead of std for no_std compatibility
        .use_core()
        // Don't generate layout tests (they can fail across platforms)
        .layout_tests(false)
        // Generate
        .generate()
        .expect("Unable to generate bindings");

    // Write bindings to OUT_DIR
    bindings
        .write_to_file(out_dir.join("bindings.rs"))
        .expect("Couldn't write bindings!");

    // Tell cargo where to find the compiled library
    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=detour");

    // Link C++ standard library
    if cfg!(target_os = "linux") {
        println!("cargo:rustc-link-lib=stdc++");
    } else if cfg!(target_os = "macos") {
        println!("cargo:rustc-link-lib=c++");
    }
    // Windows links automatically via MSVC
}
