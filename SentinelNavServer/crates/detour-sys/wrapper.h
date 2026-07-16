/**
 * @file wrapper.h
 * @brief C-linkage wrapper for Detour C++ library.
 *
 * This header provides C-compatible function declarations that wrap
 * Detour's C++ classes. These are used by bindgen to generate Rust FFI bindings.
 *
 * Why we need this:
 * - bindgen cannot directly bind C++ class methods
 * - We need C-linkage functions that delegate to the C++ methods
 * - This allows Rust to call Detour functions via FFI
 */

#ifndef SENTINEL_NAV_SERVER_WRAPPER_H
#define SENTINEL_NAV_SERVER_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Type Definitions
// =============================================================================

// Opaque pointer types - the actual structs are defined in C++
// Use void* for C compatibility with C++ class types
typedef void dtNavMesh;
typedef void dtNavMeshQuery;
typedef void dtQueryFilter;

// TrinityCore uses 64-bit poly refs for WoW-scale worlds
// This must match DT_POLYREF64 setting in DetourNavMesh.h
typedef uint64_t dtPolyRef;
typedef uint64_t dtTileRef;

// Status codes
typedef uint32_t dtStatus;

// Status code constants (must match DetourStatus.h)
#define WRAPPER_DT_SUCCESS          (1u << 30)
#define WRAPPER_DT_FAILURE          (1u << 31)
#define WRAPPER_DT_IN_PROGRESS      (1u << 29)

// Status detail masks
#define WRAPPER_DT_WRONG_MAGIC      (1u << 0)
#define WRAPPER_DT_WRONG_VERSION    (1u << 1)
#define WRAPPER_DT_OUT_OF_MEMORY    (1u << 2)
#define WRAPPER_DT_INVALID_PARAM    (1u << 3)
#define WRAPPER_DT_BUFFER_TOO_SMALL (1u << 4)
#define WRAPPER_DT_OUT_OF_NODES     (1u << 5)
#define WRAPPER_DT_PARTIAL_RESULT   (1u << 6)

// Tile flags
#define WRAPPER_DT_TILE_FREE_DATA   0x01

// Max areas for query filter
#define WRAPPER_DT_MAX_AREAS        64

// =============================================================================
// NavMesh Parameters
// =============================================================================

/**
 * @brief Configuration parameters for multi-tile navigation meshes.
 *
 * Note: This must match dtNavMeshParams in DetourNavMesh.h
 */
typedef struct WrapperNavMeshParams {
    float orig[3];      ///< World space origin of tile space
    float tileWidth;    ///< Width of each tile (along x-axis)
    float tileHeight;   ///< Height of each tile (along z-axis)
    int maxTiles;       ///< Maximum number of tiles
    int maxPolys;       ///< Maximum polygons per tile
} WrapperNavMeshParams;

// =============================================================================
// Status Helper Functions
// =============================================================================

/**
 * @brief Check if status indicates success.
 */
static inline bool wrapper_dtStatusSucceed(dtStatus status) {
    return (status & WRAPPER_DT_SUCCESS) != 0;
}

/**
 * @brief Check if status indicates failure.
 */
static inline bool wrapper_dtStatusFailed(dtStatus status) {
    return (status & WRAPPER_DT_FAILURE) != 0;
}

/**
 * @brief Check if status indicates in progress.
 */
static inline bool wrapper_dtStatusInProgress(dtStatus status) {
    return (status & WRAPPER_DT_IN_PROGRESS) != 0;
}

/**
 * @brief Check if status has a detail flag.
 */
static inline bool wrapper_dtStatusDetail(dtStatus status, dtStatus detail) {
    return (status & detail) != 0;
}

// =============================================================================
// NavMesh Allocation
// =============================================================================

/**
 * @brief Allocate a new dtNavMesh.
 * @return Pointer to allocated NavMesh, or NULL on failure.
 */
dtNavMesh* wrapper_dtAllocNavMesh(void);

/**
 * @brief Free a dtNavMesh.
 * @param nav The NavMesh to free.
 */
void wrapper_dtFreeNavMesh(dtNavMesh* nav);

// =============================================================================
// NavMesh Initialization
// =============================================================================

/**
 * @brief Initialize NavMesh for tiled use.
 * @param nav The NavMesh to initialize.
 * @param params Initialization parameters.
 * @return Status code.
 */
dtStatus wrapper_dtNavMesh_init(dtNavMesh* nav, const WrapperNavMeshParams* params);

