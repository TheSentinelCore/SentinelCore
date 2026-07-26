//! Campaign → [`ExecutionPlan`].
//!
//! Three steps, in order: flatten imports and their override layers into a plain list of graphs,
//! order one graph's nodes topologically, then lower each node's intent through the task registry.
//!
//! **Purity is the defining property** (ADR 09 §5): same intent + same `db_fingerprint` ⇒
//! byte-identical output. Nothing here reads a clock, draws a random number, or iterates a
//! `HashMap`. Node ordering is a deterministic entry-first Kahn traversal with document order as
//! the tie-break; every collection that touches output is a `Vec` or a `BTreeMap`. That is what
//! makes bulk re-resolution a diff instead of a rewrite.
//!
//! Two failure channels, and they are not interchangeable. A [`Diagnostic`] travels *with* a plan
//! and describes something the author can fix. A [`crate::DbError`] replaces the plan entirely and
//! describes a database that could not be read — which is also what keeps purity intact, since a
//! plan whose contents depended on which lookups happened to succeed would differ between two
//! resolves of the same intent against the same fingerprint.

use std::collections::{BTreeMap, BTreeSet};

use sentinel_models::platform::{
    compute_content_hash, Campaign, Edge, ExecutionPlan, Graph, Intent, Node, PlanOperation,
    PlanTransition, PLATFORM_SCHEMA_VERSION,
};
use uuid::Uuid;

use crate::db::{DbResult, ResolverDb};
use crate::diagnostic::{Diagnostic, Severity};
use crate::registry::TaskRegistry;

/// Where imported campaigns are looked up. A campaign names its imports by id (ADR 09a §1.3), so
/// resolution needs somewhere to find them — and the crate must not decide that "somewhere" is a
/// directory, a database, or an HTTP endpoint.
pub trait CampaignLibrary {
    fn campaign(&self, id: Uuid) -> Option<&Campaign>;
}

/// A library with nothing in it. Resolving a campaign that imports against this reports the
/// dangling import rather than silently producing a plan with the imported half missing.
#[derive(Debug, Clone, Copy, Default)]
pub struct NoImports;

impl CampaignLibrary for NoImports {
    fn campaign(&self, _id: Uuid) -> Option<&Campaign> {
        None
    }
}

impl CampaignLibrary for [Campaign] {
    fn campaign(&self, id: Uuid) -> Option<&Campaign> {
        self.iter().find(|campaign| campaign.id == id)
    }
}

impl CampaignLibrary for Vec<Campaign> {
    fn campaign(&self, id: Uuid) -> Option<&Campaign> {
        self.as_slice().campaign(id)
    }
}

static NO_IMPORTS: NoImports = NoImports;

/// Resolve a campaign's first graph with the questing task set and no import library.
///
/// The convenience entry point of ADR 09a §2 W2. Use [`Resolver`] when imports, a different graph,
/// or a different task registry are in play.
pub fn resolve(
    campaign: &Campaign,
    db: &dyn ResolverDb,
) -> DbResult<(ExecutionPlan, Vec<Diagnostic>)> {
    Resolver::new(TaskRegistry::with_questing(), &NO_IMPORTS).resolve(campaign, db)
}

pub struct Resolver<'a> {
    registry: TaskRegistry,
    library: &'a dyn CampaignLibrary,
}

impl<'a> Resolver<'a> {
    pub fn new(registry: TaskRegistry, library: &'a dyn CampaignLibrary) -> Self {
        Self { registry, library }
    }

    pub fn registry(&self) -> &TaskRegistry {
        &self.registry
    }

    /// The campaign's first graph after flattening — imported graphs come before the campaign's
    /// own, so a campaign that only layers overrides onto an import still resolves to the imported
    /// route.
    ///
    /// `Err` means one lookup failed and there is therefore **no plan**, not a plan with a louder
    /// diagnostic. A plan lowered against a half-readable database is structurally complete and
    /// carries a content hash and a fingerprint, so nothing downstream — the compiler, the runtime,
    /// a CI diff — can tell it apart from one resolved against a healthy snapshot. Emitting nothing
    /// is the only outcome that cannot be mistaken for a good one. Everything an author can act on
    /// stays a [`Diagnostic`] alongside a plan, exactly as before.
    pub fn resolve(
        &self,
        campaign: &Campaign,
        db: &dyn ResolverDb,
    ) -> DbResult<(ExecutionPlan, Vec<Diagnostic>)> {
        let (graphs, mut diagnostics) = self.flatten(campaign);
        let Some(graph) = graphs.first() else {
            diagnostics.push(Diagnostic::error(
                "resolver.campaign.no_graph",
                format!("campaign `{}` has no graph to resolve", campaign.name),
            ));
            return Ok((empty_plan(campaign.id, Uuid::nil(), db), diagnostics));
        };
        let (plan, graph_diagnostics) = self.lower_graph(campaign, graph, db)?;
        diagnostics.extend(graph_diagnostics);
        Ok((plan, diagnostics))
    }

