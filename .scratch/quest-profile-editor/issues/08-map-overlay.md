# 08 — Map Overlay

**What to build:** A map overlay panel that renders quest locations, NPC positions, and objective areas on a zoomable/pannable map view. Shows where quests in the profile take place.

**Blocked by:** 01 — Editor Window Shell

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/map_overlay.lua`
- [ ] Create `sentinel/ui/quest_ui/profile_editor/utils/zoom_pan.lua` for zoom/pan controller
- [ ] Render zone map background (solid color grid or zone texture if available)
- [ ] Render NPC markers: circles at quest giver/turn-in locations
- [ ] Render objective areas: rectangles/polygons for kill/collect zones
- [ ] Render routing policy paths: lines between waypoints
- [ ] Player position indicator (arrow)
- [ ] Scroll: zoom in/out
- [ ] Drag: pan map
- [ ] Click marker: show quest/NPC details popup
- [ ] Integration with profile's routing policies for path display
- [ ] Zone selector dropdown to switch between zones