/**
 * @brief Initialize NavMesh with single tile data.
 * @param nav The NavMesh to initialize.
 * @param data Tile data (ownership may transfer based on flags).
 * @param dataSize Size of tile data.
 * @param flags Tile flags (e.g., DT_TILE_FREE_DATA).
 * @return Status code.
 */
dtStatus wrapper_dtNavMesh_initSingle(dtNavMesh* nav, unsigned char* data, int dataSize, int flags);

// =============================================================================
// NavMesh Tile Management
// =============================================================================

/**
 * @brief Add a tile to the NavMesh.
 * @param nav The NavMesh.
 * @param data Tile data (ownership transfers if DT_TILE_FREE_DATA set).
 * @param dataSize Size of tile data.
 * @param flags Tile flags.
 * @param lastRef Previous tile reference (for reloading), or 0.
 * @param result Output: the tile reference.
 * @return Status code.
 */
dtStatus wrapper_dtNavMesh_addTile(
    dtNavMesh* nav,
    unsigned char* data,
    int dataSize,
    int flags,
    dtTileRef lastRef,
    dtTileRef* result
);

/**
 * @brief Remove a tile from the NavMesh.
 * @param nav The NavMesh.
 * @param ref Tile reference to remove.
 * @param data Output: tile data (if DT_TILE_FREE_DATA was not set).
 * @param dataSize Output: tile data size.
 * @return Status code.
 */
dtStatus wrapper_dtNavMesh_removeTile(
    dtNavMesh* nav,
    dtTileRef ref,
    unsigned char** data,
    int* dataSize
);

/**
 * @brief Get tile at specified grid location.
 * @param nav The NavMesh.
 * @param x Tile x coordinate.
 * @param y Tile y coordinate.
 * @param layer Tile layer.
 * @return Pointer to tile, or NULL if not found.
 */
const void* wrapper_dtNavMesh_getTileAt(const dtNavMesh* nav, int x, int y, int layer);

/**
 * @brief Get the maximum number of tiles.
 * @param nav The NavMesh.
 * @return Maximum tile count.
 */
int wrapper_dtNavMesh_getMaxTiles(const dtNavMesh* nav);

/**
 * @brief Get NavMesh parameters.
 * @param nav The NavMesh.
 * @return Pointer to parameters.
 */
const WrapperNavMeshParams* wrapper_dtNavMesh_getParams(const dtNavMesh* nav);

// =============================================================================
// NavMeshQuery Allocation
// =============================================================================

/**
 * @brief Allocate a new dtNavMeshQuery.
 * @return Pointer to allocated query, or NULL on failure.
 */
dtNavMeshQuery* wrapper_dtAllocNavMeshQuery(void);

/**
 * @brief Free a dtNavMeshQuery.
 * @param query The query to free.
 */
void wrapper_dtFreeNavMeshQuery(dtNavMeshQuery* query);

// =============================================================================
// NavMeshQuery Initialization
// =============================================================================

