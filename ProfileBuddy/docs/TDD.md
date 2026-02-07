# ProfileBuddy - Technical Design Document

## System Architecture

### High-Level Design

```
┌──────────────────────────────────────────────────────────────────┐
│                         ProfileBuddy                             │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    pb-tui (Binary Crate)                    │ │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌─────────────┐  │ │
│  │  │  App      │ │  Events   │ │  UI       │ │  Rendering  │  │ │
│  │  │  State    │ │  Handler  │ │  Widgets  │ │  Loop       │  │ │
│  │  └───────────┘ └───────────┘ └───────────┘ └─────────────┘  │ │
│  └──────────────────────────────┬──────────────────────────────┘ │
│                                 │                                │
│  ┌──────────────────────────────▼──────────────────────────────┐ │
│  │                    pb-core (Library Crate)                  │ │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌─────────────┐  │ │
│  │  │  Parser   │ │ Optimizer │ │ Generator │ │    Data     │  │ │
│  │  │  Module   │ │  Module   │ │  Module   │ │   Module    │  │ │
│  │  └───────────┘ └───────────┘ └───────────┘ └─────────────┘  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
            ┌───────────────┐         ┌───────────────┐
            │ GatherMate2   │         │ Zone Bounds   │
            │ Data Files    │         │ Database      │
            └───────────────┘         └───────────────┘
```

### Module Responsibilities

#### pb-core

| Module | Responsibility |
|--------|----------------|
| `parser` | Parse GatherMate2 Lua files, decode coordinates |
| `optimizer` | Route optimization algorithms (TSP, Cluster, Density) |
| `generator` | Create GatherBuddy JSON profiles |
| `data` | Static data (zone bounds, node ID mappings) |

#### pb-tui

| Module | Responsibility |
|--------|----------------|
| `app` | Application state machine |
| `ui` | ratatui widget rendering |
| `event` | Keyboard/mouse input handling |

### Data Flow

```
GatherMate2_Data/*.lua
         │
         ▼
    ┌─────────┐
    │ Parser  │ ──► Vec<RawNode>
    └─────────┘
         │
         ▼
    ┌─────────┐
    │ Decoder │ ──► Vec<DecodedNode>
    └─────────┘
         │
    User Selection (zone, nodes, algorithm)
         │
         ▼
    ┌───────────┐
    │ Optimizer │ ──► OptimizedRoute
    └───────────┘
         │
         ▼
    ┌───────────┐
    │ Generator │ ──► Profile JSON
    └───────────┘
         │
         ▼
    scripts_data/gatherbuddy/profiles/*.json
```

## Component Design

### Parser Module

```rust
// parser/mod.rs
pub struct Parser {
    game_version: GameVersion,
}

impl Parser {
    pub fn parse_herbs(&self, path: &Path) -> Result<Vec<RawNode>>;
    pub fn parse_ores(&self, path: &Path) -> Result<Vec<RawNode>>;
    pub fn parse_all(&self, data_dir: &Path) -> Result<NodeDatabase>;
}

// Regex patterns for Lua table parsing
const ZONE_PATTERN: &str = r"\[(\d+)\]\s*=\s*\{";
const NODE_PATTERN: &str = r"\[(\d+)\]\s*=\s*(\d+)";
```

### Optimizer Module

```rust
// optimizer/mod.rs
pub trait RouteOptimizer {
    fn optimize(&self, nodes: &[DecodedNode], config: &OptimizerConfig) -> Route;
    fn algorithm(&self) -> Algorithm;
}

pub struct TspOptimizer;      // Nearest neighbor + 2-opt
pub struct ClusterOptimizer;  // DBSCAN + centroid routing
pub struct DensityOptimizer;  // KDE-based path following

// optimizer/tsp.rs
impl RouteOptimizer for TspOptimizer {
    fn optimize(&self, nodes: &[DecodedNode], config: &OptimizerConfig) -> Route {
        let route = self.nearest_neighbor(nodes);
        self.two_opt_improve(route, config.max_iterations)
    }
}
```

### Generator Module

```rust
// generator/profile.rs
pub struct ProfileGenerator {
    config: GeneratorConfig,
}

impl ProfileGenerator {
    pub fn generate(&self, route: &Route, zone_name: &str) -> Result<Profile>;
    pub fn to_json(&self, profile: &Profile) -> Result<String>;
    pub fn write_to_file(&self, profile: &Profile, path: &Path) -> Result<()>;
}
```

## Algorithm Details

### TSP Optimization (Default)

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

## Error Handling

```rust
#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("Failed to parse GatherMate2 data: {0}")]
    ParseError(String),

    #[error("Zone not found: {zone_id} ({zone_name})")]
    ZoneNotFound { zone_id: u32, zone_name: String },

    #[error("No nodes found for selection: {0}")]
    NoNodesFound(String),

    #[error("Failed to write profile: {0}")]
    IoError(#[from] std::io::Error),
}
```

## Testing Strategy

| Test Type | Coverage Target | Tools |
|-----------|-----------------|-------|
| Unit Tests | >80% | cargo test |
| Integration Tests | Critical paths | cargo test --test |
| Validation | Profile format | JSON Schema |
| Manual | TUI interaction | Human testing |

## Performance Considerations

- **Parsing**: Stream Lua files, don't load entire 1.4MB into memory at once
- **Optimization**: Cap TSP 2-opt iterations based on node count
- **UI**: Only render visible list items (virtualized list)
