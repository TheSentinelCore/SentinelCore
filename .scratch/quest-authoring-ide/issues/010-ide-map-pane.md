# 010 — IDE: Map Pane

**What to build:** Implement the center Map pane (primary canvas) that shows:
- Interactive world map based on Mangos TBC database
- Click to draw polygons for farm areas, patrol zones, avoid zones
- Click to place markers for quest hubs, vendors, trainers
- Clicking on world objects (NPCs, monsters, game objects) sets their ID in selected action fields
- Right-click drag to pan, scroll wheel to zoom
- Layer toggles: show/hide quest givers, trainers, vendors, flight masters, etc.
- Coordinate grid overlay (toggleable)
- Integration with Timeline: selecting an operation shows its markers/polys on map
- Integration with Properties: clicking a marker/poly selects the corresponding action
- Visual feedback for selected objects (highlighting, tooltip with ID/name)
- Support for multiple polygon types: fill (area), line (route), point (marker)
- Color coding by action type (green for quest, red for avoid, blue for travel, etc.)
- Snapping to grid for precise placement
- Export/import of map annotations as part of operation YAML
- Performance optimizations for large worlds (tile-based rendering, level-of-detail)
- Tooltip on hover showing object name, ID, zone, etc.
- Click-drag to create rectangles, shift-click for polygons
- Clear selection with Escape key

**Blocked by:** 001 — Source Format Specification

**Status:** ready-for-agent

- [ ] Create Map component using HTML5 Canvas or WebGL for rendering
- [ ] Fetch map data from Mangos TBC database via QueryClient (area tables, terrain textures)
- [ ] Implement tile-based loading for efficient world streaming
- [ ] Add coordinate system overlay (showing current mouse position in world coords)
- [ ] Implement drawing tools: polygon (fill/line), point marker, rectangle, ellipse
- [ ] Implement selection system: click to select map elements, drag to pan
- [ ] Add layer system: terrain, objects (NPCs, monsters, gameobjects), user annotations
- [ ] Implement object clicking: when user clicks NPC/monster/gameobject, get its ID and populate relevant action field
- [ ] Add snapping to grid (configurable: 1-yard, 5-yard, 10-yard)
- [ ] Implement zoom/pan with inertia and bounds checking
- [ ] Add minimap in corner for navigation
- [ ] Implement measurement tool (distance between two points)
- [ ] Add ability to save/load map views as part of project
- [ ] Integrate with Timeline: when operation selected, show only its objects on map
- [ ] Integrate with Properties: when map object selected, show/edit corresponding action
- [ ] Visual feedback: selected objects glow, hovered objects highlight
- [ ] Support for multiple map instances (different zoom levels)
- [ ] Performance target: 60fps at 1920x1080 resolution