    /// One named graph, wherever it came from in the import tree.
    pub fn resolve_graph(
        &self,
        campaign: &Campaign,
        graph_id: Uuid,
        db: &dyn ResolverDb,
    ) -> DbResult<(ExecutionPlan, Vec<Diagnostic>)> {
        let (graphs, mut diagnostics) = self.flatten(campaign);
        let Some(graph) = graphs.iter().find(|graph| graph.id == graph_id) else {
            diagnostics.push(Diagnostic::error(
                "resolver.campaign.no_graph",
                format!("campaign `{}` has no graph `{graph_id}`", campaign.name),
            ));
            return Ok((empty_plan(campaign.id, graph_id, db), diagnostics));
        };
        let (plan, graph_diagnostics) = self.lower_graph(campaign, graph, db)?;
        diagnostics.extend(graph_diagnostics);
        Ok((plan, diagnostics))
    }

    /// Imported graphs (override layers applied, disabled nodes spliced out) followed by the
    /// campaign's own. The imported campaigns themselves are never touched — an override is a
    /// layer, not an edit (ADR 09 §8).
    pub fn flatten(&self, campaign: &Campaign) -> (Vec<Graph>, Vec<Diagnostic>) {
        let mut diagnostics = Vec::new();
        let mut seen = BTreeSet::new();
        let graphs = self.flatten_into(campaign, &mut seen, &mut diagnostics);
        (graphs, diagnostics)
    }

    fn flatten_into(
        &self,
        campaign: &Campaign,
        seen: &mut BTreeSet<Uuid>,
        diagnostics: &mut Vec<Diagnostic>,
    ) -> Vec<Graph> {
        if !seen.insert(campaign.id) {
            diagnostics.push(Diagnostic::error(
                "resolver.import.cycle",
                format!("campaign `{}` is already in its own import chain", campaign.id),
            ));
            return Vec::new();
        }

        let mut graphs = Vec::new();
        for import in &campaign.imports {
            let Some(imported) = self.library.campaign(import.campaign) else {
                diagnostics.push(Diagnostic::error(
                    "resolver.import.unknown_campaign",
                    format!("imported campaign `{}` was not found", import.campaign),
                ));
                continue;
            };

            let mut imported_graphs = self.flatten_into(imported, seen, diagnostics);
            for graph in &mut imported_graphs {
                apply_overrides(graph, import, diagnostics);
                remove_disabled(graph, import, diagnostics);
            }
            graphs.extend(imported_graphs);
        }

        graphs.extend(campaign.graphs.iter().cloned());
        seen.remove(&campaign.id);
        graphs
    }

    fn lower_graph(
        &self,
        campaign: &Campaign,
        graph: &Graph,
        db: &dyn ResolverDb,
    ) -> DbResult<(ExecutionPlan, Vec<Diagnostic>)> {
        let mut diagnostics = Vec::new();
        let order = topological_order(graph, &mut diagnostics);

        let mut index_of: BTreeMap<Uuid, usize> = BTreeMap::new();
        for (position, node_index) in order.iter().enumerate() {
            index_of.insert(graph.nodes[*node_index].id, position);
        }

        let mut operations = Vec::with_capacity(order.len());
        for node_index in &order {
            let node = &graph.nodes[*node_index];
            operations.push(PlanOperation {
                node_id: node.id,
                actions: self.lower_node(node, db, &mut diagnostics)?,
                next: transitions(campaign, graph, node, &index_of, &mut diagnostics),
            });
        }

        let mut plan = ExecutionPlan {
            schema_version: PLATFORM_SCHEMA_VERSION,
            campaign_id: campaign.id,
            graph_id: graph.id,
            db_fingerprint: db.fingerprint().to_string(),
            content_hash: String::new(),
            operations,
        };
        plan.content_hash = compute_content_hash(&plan);
        Ok((plan, diagnostics))
    }

