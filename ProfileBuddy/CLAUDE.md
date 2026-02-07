# CLAUDE.md - ProfileBuddy Project Guide

This file provides guidance to Claude Code when working with the ProfileBuddy codebase.

## Project Overview

ProfileBuddy is a Rust TUI application that generates optimized gathering profiles for GatherBuddy from GatherMate2 addon data.

**Key Components:**
- **pb-core** - Core library: parsing, optimization, profile generation
- **pb-tui** - Terminal UI using ratatui

---

## Build & Run

```bash
cd ProfileBuddy
cargo build --release
cargo run --release
```

### Testing

```bash
cargo test                    # All tests
cargo test -p pb-core         # Core library only
cargo clippy                  # Lint
cargo fmt --check             # Format check
```

---

## Architecture

```
ProfileBuddy/
├── Cargo.toml                # Workspace manifest
├── crates/
│   ├── pb-core/              # Core library
│   │   └── src/
│   │       ├── parser/       # GatherMate2 Lua parser
│   │       ├── optimizer/    # Route algorithms
│   │       ├── generator/    # Profile JSON output
│   │       └── data/         # Static zone/node data
│   └── pb-tui/               # Terminal UI
│       └── src/
│           ├── app.rs        # App state machine
│           ├── ui/           # ratatui widgets
│           └── event.rs      # Input handling
└── docs/                     # Documentation
```

---

## Critical Implementation Details

### GatherMate2 Coordinate Decoding

**CRITICAL**: Coordinates are packed integers in `XXXXYYYY00` format.

```rust
fn decode_coord(packed: u64) -> (f32, f32) {
    let x = (packed / 1_000_000) as f32 / 10000.0;  // Digits 1-4
    let y = ((packed % 1_000_000) / 100) as f32 / 10000.0;  // Digits 5-8
    (x, y)  // Returns normalized 0.0-1.0 map coordinates
}
```

### Coordinate Conversion

GatherMate2 uses normalized map coordinates (0.0-1.0).
GatherBuddy requires WoW world coordinates.

```rust
fn to_world_coords(map_x: f32, map_y: f32, bounds: &ZoneBounds) -> (f32, f32, f32) {
    let world_x = bounds.loc_top + (bounds.loc_bottom - bounds.loc_top) * map_x;
    let world_y = bounds.loc_left + (bounds.loc_right - bounds.loc_left) * map_y;
    (world_x, world_y, bounds.default_z)
}
```

### Zone IDs (UiMapID)

GatherMate2 Era/TBC uses modern UiMapID values:
- 1411 = Durotar
- 1429 = Elwynn Forest
- 1412 = Mulgore

The zone boundary database maps these to world coordinate boundaries.

---

## Route Optimization Algorithms

### TSP (Traveling Salesman Problem) - Default

1. **Nearest Neighbor Heuristic**
   - Start at random node
   - Repeatedly visit nearest unvisited node
   - O(n²) time complexity

2. **2-Opt Improvement**
   - Swap edge pairs if it reduces distance
   - Iterate until no improvement found
   - Typically 5-15% distance reduction

### Cluster Optimization

1. **DBSCAN Clustering**
   - eps = 50 yards (node proximity)
   - min_samples = 3
   - Creates hotspot clusters

2. **Centroid Routing**
   - Calculate cluster centroids
   - TSP between centroids
   - Within cluster: nearest neighbor

### Density-Based Optimization

1. **Kernel Density Estimation**
   - Gaussian kernel, bandwidth = 30 yards
   - Generate density heatmap

2. **Gradient Following**
   - Start at density peak
   - Follow density gradient to next peak
   - Creates organic-feeling routes

---

## Profile Output Format

Generated profiles must match GatherBuddy's expected JSON schema:

```json
{
  "version": "1.0",
  "metadata": {
    "name": "Zone - Nodes",
    "author": "ProfileBuddy",
    "description": "Auto-generated gathering route"
  },
  "requirements": {
    "zone": "Zone Name",
    "map_id": 0,
    "continent_id": 0
  },
  "settings": {
    "loop": true,
    "node_search_radius": 80,
    "waypoint_tolerance": 3.0
  },
  "waypoints": [
    { "id": 1, "x": -9456.2, "y": 64.8, "z": 56.0, "type": "path" },
    { "id": 2, "x": -9502.3, "y": 85.7, "z": 58.1, "type": "hotspot", "radius": 35 }
  ]
}
```

---

## TUI State Machine

```
Start
  │
  ▼
┌─────────────────┐
│ GameVersionSelect│◄──────────────┐
└────────┬────────┘               │
         │ Enter                  │ Esc
         ▼                        │
┌─────────────────┐               │
│   ZoneSelect    │───────────────┤
└────────┬────────┘               │
         │ Enter                  │
         ▼                        │
┌─────────────────┐               │
│   NodeSelect    │───────────────┤
└────────┬────────┘               │
         │ Enter                  │
         ▼                        │
┌─────────────────┐               │
│  AlgorithmConfig│───────────────┤
└────────┬────────┘               │
         │ Enter                  │
         ▼                        │
┌─────────────────┐               │
│    Preview      │───────────────┤
└────────┬────────┘               │
         │ Enter (Generate)       │
         ▼                        │
┌─────────────────┐               │
│    Complete     │───────────────┘
└─────────────────┘
```

---

## Key Files

| File | Purpose |
|------|---------|
| `pb-core/src/parser/lua_parser.rs` | GatherMate2 Lua file parsing |
| `pb-core/src/optimizer/tsp.rs` | TSP route optimization |
| `pb-core/src/generator/profile.rs` | GatherBuddy JSON generation |
| `pb-core/src/data/zones.rs` | Zone boundary database |
| `pb-core/src/data/nodes.rs` | Node ID to name mappings |
| `pb-tui/src/app.rs` | Application state and logic |
| `pb-tui/src/ui/zone_select.rs` | Zone selection widget |

---

## Dependencies

```toml
# Core
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
regex = "1.10"
rand = "0.8"
thiserror = "1.0"

# TUI
ratatui = "0.28"
crossterm = "0.28"
```

---

## Common Tasks

### Adding a New Zone

1. Add entry to `pb-core/src/data/zones.rs` in `ZONE_DATABASE`
2. Ensure UiMapID maps correctly
3. Verify coordinate conversion with known in-game coordinates

### Adding a New Algorithm

1. Create `pb-core/src/optimizer/new_algo.rs`
2. Implement `RouteOptimizer` trait
3. Add variant to `Algorithm` enum
4. Wire up in TUI algorithm selection

### Updating Node Mappings

1. Edit `pb-core/src/data/nodes.rs`
2. Add new entries to `HERB_NODES` or `ORE_NODES`
3. Ensure node_id matches GatherMate2 constant

---

## Do's and Don'ts

### DO
- ✅ Use regex for Lua parsing (simple, fast)
- ✅ Validate generated profiles against GatherBuddy schema
- ✅ Include coordinate jitter for anti-detection
- ✅ Use hotspots for dense node clusters
- ✅ Support both Era and TBC data

### DON'T
- ❌ Use a full Lua VM (overkill for this format)
- ❌ Generate profiles without Z coordinates
- ❌ Hardcode zone boundaries (use database)
- ❌ Skip randomization options
- ❌ Output incompatible JSON structure
- ❌ Use WoW Lua API (this is a standalone Rust application)
