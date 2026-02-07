//! Application state and logic

use anyhow::Result;
use crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use pb_core::{
    Algorithm, GameVersion, HeightValidator, NavBuddyClient, NodeDatabase, OptimizerConfig, Parser,
    Profile, ProfileGenerator, RandomStrategy, Route, RouteWaypoint, ValidationResult,
    ValidatorConfig, WaypointType, ZONE_DATABASE, deduplicate_nodes, identify_hotspots,
};
use std::path::PathBuf;

/// Application screen/state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Screen {
    /// Select game version (Era/TBC)
    GameVersion,
    /// Select zone from available zones
    ZoneSelect,
    /// Select which node types to include
    NodeSelect,
    /// Configure optimization algorithm
    AlgorithmConfig,
    /// Preview the route
    Preview,
    /// Generation complete
    Complete,
}

/// Selection state for a list
#[derive(Debug, Clone)]
pub struct ListState {
    pub selected: usize,
    pub offset: usize,
}

impl Default for ListState {
    fn default() -> Self {
        Self {
            selected: 0,
            offset: 0,
        }
    }
}

impl ListState {
    pub fn next(&mut self, len: usize) {
        if len == 0 {
            return;
        }
        self.selected = (self.selected + 1) % len;
    }

    pub fn prev(&mut self, len: usize) {
        if len == 0 {
            return;
        }
        if self.selected == 0 {
            self.selected = len - 1;
        } else {
            self.selected -= 1;
        }
    }
}

/// Node type selection
#[derive(Debug, Clone)]
pub struct NodeSelection {
    pub node_id: u16,
    pub name: String,
    pub selected: bool,
    pub count: usize,
}

/// Application state
pub struct App {
    /// Current screen
    pub screen: Screen,

    /// Selected game version
    pub game_version: GameVersion,

    /// Parsed node database (populated after game version selection)
    pub database: Option<NodeDatabase>,

    /// Available zones (filtered by game version)
    pub zones: Vec<(u32, String, usize)>, // (zone_id, name, node_count)

    /// Zone list state
    pub zone_list: ListState,

    /// Selected zone ID
    pub selected_zone: Option<u32>,

    /// Available herbs in selected zone
    pub herbs: Vec<NodeSelection>,

    /// Available ores in selected zone
    pub ores: Vec<NodeSelection>,

    /// Node list state (0 = herbs, 1 = ores)
    pub node_list: ListState,

    /// Which list is active (0 = herbs, 1 = ores)
    pub active_node_list: usize,

    /// Selected algorithm
    pub algorithm: Algorithm,

    /// Randomization strategy
    pub randomization: RandomStrategy,

    /// Algorithm list state
    pub algo_list: ListState,

    /// Generated route (after optimization)
    pub route: Option<Route>,

    /// Generated profile
    pub profile: Option<Profile>,

    /// Output path
    pub output_path: Option<PathBuf>,

    /// Status message
    pub status: String,

    /// GatherMate2 data directory
    pub data_dir: PathBuf,

    /// NavBuddy validator configuration
    pub validator_config: ValidatorConfig,

    /// Last validation result
    pub validation_result: Option<ValidationResult>,
}

impl App {
    pub fn new() -> Self {
        // Default data directory - look for GatherMate2_Data in common locations
        let data_dir = Self::find_data_dir();

        // Try to load validator config from file
        let validator_config = Self::load_validator_config().unwrap_or_default();

        Self {
            screen: Screen::GameVersion,
            game_version: GameVersion::Era,
            database: None,
            zones: Vec::new(),
            zone_list: ListState::default(),
            selected_zone: None,
            herbs: Vec::new(),
            ores: Vec::new(),
            node_list: ListState::default(),
            active_node_list: 0,
            algorithm: Algorithm::Tsp,
            randomization: RandomStrategy::RouteVariation,
            algo_list: ListState::default(),
            route: None,
            profile: None,
            output_path: None,
            status: "Select game version".to_string(),
            data_dir,
            validator_config,
            validation_result: None,
        }
    }