    /// An unknown task type, a failed check, or a lowering that produced nothing all yield an
    /// operation with no actions — never a missing operation. A dropped node would move every
    /// later `to_index` and silently reroute the plan.
    fn lower_node(
        &self,
        node: &Node,
        db: &dyn ResolverDb,
        diagnostics: &mut Vec<Diagnostic>,
    ) -> DbResult<Vec<sentinel_models::runtime::GuardedAction>> {
        let Some(task) = self.registry.get(&node.node_type) else {
            diagnostics.push(
                Diagnostic::error(
                    "resolver.task.unknown",
                    format!("no registered task type `{}`", node.node_type),
                )
                .with_node(node.id),
            );
            return Ok(Vec::new());
        };

        let checks = task.check(&node.intent, db)?;
        let blocked = checks.iter().any(|d| d.severity == Severity::Error);
        diagnostics.extend(checks.into_iter().map(|d| d.with_node(node.id)));
        if blocked {
            // Lowering an intent that already failed its schema would produce a second, less
            // useful report of the same problem — and, worse, a plausible-looking action built
            // from whatever fields happened to parse.
            return Ok(Vec::new());
        }

        let mut lowering = Vec::new();
        // The diagnostics collected so far are dropped with an `Err`. That is deliberate: an
        // author-facing list assembled while the backend was failing describes a database that was
        // never fully read.
        let actions = (task.lower)(&node.intent, db, &mut lowering)?;
        diagnostics.extend(lowering.into_iter().map(|d| d.with_node(node.id)));
        Ok(actions)
    }
}

fn empty_plan(campaign_id: Uuid, graph_id: Uuid, db: &dyn ResolverDb) -> ExecutionPlan {
    let mut plan = ExecutionPlan {
        schema_version: PLATFORM_SCHEMA_VERSION,
        campaign_id,
        graph_id,
        db_fingerprint: db.fingerprint().to_string(),
        content_hash: String::new(),
        operations: Vec::new(),
    };
    plan.content_hash = compute_content_hash(&plan);
    plan
}

// ---------------------------------------------------------------------------
// Import layering
// ---------------------------------------------------------------------------

fn apply_overrides(
    graph: &mut Graph,
    import: &sentinel_models::platform::CampaignImport,
    diagnostics: &mut Vec<Diagnostic>,
) {
    for override_entry in &import.overrides {
        let Some(node) = graph
            .nodes
            .iter_mut()
            .find(|node| node.id == override_entry.node)
        else {
            // Not an error: one import's override may target a node that lives in a sibling graph
            // of the same campaign. It becomes visible only if no graph carries it, which the
            // warning is there to surface.
            diagnostics.push(Diagnostic::warning(
                "resolver.override.unknown_node",
                format!("override targets node `{}`, which this graph does not contain", override_entry.node),
            ));
            continue;
        };
        merge_intent(&mut node.intent, &override_entry.intent);
    }
}

/// A patch, not a replacement (ADR 09a §1.3): only the named fields change, so an override that
/// bumps a kill count does not also erase the target it was counting.
fn merge_intent(target: &mut Intent, patch: &Intent) {
    for (field, value) in &patch.0 {
        target.0.insert(field.clone(), value.clone());
    }
}

/// Disabling a node is how an author skips a quest they already did. The route has to stay
/// connected — a hole in the middle of a linear route strands the runtime on the operation before
/// it, with no successor to advance to.
fn remove_disabled(
    graph: &mut Graph,
    import: &sentinel_models::platform::CampaignImport,
    diagnostics: &mut Vec<Diagnostic>,
) {
    for disabled in &import.disabled_nodes {
        if !graph.nodes.iter().any(|node| node.id == *disabled) {
            continue;
        }

        let incoming: Vec<Edge> = graph
            .edges
            .iter()
            .filter(|edge| edge.to == *disabled)
            .cloned()
            .collect();
        let outgoing: Vec<Edge> = graph
            .edges
            .iter()
            .filter(|edge| edge.from == *disabled)
            .cloned()
            .collect();

        graph
            .edges
            .retain(|edge| edge.from != *disabled && edge.to != *disabled);

        for predecessor in &incoming {
            for successor in &outgoing {
                graph.edges.push(Edge {
                    // Derived, not minted: `Uuid::now_v7()` reads the clock, and a spliced edge id
                    // that changed between two resolves of one campaign would break byte-identity.
                    // Edge ids never reach the ExecutionPlan, so only determinism matters here.
                    id: Uuid::from_u128(predecessor.id.as_u128() ^ successor.id.as_u128()),
                    from: predecessor.from,
                    to: successor.to,
                    guard: predecessor.guard.or(successor.guard),
                });
            }
        }

        if graph.entry_node == *disabled {
            match outgoing.first() {
                Some(successor) => graph.entry_node = successor.to,
                None => diagnostics.push(Diagnostic::warning(
                    "resolver.disabled.entry_node",
                    format!("entry node `{disabled}` was disabled and has no successor"),
                )),
            }
        }

        graph.nodes.retain(|node| node.id != *disabled);
    }
}

// ---------------------------------------------------------------------------
// Ordering
// ---------------------------------------------------------------------------

