# Enhanced MMap Generation — Design & Implementation Plan

## Context

NavBuddy currently loads third-party pre-generated CMaNGOS-format mmaps for pathfinding. These were generated with default Recast parameters and **do not include server-spawned GameObjects** (fences, crates, barriers, mining/herb nodes). This causes the bot to path through solid objects that exist in-game but are invisible to the navmesh.

**Goals**:
1. Generate higher-quality mmaps with tuned Recast parameters (2x horizontal resolution, finer vertical)
2. Inject static GameObjects from the CMaNGOS-TBC database into the navmesh
3. Produce mmtile files compatible with NavBuddy's existing `tc-mmap` loader

## Approach

Clone CMaNGOS-TBC, build and modify the C++ mmap generator. Apply Recast parameter tuning and GO injection, then validate against NavBuddy.

## Format Compatibility (Verified)

CMaNGOS MmapTileHeader (20 bytes) matches NavBuddy's tc-mmap format:
- Magic: `0x4D4D4150` ("MMAP") -- matches
- Detour version: `7` -- matches NavBuddy's expected `DT_NAVMESH_VERSION`
- MMAP version: `8` -- within NavBuddy's accepted range (5-15)
- Size + usesLiquids fields: binary compatible (uint32 vs u8+padding in little-endian)

## Recast Parameter Changes

### cellSize Constraint
`BASE_UNIT_DIM` must evenly divide `GRID_SIZE` (533.33333), and `VERTEX_PER_MAP` must be divisible by `VERTEX_PER_TILE` (80).

- Default: `BASE_UNIT_DIM = 0.2666666f` -> `VERTEX_PER_MAP = 2000`, `TILES_PER_MAP = 25`
- **Chosen**: `BASE_UNIT_DIM = 0.1333333f` -> `VERTEX_PER_MAP = 4000`, `TILES_PER_MAP = 50`

NOTE: `cs = 0.20` was originally proposed but would break the tile grid (2667/80 = 33.3, not integer).

### Full Parameter Table

| Parameter | CMaNGOS Default | New Value | Effect |
|-----------|----------------|-----------|--------|
| BASE_UNIT_DIM (cs) | 0.2666666f | **0.1333333f** | 2x horizontal resolution |
| cellHeight (ch) | 0.2666666f (=cs) | **0.15f** | Better stair/curb detection |
| walkableRadius | 2 | **1** | Tighter fit (0.13yd vs 0.53yd) |
| walkableClimb | 4 | **3** | Conservative step-up |
| maxSimplificationError | 1.8 | **1.0** | More edge detail |
| minRegionArea | 60 | **20** | Smaller walkable islands |
| mergeRegionArea | 50 | **30** | Less aggressive merging |
| detailSampleDist | BASE_UNIT_DIM*16 | **BASE_UNIT_DIM*12** | Denser detail mesh |
| detailSampleMaxError | BASE_UNIT_DIM | **0.15** | Tighter detail accuracy |
| walkableSlopeAngle | 60° | **55°** | Stricter slope limit |

### Source Files Modified

- `contrib/mmap/src/MapBuilder.h:50` -- `BASE_UNIT_DIM = 0.1333333f`
- `contrib/mmap/src/MapBuilder.cpp:69` -- `config.ch = 0.15f` (independent of cs)
- `contrib/mmap/src/MapBuilder.cpp:1227-1243` -- `getDefaultConfig()` tuned params

## GameObject Injection (Step 4)

Injection point: `buildTile()` between `loadVMap()` and `cleanVertices()`.

Add `TerrainBuilder::loadGameObjects()` that:
1. Queries CMaNGOS DB for GOs on the current tile (type 0/DOOR, type 5/GENERIC)
2. Resolves displayId -> model file via GameObjectDisplayInfo.dbc
3. Loads collision mesh via existing vmap model infrastructure
4. Transforms: scale * rotation * position, then WoW->Recast coordinate conversion
5. Appends to `MeshData.solidVerts` / `MeshData.solidTris`

## Build Dependencies

- CMaNGOS-TBC repo: `C:\Users\Levi\Desktop\mangos-tbc`
- vcpkg + Boost: `C:\Users\Levi\Desktop\vcpkg`
- VS2022 Community (MSVC)
- Existing client data: maps/, vmaps/, dbc/

## Expected Tradeoffs

- Generation time: ~4x slower (doubled cs in both dimensions)
- Tile file size: ~2-4x larger
- Path quality: significantly better near obstacles, stairs, narrow passages