    /// Load validator config from validator.json if it exists
    fn load_validator_config() -> Option<ValidatorConfig> {
        if let Ok(content) = std::fs::read_to_string("validator.json") {
            // Need to import serde_json, assuming it's available since pb-core uses it
            // Otherwise we might need to use serde_json via exact path or check Cargo.toml
            // workspace.dependencies has serde_json, check pb-tui/Cargo.toml or if it's in scope
            match serde_json::from_str(&content) {
                Ok(config) => return Some(config),
                Err(e) => eprintln!("Failed to parse validator.json: {}", e),
            }
        }
        None
    }

    /// Find GatherMate2_Data directory
    fn find_data_dir() -> PathBuf {
        // Check common locations
        let candidates = [
            "GatherMate2_Data",
            "../GatherMate2_Data",
            "../../GatherMate2_Data",
        ];

        for path in candidates {
            let p = PathBuf::from(path);
            if p.exists() && p.is_dir() {
                return p;
            }
        }

        // Default to current directory subfolder
        PathBuf::from("GatherMate2_Data")
    }

    /// Handle input event, returns true if should quit
    pub fn handle_event(&mut self, event: Event) -> Result<bool> {
        match event {
            Event::Key(key) => self.handle_key(key),
            _ => Ok(false),
        }
    }

    fn handle_key(&mut self, key: KeyEvent) -> Result<bool> {
        // Only process key press events, not release events
        // Crossterm 0.28+ sends both Press and Release for each keypress
        if key.kind != KeyEventKind::Press {
            return Ok(false);
        }

        // Global keys
        match key.code {
            KeyCode::Char('q') | KeyCode::Char('Q') => return Ok(true),
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => return Ok(true),
            KeyCode::Esc => {
                // Go back to previous screen
                self.go_back();
                return Ok(false);
            }
            _ => {}
        }

        // Screen-specific handling
        match self.screen {
            Screen::GameVersion => self.handle_game_version_key(key),
            Screen::ZoneSelect => self.handle_zone_select_key(key),
            Screen::NodeSelect => self.handle_node_select_key(key),
            Screen::AlgorithmConfig => self.handle_algorithm_key(key),
            Screen::Preview => self.handle_preview_key(key),
            Screen::Complete => self.handle_complete_key(key),
        }
    }

    fn go_back(&mut self) {
        self.screen = match self.screen {
            Screen::GameVersion => Screen::GameVersion, // Can't go back
            Screen::ZoneSelect => Screen::GameVersion,
            Screen::NodeSelect => Screen::ZoneSelect,
            Screen::AlgorithmConfig => Screen::NodeSelect,
            Screen::Preview => Screen::AlgorithmConfig,
            Screen::Complete => Screen::Preview,
        };
        self.update_status();
    }