/// Deterministic entry-first Kahn traversal, returning indices into `graph.nodes`.
///
/// Every node is returned exactly once, even in a cyclic or disconnected graph. Dropping one would
/// silently delete authored work; leaving one out of order is recoverable and reported.
fn topological_order(graph: &Graph, diagnostics: &mut Vec<Diagnostic>) -> Vec<usize> {
    let count = graph.nodes.len();
    let mut index_of: BTreeMap<Uuid, usize> = BTreeMap::new();
    for (index, node) in graph.nodes.iter().enumerate() {
        index_of.insert(node.id, index);
    }

    let mut successors: Vec<Vec<usize>> = vec![Vec::new(); count];
    let mut indegree = vec![0usize; count];
    for edge in &graph.edges {
        let (Some(from), Some(to)) = (index_of.get(&edge.from), index_of.get(&edge.to)) else {
            continue;
        };
        successors[*from].push(*to);
        indegree[*to] += 1;
    }

    let mut visited = vec![false; count];
    let mut order = Vec::with_capacity(count);
    // A `BTreeSet` of node indices, so the tie-break among simultaneously-ready nodes is document
    // order — the one thing an author can see and reason about.
    let mut ready: BTreeSet<usize> = (0..count).filter(|index| indegree[*index] == 0).collect();

    let emit = |index: usize,
                    order: &mut Vec<usize>,
                    visited: &mut Vec<bool>,
                    indegree: &mut Vec<usize>,
                    ready: &mut BTreeSet<usize>| {
        visited[index] = true;
        order.push(index);
        ready.remove(&index);
        for successor in &successors[index] {
            if visited[*successor] {
                continue;
            }
            indegree[*successor] = indegree[*successor].saturating_sub(1);
            if indegree[*successor] == 0 {
                ready.insert(*successor);
            }
        }
    };

    // The graph declares where it starts; starting anywhere else would reorder a loop's operations
    // around an arbitrary node.
    if let Some(entry) = index_of.get(&graph.entry_node).copied() {
        emit(entry, &mut order, &mut visited, &mut indegree, &mut ready);
    }

    while order.len() < count {
        let next = ready
            .iter()
            .copied()
            .find(|index| !visited[*index])
            .or_else(|| (0..count).find(|index| !visited[*index]));
        match next {
            Some(index) => emit(index, &mut order, &mut visited, &mut indegree, &mut ready),
            None => break,
        }
    }

    report_back_edges(graph, &order, &index_of, diagnostics);
    order
}

/// In a valid topological order every edge points forward. A backward edge means the graph is
/// cyclic (a repeatable loop) or its declared entry node has predecessors. Both are legal and both
/// make the order below a traversal rather than a topological sort, so say so.
fn report_back_edges(
    graph: &Graph,
    order: &[usize],
    index_of: &BTreeMap<Uuid, usize>,
    diagnostics: &mut Vec<Diagnostic>,
) {
    let mut position = vec![0usize; graph.nodes.len()];
    for (slot, node_index) in order.iter().enumerate() {
        position[*node_index] = slot;
    }

    let cyclic = graph.edges.iter().any(|edge| {
        match (index_of.get(&edge.from), index_of.get(&edge.to)) {
            (Some(from), Some(to)) => position[*to] <= position[*from],
            _ => false,
        }
    });

    if cyclic {
        diagnostics.push(Diagnostic::warning(
            "resolver.graph.cycle",
            format!(
                "graph `{}` has a backward edge; operations are in entry-first traversal order, not topological order",
                graph.name
            ),
        ));
    }
}

fn transitions(
    campaign: &Campaign,
    graph: &Graph,
    node: &Node,
    index_of: &BTreeMap<Uuid, usize>,
    diagnostics: &mut Vec<Diagnostic>,
) -> Vec<PlanTransition> {
    let mut next = Vec::new();
    for edge in graph.edges.iter().filter(|edge| edge.from == node.id) {
        let Some(to_index) = index_of.get(&edge.to).copied() else {
            diagnostics.push(
                Diagnostic::error(
                    "resolver.edge.dangling",
                    format!("edge points at node `{}`, which is not in this graph", edge.to),
                )
                .with_node(node.id),
            );
            continue;
        };

        if let Some(guard) = edge.guard {
            if campaign.condition(guard).is_none() {
                // The transition is kept anyway: dropping it would rewrite the route's shape, and
                // a plan that still shows the broken guard is one an author can fix.
                diagnostics.push(
                    Diagnostic::error(
                        "resolver.guard.unknown_condition",
                        format!("edge guard `{guard}` names no condition in this campaign"),
                    )
                    .with_node(node.id),
                );
            }
        }

        next.push(PlanTransition {
            to_index,
            guard: edge.guard,
        });
    }
    next
}
