# 03 — Statechart Canvas: Render States & Transitions

**What to build:** A visual canvas that renders the profile's state hierarchy as a node-based graph. States appear as rounded rectangles (color-coded by type), transitions as bezier curves with arrowheads, and regions as nested containers. The canvas reads from the profile data model and renders the full state tree.

**Blocked by:** 01 — Editor Window Shell

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/statechart_canvas.lua`
- [ ] Create `sentinel/ui/quest_ui/profile_editor/components/node.lua` for state rendering
- [ ] Create `sentinel/ui/quest_ui/profile_editor/components/edge.lua` for transition rendering
- [ ] Parse profile YAML states into `StateNode` and `TransitionEdge` data structures
- [ ] Render atomic states as blue rounded rectangles
- [ ] Render compound states as green containers with nested children
- [ ] Render parallel states as purple containers with region divisions
- [ ] Render final states as gold circles
- [ ] Render initial pseudo-states as small filled circles with arrows
- [ ] Render transitions as bezier curves with arrowheads
- [ ] Auto-layout: hierarchical tree layout algorithm
- [ ] Show state labels and type indicators