/**
 * @brief Initialize the query object.
 * @param query The query to initialize.
 * @param nav The NavMesh to query.
 * @param maxNodes Maximum search nodes (limit: 0 < value <= 65535).
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_init(dtNavMeshQuery* query, const dtNavMesh* nav, int maxNodes);

// =============================================================================
// NavMeshQuery - Pathfinding
// =============================================================================

/**
 * @brief Find the nearest polygon to a position.
 * @param query The query object.
 * @param center Search center position [x, y, z].
 * @param halfExtents Search box half-extents [x, y, z].
 * @param filter Query filter.
 * @param nearestRef Output: nearest polygon reference.
 * @param nearestPt Output: nearest point on polygon [x, y, z].
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_findNearestPoly(
    const dtNavMeshQuery* query,
    const float* center,
    const float* halfExtents,
    const dtQueryFilter* filter,
    dtPolyRef* nearestRef,
    float* nearestPt
);

/**
 * @brief Find a path from start to end polygon.
 * @param query The query object.
 * @param startRef Start polygon reference.
 * @param endRef End polygon reference.
 * @param startPos Start position [x, y, z].
 * @param endPos End position [x, y, z].
 * @param filter Query filter.
 * @param path Output: array of polygon references.
 * @param pathCount Output: number of polygons in path.
 * @param maxPath Maximum polygons in path array.
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_findPath(
    const dtNavMeshQuery* query,
    dtPolyRef startRef,
    dtPolyRef endRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    dtPolyRef* path,
    int* pathCount,
    int maxPath
);

/**
 * @brief Find the straight path through a polygon corridor.
 * @param query The query object.
 * @param startPos Start position [x, y, z].
 * @param endPos End position [x, y, z].
 * @param path Polygon corridor (from findPath).
 * @param pathSize Number of polygons in corridor.
 * @param straightPath Output: waypoint positions [x, y, z] * count.
 * @param straightPathFlags Output: waypoint flags (optional, can be NULL).
 * @param straightPathRefs Output: polygon refs (optional, can be NULL).
 * @param straightPathCount Output: number of waypoints.
 * @param maxStraightPath Maximum waypoints.
 * @param options Path options (see dtStraightPathOptions).
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_findStraightPath(
    const dtNavMeshQuery* query,
    const float* startPos,
    const float* endPos,
    const dtPolyRef* path,
    int pathSize,
    float* straightPath,
    unsigned char* straightPathFlags,
    dtPolyRef* straightPathRefs,
    int* straightPathCount,
    int maxStraightPath,
    int options
);

// =============================================================================
// NavMeshQuery - Movement
// =============================================================================

/**
 * @brief Move along the surface of the navmesh.
 * @param query The query object.
 * @param startRef Start polygon reference.
 * @param startPos Start position [x, y, z].
 * @param endPos Desired end position [x, y, z].
 * @param filter Query filter.
 * @param resultPos Output: actual end position [x, y, z].
 * @param visited Output: visited polygon refs (optional).
 * @param visitedCount Output: number of visited polygons.
 * @param maxVisitedSize Maximum visited polygons.
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_moveAlongSurface(
    const dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    float* resultPos,
    dtPolyRef* visited,
    int* visitedCount,
    int maxVisitedSize
);

/**
 * @brief Cast a ray along the navmesh surface.
 * @param query The query object.
 * @param startRef Start polygon reference.
 * @param startPos Start position [x, y, z].
 * @param endPos End position [x, y, z].
 * @param filter Query filter.
 * @param t Output: hit parameter (FLT_MAX if no hit).
 * @param hitNormal Output: normal at hit point [x, y, z].
 * @param path Output: visited polygon refs (optional).
 * @param pathCount Output: number of visited polygons.
 * @param maxPath Maximum path polygons.
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_raycast(
    const dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* startPos,
    const float* endPos,
    const dtQueryFilter* filter,
    float* t,
    float* hitNormal,
    dtPolyRef* path,
    int* pathCount,
    int maxPath
);

// =============================================================================
// NavMeshQuery - Wall Distance
// =============================================================================

/**
 * @brief Find the distance from a position to the nearest polygon wall.
 * @param query The query object.
 * @param startRef Start polygon reference.
 * @param centerPos Center position [x, y, z].
 * @param maxRadius Maximum search radius.
 * @param filter Query filter.
 * @param hitDist Output: distance to nearest wall.
 * @param hitPos Output: nearest position on wall [x, y, z].
 * @param hitNormal Output: normal pointing from wall toward center [x, y, z].
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_findDistanceToWall(
    const dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* centerPos,
    float maxRadius,
    const dtQueryFilter* filter,
    float* hitDist,
    float* hitPos,
    float* hitNormal
);

// =============================================================================
// NavMeshQuery - Random Points
// =============================================================================

/**
 * @brief Random number generator function type.
 */
typedef float (*RandomFunc)(void);

/**
 * @brief Find a random point on the navmesh.
 * @param query The query object.
 * @param filter Query filter.
 * @param frand Random number generator function [0..1).
 * @param randomRef Output: polygon reference.
 * @param randomPt Output: random point [x, y, z].
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_findRandomPoint(
    const dtNavMeshQuery* query,
    const dtQueryFilter* filter,
    RandomFunc frand,
    dtPolyRef* randomRef,
    float* randomPt
);

/**
 * @brief Find a random point within a circle.
 * @param query The query object.
 * @param startRef Center polygon reference.
 * @param centerPos Center position [x, y, z].
 * @param maxRadius Search radius.
 * @param filter Query filter.
 * @param frand Random number generator function [0..1).
 * @param randomRef Output: polygon reference.
 * @param randomPt Output: random point [x, y, z].
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_findRandomPointAroundCircle(
    const dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* centerPos,
    float maxRadius,
    const dtQueryFilter* filter,
    RandomFunc frand,
    dtPolyRef* randomRef,
    float* randomPt
);

// =============================================================================
// NavMeshQuery - Height Queries
// =============================================================================

/**
 * @brief Get the height at a position on a polygon.
 * @param query The query object.
 * @param ref Polygon reference.
 * @param pos Position [x, y, z] (x, z used for lookup).
 * @param height Output: height at position.
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_getPolyHeight(
    const dtNavMeshQuery* query,
    dtPolyRef ref,
    const float* pos,
    float* height
);

/**
 * @brief Find the closest point on a polygon.
 * @param query The query object.
 * @param ref Polygon reference.
 * @param pos Position to check [x, y, z].
 * @param closest Output: closest point [x, y, z].
 * @param posOverPoly Output: true if pos is over polygon.
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_closestPointOnPoly(
    const dtNavMeshQuery* query,
    dtPolyRef ref,
    const float* pos,
    float* closest,
    bool* posOverPoly
);

// =============================================================================
// QueryFilter Allocation and Configuration
// =============================================================================

/**
 * @brief Allocate a new dtQueryFilter.
 * @return Pointer to allocated filter, or NULL on failure.
 */
