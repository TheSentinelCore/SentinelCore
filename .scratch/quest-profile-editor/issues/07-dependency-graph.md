# 07 — Dependency Graph

**What to build:** A visualization of quest prerequisite chains as a directed acyclic graph. Shows which quests depend on which other quests, color-coded by status (available, active, completed).

**Blocked by:** 06 — Quest Browser

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/dependency_graph.lua`
- [ ] Query `QueryClient` for quest prerequisites
- [ ] Build DAG from prerequisite relationships
- [ ] Render nodes: quests as circles/rectangles with name and level
- [ ] Render edges: prerequisite arrows (source → dependent)
- [ ] Color coding: available=gray, active=blue, completed=green, locked=red
- [ ] Topological sort layout (left-to-right or top-to-bottom)
- [ ] Hover node: show quest details tooltip
- [ ] Click node: highlight all prerequisites and dependents
- [ ] Show profile's quest sequence overlaid on graph
- [ ] Zoom/pan support for large graphs