    fn handle_game_version_key(&mut self, key: KeyEvent) -> Result<bool> {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.game_version = match self.game_version {
                    GameVersion::Era => GameVersion::Tbc,
                    GameVersion::Tbc => GameVersion::Era,
                };
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.game_version = match self.game_version {
                    GameVersion::Era => GameVersion::Tbc,
                    GameVersion::Tbc => GameVersion::Era,
                };
            }
            KeyCode::Enter => {
                self.load_database()?;
                self.screen = Screen::ZoneSelect;
            }
            _ => {}
        }
        self.update_status();
        Ok(false)
    }

    fn handle_zone_select_key(&mut self, key: KeyEvent) -> Result<bool> {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.zone_list.prev(self.zones.len());
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.zone_list.next(self.zones.len());
            }
            KeyCode::Enter => {
                if let Some((zone_id, _, _)) = self.zones.get(self.zone_list.selected) {
                    self.selected_zone = Some(*zone_id);
                    self.load_zone_nodes(*zone_id);
                    self.screen = Screen::NodeSelect;
                }
            }
            _ => {}
        }
        self.update_status();
        Ok(false)
    }

    fn handle_node_select_key(&mut self, key: KeyEvent) -> Result<bool> {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                let len = if self.active_node_list == 0 {
                    self.herbs.len()
                } else {
                    self.ores.len()
                };
                self.node_list.prev(len);
            }
            KeyCode::Down | KeyCode::Char('j') => {
                let len = if self.active_node_list == 0 {
                    self.herbs.len()
                } else {
                    self.ores.len()
                };
                self.node_list.next(len);
            }
            KeyCode::Tab => {
                self.active_node_list = 1 - self.active_node_list;
                self.node_list.selected = 0;
            }
            KeyCode::Char(' ') => {
                // Toggle selection
                let nodes = if self.active_node_list == 0 {
                    &mut self.herbs
                } else {
                    &mut self.ores
                };
                if let Some(node) = nodes.get_mut(self.node_list.selected) {
                    node.selected = !node.selected;
                }
            }
            KeyCode::Char('a') | KeyCode::Char('A') => {
                // Select all in current list
                let nodes = if self.active_node_list == 0 {
                    &mut self.herbs
                } else {
                    &mut self.ores
                };
                let all_selected = nodes.iter().all(|n| n.selected);
                for node in nodes {
                    node.selected = !all_selected;
                }
            }
            KeyCode::Enter => {
                // Check if at least one node is selected
                let has_selection = self.herbs.iter().any(|n| n.selected)
                    || self.ores.iter().any(|n| n.selected);
                if has_selection {
                    self.screen = Screen::AlgorithmConfig;
                } else {
                    self.status = "Select at least one node type!".to_string();
                }
            }
            _ => {}
        }
        self.update_status();
        Ok(false)
    }

    fn handle_algorithm_key(&mut self, key: KeyEvent) -> Result<bool> {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.algo_list.prev(6); // 3 algorithms + 3 randomization options
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.algo_list.next(6);
            }
            KeyCode::Char(' ') | KeyCode::Enter if self.algo_list.selected < 3 => {
                // Select algorithm
                self.algorithm = match self.algo_list.selected {
                    0 => Algorithm::Tsp,
                    1 => Algorithm::Cluster,
                    2 => Algorithm::Density,
                    _ => Algorithm::Tsp,
                };
            }
            KeyCode::Char(' ') | KeyCode::Enter if self.algo_list.selected >= 3 => {
                // Select randomization
                self.randomization = match self.algo_list.selected {
                    3 => RandomStrategy::None,
                    4 => RandomStrategy::RouteVariation,
                    5 => RandomStrategy::Both,
                    _ => RandomStrategy::RouteVariation,
                };
            }
            KeyCode::Enter => {
                // Generate route
                self.generate_route()?;
                self.screen = Screen::Preview;
            }
            KeyCode::Char('g') | KeyCode::Char('G') => {
                // Quick generate
                self.generate_route()?;
                self.screen = Screen::Preview;
            }
            _ => {}
        }
        self.update_status();
        Ok(false)
    }

    fn handle_preview_key(&mut self, key: KeyEvent) -> Result<bool> {
        match key.code {
            KeyCode::Enter | KeyCode::Char('g') | KeyCode::Char('G') => {
                // Save profile
                self.save_profile()?;
                self.screen = Screen::Complete;
            }
            KeyCode::Char('r') | KeyCode::Char('R') => {
                // Regenerate route
                self.generate_route()?;
            }
            _ => {}
        }
        self.update_status();
        Ok(false)
    }

    fn handle_complete_key(&mut self, key: KeyEvent) -> Result<bool> {
        match key.code {
            KeyCode::Enter => {
                // Start over
                self.screen = Screen::GameVersion;
                self.route = None;
                self.profile = None;
            }
            _ => {}
        }
        self.update_status();
        Ok(false)
    }

    fn update_status(&mut self) {
        self.status = match self.screen {
            Screen::GameVersion => "Select game version (Era/TBC)".to_string(),
            Screen::ZoneSelect => format!(
                "{} zones available - Select zone",
                self.zones.len()
            ),
            Screen::NodeSelect => "Select node types (Space to toggle, Tab to switch, A for all)"
                .to_string(),
            Screen::AlgorithmConfig => "Configure algorithm (Enter to generate)".to_string(),
            Screen::Preview => {
                if let Some(route) = &self.route {
                    let validation_info = if let Some(ref result) = self.validation_result {
                        format!(
                            " | Validated: {}, Removed: {}",
                            result.validated,
                            result.total_removed()
                        )
                    } else {
                        String::new()
                    };
                    format!(
                        "Route: {} waypoints, {:.0} yards{} - Enter to save, R to regenerate",
                        route.waypoints.len(),
                        route.total_distance,
                        validation_info
                    )
                } else {
                    "Generating...".to_string()
                }
            }
            Screen::Complete => {
                if let Some(path) = &self.output_path {
                    format!("Saved to: {} - Enter to start over", path.display())
                } else {
                    "Complete!".to_string()
                }
            }
        };
    }

    /// Load GatherMate2 database for selected game version
    fn load_database(&mut self) -> Result<()> {
        let subdir = match self.game_version {
            GameVersion::Era => "Era",
            GameVersion::Tbc => "TBC",
        };

        let path = self.data_dir.join(subdir);

        self.status = format!("Loading from {}...", path.display());

        let parser = Parser::new(self.game_version);
        let db = parser.parse_all(&path)?;

        // Build zone list
        self.zones = db
            .zones_sorted()
            .iter()
            .map(|z| (z.zone_id, z.name.clone(), z.node_count()))
            .collect();

        self.database = Some(db);
        self.zone_list = ListState::default();

        Ok(())
    }

    /// Load nodes for selected zone
    fn load_zone_nodes(&mut self, zone_id: u32) {
        if let Some(db) = &self.database {
            if let Some(zone) = db.get_zone(zone_id) {
                // Group herbs by type
                let mut herb_counts: std::collections::HashMap<u16, (String, usize)> =
                    std::collections::HashMap::new();
                for node in &zone.herbs {
                    let entry = herb_counts
                        .entry(node.node_id)
                        .or_insert_with(|| (node.node_name.clone(), 0));
                    entry.1 += 1;
                }
                self.herbs = herb_counts
                    .into_iter()
                    .map(|(id, (name, count))| NodeSelection {
                        node_id: id,
                        name,
                        selected: true,
                        count,
                    })
                    .collect();
                self.herbs.sort_by(|a, b| a.name.cmp(&b.name));

                // Group ores by type
                let mut ore_counts: std::collections::HashMap<u16, (String, usize)> =
                    std::collections::HashMap::new();
                for node in &zone.ores {
                    let entry = ore_counts
                        .entry(node.node_id)
                        .or_insert_with(|| (node.node_name.clone(), 0));
                    entry.1 += 1;
                }
                self.ores = ore_counts
                    .into_iter()
                    .map(|(id, (name, count))| NodeSelection {
                        node_id: id,
                        name,
                        selected: true,
                        count,
                    })
                    .collect();
                self.ores.sort_by(|a, b| a.name.cmp(&b.name));

                self.node_list = ListState::default();
                self.active_node_list = 0;
            }
        }
    }

    /// Generate optimized route
    fn generate_route(&mut self) -> Result<()> {
        let zone_id = self.selected_zone.ok_or_else(|| anyhow::anyhow!("No zone selected"))?;

        let db = self.database.as_ref().ok_or_else(|| anyhow::anyhow!("No database loaded"))?;

        let zone = db
            .get_zone(zone_id)
            .ok_or_else(|| anyhow::anyhow!("Zone not found"))?;

        // Filter nodes based on selection
        let selected_herb_ids: std::collections::HashSet<_> = self
            .herbs
            .iter()
            .filter(|n| n.selected)
            .map(|n| n.node_id)
            .collect();

        let selected_ore_ids: std::collections::HashSet<_> = self
            .ores
            .iter()
            .filter(|n| n.selected)
            .map(|n| n.node_id)
            .collect();

        let nodes: Vec<_> = zone
            .all_nodes()
            .filter(|n| {
                selected_herb_ids.contains(&n.node_id) || selected_ore_ids.contains(&n.node_id)
            })
            .cloned()
            .collect();

        if nodes.is_empty() {
            return Err(anyhow::anyhow!("No nodes match selection"));
        }

        // Deduplicate near-duplicate spawn points (GatherMate2 crowd-sourced data)
        let original_count = nodes.len();
        let mut nodes = deduplicate_nodes(&nodes, 5.0);
        if nodes.len() < original_count {
            self.status = format!(
                "Deduplicated: {} → {} nodes",
                original_count,
                nodes.len()
            );
        }

        // Filter out nodes in exclusion zones (e.g., Stormwind within Elwynn Forest)
        if let Some(bounds) = ZONE_DATABASE.iter().find(|z| z.ui_map_id == zone_id) {
            if !bounds.exclusion_zones.is_empty() {
                let before = nodes.len();
                nodes.retain(|n| {
                    !bounds.exclusion_zones.iter().any(|ez| ez.contains(n.world_x, n.world_y))
                });
                let excluded = before - nodes.len();
                if excluded > 0 {
                    let zone_names: Vec<_> = bounds.exclusion_zones.iter().map(|ez| ez.name).collect();
                    self.status = format!(
                        "Excluded {} nodes in {}",
                        excluded,
                        zone_names.join(", ")
                    );
                }
            }
        }

        // Validate nodes via NavBuddy if enabled
        self.validation_result = None;
        if self.validator_config.enabled {
            // Get zone bounds for map_id and default_z
            let zone_bounds = ZONE_DATABASE.iter().find(|z| z.ui_map_id == zone_id);

            if let Some(bounds) = zone_bounds {
                let map_id = bounds.map_id;
                let default_z = bounds.default_z;

                self.status = format!("Validating {} nodes via NavBuddy...", nodes.len());

                match HeightValidator::new(&self.validator_config) {
                    Ok(validator) => {
                        let result = validator.validate_nodes(map_id, &mut nodes, default_z);
                        self.status = format!(
                            "Validated: {} | Removed: {} (navmesh) + {} (caves) + {} (unreachable)",
                            result.validated,
                            result.removed_not_on_navmesh,
                            result.removed_underground,
                            result.removed_unreachable
                        );
                        self.validation_result = Some(result);
                    }
                    Err(e) => {
                        if self.validator_config.fallback_on_error {
                            self.status = format!("NavBuddy unavailable, using default Z: {}", e);
                        } else {
                            return Err(anyhow::anyhow!("NavBuddy validation failed: {}", e));
                        }
                    }
                }
            }
        }

        if nodes.is_empty() {
            return Err(anyhow::anyhow!("No valid nodes after validation"));
        }

        // Try NavBuddy TSP for navmesh-aware route ordering
        let mut used_navbuddy_tsp = false;
        if self.validator_config.enabled {
            if let Some(bounds) = ZONE_DATABASE.iter().find(|z| z.ui_map_id == zone_id) {
                let map_id = bounds.map_id;

                // Identify hotspot clusters
                let node_refs: Vec<&_> = nodes.iter().collect();
                let clusters = identify_hotspots(&node_refs, 50.0, 3);

                // Build point list: one centroid per cluster + each non-cluster node
                let clustered_node_ids: std::collections::HashSet<u64> = clusters
                    .iter()
                    .flat_map(|c| c.node_ids.iter().copied())
                    .collect();

                struct TspPoint {
                    x: f32,
                    y: f32,
                    z: f32,
                    cluster: Option<usize>,
                }

                let mut tsp_points: Vec<TspPoint> = Vec::new();

                for (idx, cluster) in clusters.iter().enumerate() {
                    tsp_points.push(TspPoint {
                        x: cluster.center_x,
                        y: cluster.center_y,
                        z: cluster.center_z,
                        cluster: Some(idx),
                    });
                }

                for node in &nodes {
                    if !clustered_node_ids.contains(&node.id) {
                        tsp_points.push(TspPoint {
                            x: node.world_x,
                            y: node.world_y,
                            z: node.world_z,
                            cluster: None,
                        });
                    }
                }

                let individual_count = tsp_points.len() - clusters.len();
                self.status = format!(
                    "Route points: {} clusters + {} individual = {} total ({} nodes)",
                    clusters.len(),
                    individual_count,
                    tsp_points.len(),
                    nodes.len()
                );

                if tsp_points.len() <= 30 {
                    self.status = format!(
                        "Optimizing route via NavBuddy TSP ({} points: {} clusters + {} individual)...",
                        tsp_points.len(),
                        clusters.len(),
                        individual_count
                    );

                    match NavBuddyClient::new(
                        &self.validator_config.navbuddy_url,
                        self.validator_config.timeout_ms,
                    ) {
                        Ok(client) => {
                            let points: Vec<(f32, f32, f32)> =
                                tsp_points.iter().map(|p| (p.x, p.y, p.z)).collect();

                            match client.path_tsp(map_id, &points, true) {
                                Ok(tsp_result) if tsp_result.success => {
                                    let mut waypoints = Vec::new();
                                    for &visit_idx in &tsp_result.visit_order {
                                        let point = &tsp_points[visit_idx];
                                        if let Some(cluster_idx) = point.cluster {
                                            let cluster = &clusters[cluster_idx];
                                            waypoints.push(RouteWaypoint {
                                                x: cluster.center_x,
                                                y: cluster.center_y,
                                                z: cluster.center_z,
                                                waypoint_type: WaypointType::Hotspot {
                                                    radius: cluster.radius as u32,
                                                },
                                                source_node_id: None,
                                                note: Some(format!(
                                                    "{} nodes",
                                                    cluster.node_count
                                                )),
                                            });
                                        } else {
                                            waypoints.push(RouteWaypoint {
                                                x: point.x,
                                                y: point.y,
                                                z: point.z,
                                                waypoint_type: WaypointType::Path,
                                                source_node_id: None,
                                                note: None,
                                            });
                                        }
                                    }

                                    let route = Route {
                                        waypoints,
                                        total_distance: tsp_result.total_distance,
                                        hotspots: clusters,
                                        algorithm: Algorithm::Tsp,
                                        randomized: false,
                                        source_nodes: nodes.clone(),
                                    };
                                    self.route = Some(route);
                                    self.status = format!(
                                        "NavBuddy TSP route: {} waypoints, {:.0} yards",
                                        tsp_result.visit_order.len(),
                                        tsp_result.total_distance
                                    );
                                    used_navbuddy_tsp = true;
                                }
                                Ok(_) => {
                                    self.status = "NavBuddy TSP returned failure, falling back to built-in optimizer".into();
                                }
                                Err(e) => {
                                    self.status =
                                        format!("NavBuddy TSP failed: {}, falling back", e);
                                }
                            }
                        }
                        Err(e) => {
                            self.status =
                                format!("NavBuddy unavailable for TSP: {}, falling back", e);
                        }
                    }
                }
            }
        }

        // Fallback: built-in optimizer
        if !used_navbuddy_tsp {
            let optimizer = pb_core::create_optimizer(self.algorithm);
            let config = OptimizerConfig {
                algorithm: self.algorithm,
                randomization: self.randomization,
                ..Default::default()
            };
            let route = optimizer.optimize(&nodes, &config);
            self.route = Some(route);
        }

        Ok(())
    }

    /// Save profile to file
    fn save_profile(&mut self) -> Result<()> {
        let route = self.route.as_ref().ok_or_else(|| anyhow::anyhow!("No route generated"))?;

        let zone_id = self.selected_zone.ok_or_else(|| anyhow::anyhow!("No zone selected"))?;

        let db = self.database.as_ref().ok_or_else(|| anyhow::anyhow!("No database loaded"))?;

        let zone = db
            .get_zone(zone_id)
            .ok_or_else(|| anyhow::anyhow!("Zone not found"))?;

        // Generate profile
        let generator = ProfileGenerator::new();
        let profile = generator.generate(route, &zone.name)?;

        // Save to file
        let timestamp = chrono::Local::now().format("%Y%m%d_%H%M%S");
        let filename = format!(
            "{}_{}.json",
            zone.name.to_lowercase().replace(' ', "_"),
            timestamp
        );

        // Create output directory
        let output_dir = PathBuf::from("../../scripts_data/gatherbuddy/profiles");
        std::fs::create_dir_all(&output_dir)?;

        let output_path = output_dir.join(&filename);
        generator.write_to_file(&profile, &output_path)?;

        self.profile = Some(profile);
        self.output_path = Some(output_path);

        Ok(())
    }
}

impl Default for App {
    fn default() -> Self {
        Self::new()
    }
}