dtQueryFilter* wrapper_dtAllocQueryFilter(void);

/**
 * @brief Free a dtQueryFilter.
 * @param filter The filter to free.
 */
void wrapper_dtFreeQueryFilter(dtQueryFilter* filter);

/**
 * @brief Set the traversal cost for an area.
 * @param filter The filter.
 * @param area Area index (0-63).
 * @param cost Traversal cost.
 */
void wrapper_dtQueryFilter_setAreaCost(dtQueryFilter* filter, int area, float cost);

/**
 * @brief Get the traversal cost for an area.
 * @param filter The filter.
 * @param area Area index (0-63).
 * @return Traversal cost.
 */
float wrapper_dtQueryFilter_getAreaCost(const dtQueryFilter* filter, int area);

/**
 * @brief Set the include flags for polygon filtering.
 * @param filter The filter.
 * @param flags Include flags.
 */
void wrapper_dtQueryFilter_setIncludeFlags(dtQueryFilter* filter, unsigned short flags);

/**
 * @brief Get the include flags.
 * @param filter The filter.
 * @return Include flags.
 */
unsigned short wrapper_dtQueryFilter_getIncludeFlags(const dtQueryFilter* filter);

/**
 * @brief Set the exclude flags for polygon filtering.
 * @param filter The filter.
 * @param flags Exclude flags.
 */
void wrapper_dtQueryFilter_setExcludeFlags(dtQueryFilter* filter, unsigned short flags);

/**
 * @brief Get the exclude flags.
 * @param filter The filter.
 * @return Exclude flags.
 */
unsigned short wrapper_dtQueryFilter_getExcludeFlags(const dtQueryFilter* filter);

// =============================================================================
// NavMesh - Polygon Queries
// =============================================================================

/**
 * @brief Get the flags for a polygon.
 * @param nav The NavMesh.
 * @param ref Polygon reference.
 * @param flags Output: polygon flags.
 * @return Status code.
 */
dtStatus wrapper_dtNavMesh_getPolyFlags(
    const dtNavMesh* nav,
    dtPolyRef ref,
    unsigned short* flags
);

/**
 * @brief Get the area type for a polygon.
 * @param nav The NavMesh.
 * @param ref Polygon reference.
 * @param area Output: area type (0-63).
 * @return Status code.
 */
dtStatus wrapper_dtNavMesh_getPolyArea(
    const dtNavMesh* nav,
    dtPolyRef ref,
    unsigned char* area
);

/**
 * @brief Set the area type for a polygon.
 * @param nav The NavMesh (non-const — mutates polygon area).
 * @param ref Polygon reference.
 * @param area New area type (0-63).
 * @return Status code.
 */
dtStatus wrapper_dtNavMesh_setPolyArea(
    dtNavMesh* nav,
    dtPolyRef ref,
    unsigned char area
);

// =============================================================================
// NavMeshQuery - Polygon Search
// =============================================================================

/**
 * @brief Find all polygons overlapping a search box.
 * @param query The query object.
 * @param center Search box center [x, y, z].
 * @param halfExtents Search box half-extents [x, y, z].
 * @param filter Query filter.
 * @param polys Output: polygon references.
 * @param polyCount Output: number of polygons found.
 * @param maxPolys Maximum polygons in output array.
 * @return Status code.
 */
dtStatus wrapper_dtNavMeshQuery_queryPolygons(
    const dtNavMeshQuery* query,
    const float* center,
    const float* halfExtents,
    const dtQueryFilter* filter,
    dtPolyRef* polys,
    int* polyCount,
    int maxPolys
);

#ifdef __cplusplus
}
#endif

#endif // SENTINEL_NAV_SERVER_WRAPPER_H
