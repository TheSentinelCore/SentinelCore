# Domain Documentation Layout

## Layout: Single-Context

This repository uses a single bounded context for domain documentation.

## Files

| Path | Purpose |
|------|---------|
| `sentinel/CONTEXT.md` | Ubiquitous language glossary (term → definition → aliases-to-avoid + relationships + example dialogue) |
| `sentinel/docs/adr/` | Architecture Decision Records (MADR/Nygard style) |

## Consumer Rules

Engineering skills (`grill-with-docs`, `to-prd`, `to-tickets`, `triage`, `diagnose`, `improve-codebase-architecture`) read from these locations:

1. **Glossary terms** → `sentinel/CONTEXT.md`
2. **Architectural decisions** → `sentinel/docs/adr/*.md`
3. **Cross-cutting principles** → `skill-observations/log.md` (maintained by `task-observer`)

## Maintenance

- `grill-with-docs` creates/updates `CONTEXT.md` when new terms are resolved during grilling
- `grill-with-docs` writes ADRs to `sentinel/docs/adr/` when a decision meets the bar:
  - **Hard to reverse** (significant migration cost)
  - **Surprising without context** (future reader would ask "why?")
  - **Result of a real trade-off** (not a default/obvious choice)
- Do not bulk-migrate old `UBIQUITOUS_LANGUAGE.md` — migrate lazily on next touch
- ADR filenames: `NNNN-short-kebab-case.md` (e.g., `0004-quest-graph-engine.md`)

## Example CONTEXT.md Entry

```markdown
## QuestGraph

**Definition:** A directed acyclic graph (DAG) representing quest prerequisites, chains, breadcrumbs, and mutual exclusions. Nodes are quests; edges are `requires`, `follows`, `breadcrumbs`, `excludes`.

**Aliases to avoid:** "QuestTree" (not a tree — has diamonds), "QuestChain" (single chain, not graph).

**Relationships:**
- `QuestGraph` contains many `QuestNode`
- `QuestNode` has `prerequisites: QuestNode[]`
- `QuestPlanner` traverses `QuestGraph` to produce `QuestPlan`

**Example dialogue:**
> "The QuestGraph for Westfall has 47 nodes. The 'Westfall Stew' quest (ID 38) has prerequisites [36, 37] and follows into [39, 40]. It's not a chain — it's a diamond."
```