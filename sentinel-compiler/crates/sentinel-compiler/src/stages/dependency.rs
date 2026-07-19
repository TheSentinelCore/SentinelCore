//! Stage 4: Operation Dependency Resolution
//!
//! Builds a directed graph from Requires/UnlocksAfter edges, detects cycles,
//! detects ExcludesWith conflicts, and produces a topological ordering with
//! SoftPrefers / priority / declaration-order tie-breaking.
//!
//! See: docs/adr/008-compilation-pipeline.md §7

use std::collections::{HashMap, HashSet};

use sentinel_schema::enums::DependencyType;
use sentinel_schema::Profile;
use uuid::Uuid;

use crate::diagnostics::{Diagnostic, Severity, Stage};

/// The result of Stage 4 — a linear ordering of Operations.
#[derive(Debug)]
pub struct DependencyOrder {
    /// Operations in compile-time order (by Uuid).
    pub ordered: Vec<Uuid>,
    /// Mapping from Operation ID to its index in the order.
    pub order_map: HashMap<Uuid, usize>,
}

/// DFS colour marker for cycle detection.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Colour {
    White,
    Gray,
    Black,
}

// =========================================================================
// Public entry point
// =========================================================================

/// Stage 4: Build dependency graph, detect cycles, topologically sort.
pub fn resolve_dependencies(profile: &Profile) -> Result<DependencyOrder, Vec<Diagnostic>> {
    let mut diagnostics: Vec<Diagnostic> = Vec::new();

    // Build an index of all operation IDs for existence checks.
    let op_set: HashSet<Uuid> = profile.operations.iter().map(|op| op.id).collect();
    // Declaration order: position in the original `operations` vec.
    let decl_order: HashMap<Uuid, usize> = profile
        .operations
        .iter()
        .enumerate()
        .map(|(i, op)| (op.id, i))
        .collect();

    // ------------------------------------------------------------------
    // 1. Validate that all dependency targets exist (C-4003).
    // ------------------------------------------------------------------
    for op in &profile.operations {
        for dep in &op.dependencies {
            if !op_set.contains(&dep.operation_id) {
                diagnostics.push(
                    Diagnostic::error(
                        "C-4003",
                        Stage::DependencyResolution,
                        format!(
                            "Operation '{}' depends on nonexistent Operation ID: {}",
                            op.name, dep.operation_id
                        ),
                    )
                    .with_entity(format!("Operation '{}'", op.name)),
                );
            }
        }
    }

    // If there are hard errors from existence checks, bail early.
    if diagnostics.iter().any(|d| d.severity == Severity::Error) {
        return Err(diagnostics);
    }

    // ------------------------------------------------------------------
    // 2. Build adjacency list from Requires / UnlocksAfter.
    //    Edge direction: dependency -> dependent (A requires B means B -> A).
    // ------------------------------------------------------------------
    let mut adj: HashMap<Uuid, Vec<Uuid>> = HashMap::new();
    let mut in_degree: HashMap<Uuid, usize> = HashMap::new();
    let mut soft_prefers_to: HashMap<Uuid, Vec<Uuid>> = HashMap::new();

    for op in &profile.operations {
        adj.entry(op.id).or_default();
        in_degree.entry(op.id).or_insert(0);

        for dep in &op.dependencies {
            match dep.relationship {
                DependencyType::Requires | DependencyType::UnlocksAfter => {
                    // dep.operation_id must come before op.id
                    adj.entry(dep.operation_id).or_default().push(op.id);
                    *in_degree.entry(op.id).or_insert(0) += 1;
                }
                DependencyType::SoftPrefers => {
                    soft_prefers_to
                        .entry(dep.operation_id)
                        .or_default()
                        .push(op.id);
                }
                DependencyType::ExcludesWith => {
                    // handled separately below
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // 3. Detect cycles via DFS (white/gray/black colouring).
    // ------------------------------------------------------------------
    let cycle = find_cycle_path(&adj, &op_set);
    if !cycle.is_empty() {
        let names: Vec<String> = cycle
            .iter()
            .map(|id| {
                profile
                    .operations
                    .iter()
                    .find(|op| op.id == *id)
                    .map(|op| format!("'{}'", op.name))
                    .unwrap_or_else(|| format!("{}", id))
            })
            .collect();

        diagnostics.push(
            Diagnostic::error(
                "C-4001",
                Stage::DependencyResolution,
                format!(
                    "Cycle detected in dependency graph: {}",
                    names.join(" → ")
                ),
            )
            .with_fix("Remove or change one of the circular dependency edges"),
        );
        return Err(diagnostics);
    }

    // ------------------------------------------------------------------
    // 4. Detect ExcludesWith conflicts (C-4002).
    // ------------------------------------------------------------------
    detect_excludes_with_conflicts(profile, &mut diagnostics);

    if diagnostics.iter().any(|d| d.severity == Severity::Error) {
        return Err(diagnostics);
    }

    // ------------------------------------------------------------------
    // 5. Topological sort via Kahn's algorithm with tie-breaking.
    // ------------------------------------------------------------------
    let ordered = kahn_sort(&adj, &in_degree, &soft_prefers_to, profile, &decl_order);

    let order_map: HashMap<Uuid, usize> = ordered
        .iter()
        .enumerate()
        .map(|(i, &id)| (id, i))
        .collect();

    Ok(DependencyOrder { ordered, order_map })
}

// =========================================================================
// Kahn's algorithm with tie-breaking
// =========================================================================

fn kahn_sort(
    adj: &HashMap<Uuid, Vec<Uuid>>,
    in_degree: &HashMap<Uuid, usize>,
    soft_prefers_to: &HashMap<Uuid, Vec<Uuid>>,
    profile: &Profile,
    decl_order: &HashMap<Uuid, usize>,
) -> Vec<Uuid> {
    let priority_map: HashMap<Uuid, u32> = profile
        .operations
        .iter()
        .map(|op| (op.id, op.priority))
        .collect();

    let mut in_deg = in_degree.clone();
    let mut ready: Vec<Uuid> = Vec::new();
    let mut result: Vec<Uuid> = Vec::new();

    // Seed with all nodes having in-degree 0.
    for (&id, &d) in &in_deg {
        if d == 0 {
            ready.push(id);
        }
    }
    sort_candidates(&mut ready, soft_prefers_to, &priority_map, decl_order);

    while !ready.is_empty() {
        let node = ready.remove(0);
        result.push(node);

        if let Some(neighbours) = adj.get(&node) {
            for &next in neighbours {
                let deg = in_deg.get_mut(&next).unwrap();
                *deg -= 1;
                if *deg == 0 {
                    ready.push(next);
                }
            }
            // Re-sort ready list after adding new entries.
            sort_candidates(&mut ready, soft_prefers_to, &priority_map, decl_order);
        }
    }

    result
}

/// Sort a list of candidate nodes by tie-breaking rules:
/// 1. Soft-prefers edges (nodes that others soft-prefer go later)
/// 2. Higher priority first
/// 3. Earlier declaration order first
fn sort_candidates(
    candidates: &mut Vec<Uuid>,
    soft_prefers_to: &HashMap<Uuid, Vec<Uuid>>,
    priority_map: &HashMap<Uuid, u32>,
    decl_order: &HashMap<Uuid, usize>,
) {
    // Score: how many candidates soft-prefer this node?
    // A node that is soft-preferred by others should come later.
    let soft_preferred_by: HashMap<Uuid, usize> = {
        let mut score: HashMap<Uuid, usize> = HashMap::new();
        for (&from, targets) in soft_prefers_to {
            for &to in targets {
                if candidates.contains(&from) && candidates.contains(&to) {
                    *score.entry(to).or_insert(0) += 1;
                }
            }
        }
        score
    };

    candidates.sort_by(|a, b| {
        // Lower soft_preferred_by → earlier
        let sa = soft_preferred_by.get(a).unwrap_or(&0);
        let sb = soft_preferred_by.get(b).unwrap_or(&0);
        sa.cmp(sb)
            // Higher priority → earlier
            .then_with(|| {
                let pa = priority_map.get(a).unwrap_or(&100);
                let pb = priority_map.get(b).unwrap_or(&100);
                pb.cmp(pa)
            })
            // Earlier declaration order → earlier
            .then_with(|| {
                let da = decl_order.get(a).unwrap_or(&usize::MAX);
                let db = decl_order.get(b).unwrap_or(&usize::MAX);
                da.cmp(db)
            })
    });
}

// =========================================================================
// Cycle path extraction via DFS
// =========================================================================

/// Find the exact cycle path in the dependency graph.
/// Returns a vec like [A, B, C, A] showing the cycle, or empty if no cycle.
fn find_cycle_path(adj: &HashMap<Uuid, Vec<Uuid>>, all_nodes: &HashSet<Uuid>) -> Vec<Uuid> {
    let mut colour: HashMap<Uuid, Colour> =
        all_nodes.iter().map(|&id| (id, Colour::White)).collect();
    let mut stack: Vec<Uuid> = Vec::new();
    let mut cycle: Vec<Uuid> = Vec::new();

    fn dfs(
        node: Uuid,
        adj: &HashMap<Uuid, Vec<Uuid>>,
        colour: &mut HashMap<Uuid, Colour>,
        stack: &mut Vec<Uuid>,
        cycle: &mut Vec<Uuid>,
    ) -> bool {
        colour.insert(node, Colour::Gray);
        stack.push(node);

        if let Some(neighbours) = adj.get(&node) {
            for &next in neighbours {
                match colour.get(&next) {
                    Some(Colour::Gray) => {
                        // Found cycle — extract path from next to current.
                        if let Some(pos) = stack.iter().position(|&x| x == next) {
                            cycle.extend_from_slice(&stack[pos..]);
                            cycle.push(next); // close the cycle
                        }
                        return true;
                    }
                    Some(Colour::White) => {
                        if dfs(next, adj, colour, stack, cycle) {
                            return true;
                        }
                    }
                    _ => {}
                }
            }
        }

        stack.pop();
        colour.insert(node, Colour::Black);
        false
    }

    let mut sorted_nodes: Vec<Uuid> = all_nodes.iter().copied().collect();
    sorted_nodes.sort_by_key(|id| id.to_string());

    for start in sorted_nodes {
        if *colour.get(&start).unwrap_or(&Colour::White) == Colour::White {
            if dfs(start, adj, &mut colour, &mut stack, &mut cycle) {
                return cycle;
            }
        }
    }

    cycle
}

// =========================================================================
// ExcludesWith conflict detection
// =========================================================================

/// Check if two entry_conditions sets are mutually exclusive based on
/// character eligibility (RaceIs, ClassIs, FactionIs).
fn are_mutually_exclusive(
    a: &[sentinel_schema::Condition],
    b: &[sentinel_schema::Condition],
) -> bool {
    use sentinel_schema::Condition;

    // RaceIs conflict
    let a_races: Vec<_> = a
        .iter()
        .filter_map(|c| match c {
            Condition::RaceIs(r) => Some(*r),
            _ => None,
        })
        .collect();
    let b_races: Vec<_> = b
        .iter()
        .filter_map(|c| match c {
            Condition::RaceIs(r) => Some(*r),
            _ => None,
        })
        .collect();
    if !a_races.is_empty() && !b_races.is_empty() {
        if a_races.iter().any(|ar| b_races.iter().all(|br| ar != br)) {
            return true;
        }
    }

    // FactionIs conflict
    let a_factions: Vec<_> = a
        .iter()
        .filter_map(|c| match c {
            Condition::FactionIs(f) => Some(*f),
            _ => None,
        })
        .collect();
    let b_factions: Vec<_> = b
        .iter()
        .filter_map(|c| match c {
            Condition::FactionIs(f) => Some(*f),
            _ => None,
        })
        .collect();
    if !a_factions.is_empty() && !b_factions.is_empty() {
        if a_factions.iter().any(|af| b_factions.iter().all(|bf| af != bf)) {
            return true;
        }
    }

    // ClassIs conflict
    let a_classes: Vec<_> = a
        .iter()
        .filter_map(|c| match c {
            Condition::ClassIs(cls) => Some(*cls),
            _ => None,
        })
        .collect();
    let b_classes: Vec<_> = b
        .iter()
        .filter_map(|c| match c {
            Condition::ClassIs(cls) => Some(*cls),
            _ => None,
        })
        .collect();
    if !a_classes.is_empty() && !b_classes.is_empty() {
        if a_classes.iter().any(|ac| b_classes.iter().all(|bc| ac != bc)) {
            return true;
        }
    }

    false
}

fn detect_excludes_with_conflicts(
    profile: &Profile,
    diagnostics: &mut Vec<Diagnostic>,
) {
    let op_map: HashMap<Uuid, &sentinel_schema::Operation> =
        profile.operations.iter().map(|op| (op.id, op)).collect();

    let mut seen_pairs: HashSet<(Uuid, Uuid)> = HashSet::new();

    for op in &profile.operations {
        for dep in &op.dependencies {
            if dep.relationship == DependencyType::ExcludesWith {
                let pair = if op.id < dep.operation_id {
                    (op.id, dep.operation_id)
                } else {
                    (dep.operation_id, op.id)
                };
                if seen_pairs.insert(pair) {
                    let a = op_map.get(&op.id);
                    let b = op_map.get(&dep.operation_id);
                    if let (Some(op_a), Some(op_b)) = (a, b) {
                        if !are_mutually_exclusive(&op_a.entry_conditions, &op_b.entry_conditions)
                        {
                            diagnostics.push(
                                Diagnostic::error(
                                    "C-4002",
                                    Stage::DependencyResolution,
                                    format!(
                                        "ExcludesWith conflict between Operations '{}' and '{}' — both are eligible for the same character",
                                        op_a.name, op_b.name
                                    ),
                                )
                                .with_entity(format!("Operation '{}' ↔ '{}'", op_a.name, op_b.name))
                                .with_fix("Add entry_conditions (RaceIs/ClassIs/FactionIs) that make them mutually exclusive"),
                            );
                        }
                    }
                }
            }
        }
    }
}

// =========================================================================
// Tests
// =========================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use sentinel_schema::condition::OperationDependency;
    use sentinel_schema::Operation;

    fn op_with_deps(name: &str, deps: Vec<OperationDependency>) -> Operation {
        let mut op = Operation::new(name);
        op.dependencies = deps;
        op
    }

    fn op_with_deps_and_priority(
        name: &str,
        deps: Vec<OperationDependency>,
        priority: u32,
    ) -> Operation {
        let mut op = Operation::new(name);
        op.dependencies = deps;
        op.priority = priority;
        op
    }

    // -- No dependencies: any order is valid --------------------------------

    #[test]
    fn test_no_dependencies() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![
            Operation::new("A"),
            Operation::new("B"),
            Operation::new("C"),
        ];

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();
        assert_eq!(order.ordered.len(), 3);
        assert_eq!(order.order_map.len(), 3);
    }

    // -- Requires ordering: B before A --------------------------------------

    #[test]
    fn test_requires_ordering() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![
            op_with_deps("A", vec![OperationDependency::requires(id_b)]),
            {
                let mut op = Operation::new("B");
                op.id = id_b;
                op
            },
        ];
        profile.operations[0].id = id_a;

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();

        let idx_b = order.order_map[&id_b];
        let idx_a = order.order_map[&id_a];
        assert!(
            idx_b < idx_a,
            "B ({}) should come before A ({})",
            idx_b,
            idx_a
        );
    }

    // -- Cycle detection ---------------------------------------------------

    #[test]
    fn test_cycle_detection() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.dependencies = vec![OperationDependency::requires(id_b)];

        let mut op_b = Operation::new("B");
        op_b.id = id_b;
        op_b.dependencies = vec![OperationDependency::requires(id_a)];

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_a, op_b];

        let result = resolve_dependencies(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-4001"));
    }

    // -- ExcludesWith: no conflict (race makes them exclusive) --------------

    #[test]
    fn test_excludes_with_no_conflict() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.entry_conditions = vec![sentinel_schema::Condition::RaceIs(
            sentinel_schema::enums::Race::Human,
        )];
        op_a.dependencies = vec![OperationDependency::excludes_with(id_b)];

        let mut op_b = Operation::new("B");
        op_b.id = id_b;
        op_b.entry_conditions = vec![sentinel_schema::Condition::RaceIs(
            sentinel_schema::enums::Race::Dwarf,
        )];

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_a, op_b];

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();
        // Should succeed with no C-4002 in the order (no diagnostics from the order itself).
        assert_eq!(order.ordered.len(), 2);
    }

    // -- ExcludesWith: conflict --------------------------------------------

    #[test]
    fn test_excludes_with_conflict() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.dependencies = vec![OperationDependency::excludes_with(id_b)];

        let mut op_b = Operation::new("B");
        op_b.id = id_b;

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_a, op_b];

        let result = resolve_dependencies(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-4002"));
    }

    // -- SoftPrefers tie-breaking -------------------------------------------

    #[test]
    fn test_soft_prefers_tie_breaking() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.dependencies = vec![OperationDependency::soft_prefers(id_b)];

        let mut op_b = Operation::new("B");
        op_b.id = id_b;

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_a, op_b];

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();
        let idx_b = order.order_map[&id_b];
        let idx_a = order.order_map[&id_a];
        assert!(
            idx_b < idx_a,
            "B ({}) should come before A ({}) due to soft-prefers",
            idx_b,
            idx_a
        );
    }

    // -- Priority tie-breaking ----------------------------------------------

    #[test]
    fn test_priority_tie_breaking() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![
            op_with_deps_and_priority("Low", vec![], 10),
            op_with_deps_and_priority("High", vec![], 200),
            op_with_deps_and_priority("Mid", vec![], 50),
        ];

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();
        let names: Vec<String> = order
            .ordered
            .iter()
            .map(|id| {
                profile
                    .operations
                    .iter()
                    .find(|op| op.id == *id)
                    .unwrap()
                    .name
                    .clone()
            })
            .collect();
        assert_eq!(names[0], "High");
        assert_eq!(names[1], "Mid");
        assert_eq!(names[2], "Low");
    }

    // -- Declaration order stable -------------------------------------------

    #[test]
    fn test_declaration_order_stable() {
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![
            Operation::new("First"),
            Operation::new("Second"),
            Operation::new("Third"),
        ];

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();
        let names: Vec<String> = order
            .ordered
            .iter()
            .map(|id| {
                profile
                    .operations
                    .iter()
                    .find(|op| op.id == *id)
                    .unwrap()
                    .name
                    .clone()
            })
            .collect();
        assert_eq!(names, vec!["First", "Second", "Third"]);
    }

    // -- Dependency on nonexistent Operation --------------------------------

    #[test]
    fn test_dependency_on_nonexistent() {
        let fake_id = Uuid::new_v4();
        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_with_deps(
            "A",
            vec![OperationDependency::requires(fake_id)],
        )];

        let result = resolve_dependencies(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-4003"));
    }

    // -- Chain dependency: C requires B requires A → A, B, C ---------------

    #[test]
    fn test_chain_dependency() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();
        let id_c = Uuid::new_v4();

        let mut op_a = Operation::new("A");
        op_a.id = id_a;

        let mut op_b = Operation::new("B");
        op_b.id = id_b;
        op_b.dependencies = vec![OperationDependency::requires(id_a)];

        let mut op_c = Operation::new("C");
        op_c.id = id_c;
        op_c.dependencies = vec![OperationDependency::requires(id_b)];

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_c, op_b, op_a]; // intentionally reversed

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();

        assert!(order.order_map[&id_a] < order.order_map[&id_b]);
        assert!(order.order_map[&id_b] < order.order_map[&id_c]);
    }

    // -- Empty profile -----------------------------------------------------

    #[test]
    fn test_empty_profile() {
        let profile = Profile::new("Test", "Agent");
        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();
        assert!(order.ordered.is_empty());
        assert!(order.order_map.is_empty());
    }

    // -- UnlocksAfter ordering ---------------------------------------------

    #[test]
    fn test_unlocks_after_ordering() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.dependencies = vec![OperationDependency::unlocks_after(id_b)];

        let mut op_b = Operation::new("B");
        op_b.id = id_b;

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_a, op_b];

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();
        assert!(order.order_map[&id_b] < order.order_map[&id_a]);
    }

    // -- Self-referencing dependency is a cycle ----------------------------

    #[test]
    fn test_self_referencing_cycle() {
        let id_a = Uuid::new_v4();
        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.dependencies = vec![OperationDependency::requires(id_a)];

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_a];

        let result = resolve_dependencies(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-4001"));
    }

    // -- ExcludesWith faction conflict -------------------------------------

    #[test]
    fn test_excludes_with_faction_conflict() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.entry_conditions = vec![sentinel_schema::Condition::FactionIs(
            sentinel_schema::enums::Faction::Alliance,
        )];
        op_a.dependencies = vec![OperationDependency::excludes_with(id_b)];

        let mut op_b = Operation::new("B");
        op_b.id = id_b;
        // No faction restriction → not mutually exclusive → conflict.

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_a, op_b];

        let result = resolve_dependencies(&profile);
        assert!(result.is_err());
        let diags = result.unwrap_err();
        assert!(diags.iter().any(|d| d.code == "C-4002"));
    }

    #[test]
    fn test_excludes_with_faction_no_conflict() {
        let id_a = Uuid::new_v4();
        let id_b = Uuid::new_v4();

        let mut op_a = Operation::new("A");
        op_a.id = id_a;
        op_a.entry_conditions = vec![sentinel_schema::Condition::FactionIs(
            sentinel_schema::enums::Faction::Alliance,
        )];
        op_a.dependencies = vec![OperationDependency::excludes_with(id_b)];

        let mut op_b = Operation::new("B");
        op_b.id = id_b;
        op_b.entry_conditions = vec![sentinel_schema::Condition::FactionIs(
            sentinel_schema::enums::Faction::Horde,
        )];

        let mut profile = Profile::new("Test", "Agent");
        profile.operations = vec![op_a, op_b];

        let result = resolve_dependencies(&profile);
        assert!(result.is_ok());
        let order = result.unwrap();
        assert_eq!(order.ordered.len(), 2);
    }
}
