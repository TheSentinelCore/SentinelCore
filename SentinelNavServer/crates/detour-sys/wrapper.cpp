/**
 * @file wrapper.cpp
 * @brief C-linkage wrapper implementation for Detour C++ library.
 *
 * This file implements the C wrapper functions declared in wrapper.h.
 * Each function delegates to the corresponding Detour C++ method.
 */

#include <new>
#include "recastnavigation/Detour/Include/DetourNavMesh.h"
#include "recastnavigation/Detour/Include/DetourNavMeshQuery.h"

// Forward declare wrapper params struct to match header
struct WrapperNavMeshParams {
    float orig[3];
    float tileWidth;
    float tileHeight;
    int maxTiles;
    int maxPolys;
};

extern "C" {

// =============================================================================
// NavMesh Allocation
// =============================================================================

dtNavMesh* wrapper_dtAllocNavMesh(void) {
    return dtAllocNavMesh();
}

void wrapper_dtFreeNavMesh(dtNavMesh* nav) {
    dtFreeNavMesh(nav);
}

// =============================================================================
// NavMesh Initialization
// =============================================================================

dtStatus wrapper_dtNavMesh_init(dtNavMesh* nav, const WrapperNavMeshParams* params) {
    if (!nav || !params) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }

    // WrapperNavMeshParams is layout-compatible with dtNavMeshParams
    return nav->init(reinterpret_cast<const dtNavMeshParams*>(params));
}

dtStatus wrapper_dtNavMesh_initSingle(dtNavMesh* nav, unsigned char* data, int dataSize, int flags) {
    if (!nav) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return nav->init(data, dataSize, flags);
}

// =============================================================================
// NavMesh Tile Management
// =============================================================================

dtStatus wrapper_dtNavMesh_addTile(
    dtNavMesh* nav,
    unsigned char* data,
    int dataSize,
    int flags,
    dtTileRef lastRef,
    dtTileRef* result
) {
    if (!nav) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return nav->addTile(data, dataSize, flags, lastRef, result);
}

dtStatus wrapper_dtNavMesh_removeTile(
    dtNavMesh* nav,
    dtTileRef ref,
    unsigned char** data,
    int* dataSize
) {
    if (!nav) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return nav->removeTile(ref, data, dataSize);
}

const void* wrapper_dtNavMesh_getTileAt(const dtNavMesh* nav, int x, int y, int layer) {
    if (!nav) {
        return nullptr;
    }
    return nav->getTileAt(x, y, layer);
}

int wrapper_dtNavMesh_getMaxTiles(const dtNavMesh* nav) {
    if (!nav) {
        return 0;
    }
    return nav->getMaxTiles();
}

const WrapperNavMeshParams* wrapper_dtNavMesh_getParams(const dtNavMesh* nav) {
    if (!nav) {
        return nullptr;
    }
    // dtNavMeshParams and WrapperNavMeshParams are layout-compatible
    return reinterpret_cast<const WrapperNavMeshParams*>(nav->getParams());
}

// =============================================================================
// NavMeshQuery Allocation
// =============================================================================

dtNavMeshQuery* wrapper_dtAllocNavMeshQuery(void) {
    return dtAllocNavMeshQuery();
}

void wrapper_dtFreeNavMeshQuery(dtNavMeshQuery* query) {
    dtFreeNavMeshQuery(query);
}

// =============================================================================
// NavMeshQuery Initialization
// =============================================================================

dtStatus wrapper_dtNavMeshQuery_init(dtNavMeshQuery* query, const dtNavMesh* nav, int maxNodes) {
    if (!query || !nav) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->init(nav, maxNodes);
}

// =============================================================================
// NavMeshQuery - Pathfinding
// =============================================================================

dtStatus wrapper_dtNavMeshQuery_findNearestPoly(
    const dtNavMeshQuery* query,
    const float* center,
    const float* halfExtents,
    const dtQueryFilter* filter,
    dtPolyRef* nearestRef,
    float* nearestPt
) {
    if (!query || !center || !halfExtents || !filter || !nearestRef) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->findNearestPoly(center, halfExtents, filter, nearestRef, nearestPt);
}

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
) {
    if (!query || !startPos || !endPos || !filter || !path || !pathCount) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->findPath(startRef, endRef, startPos, endPos, filter, path, pathCount, maxPath);
}

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
) {
    if (!query || !startPos || !endPos || !path || !straightPath || !straightPathCount) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->findStraightPath(
        startPos, endPos,
        path, pathSize,
        straightPath, straightPathFlags, straightPathRefs,
        straightPathCount, maxStraightPath, options
    );
}

// =============================================================================
// NavMeshQuery - Movement
// =============================================================================

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
) {
    if (!query || !startPos || !endPos || !filter || !resultPos || !visitedCount) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->moveAlongSurface(
        startRef, startPos, endPos, filter,
        resultPos, visited, visitedCount, maxVisitedSize
    );
}

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
) {
    if (!query || !startPos || !endPos || !filter || !t || !hitNormal) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->raycast(
        startRef, startPos, endPos, filter,
        t, hitNormal, path, pathCount, maxPath
    );
}

// =============================================================================
// NavMeshQuery - Wall Distance
// =============================================================================

dtStatus wrapper_dtNavMeshQuery_findDistanceToWall(
    const dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* centerPos,
    float maxRadius,
    const dtQueryFilter* filter,
    float* hitDist,
    float* hitPos,
    float* hitNormal
) {
    if (!query || !centerPos || !filter || !hitDist || !hitPos || !hitNormal) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->findDistanceToWall(startRef, centerPos, maxRadius, filter, hitDist, hitPos, hitNormal);
}

// =============================================================================
// NavMeshQuery - Random Points
// =============================================================================

typedef float (*RandomFunc)(void);

dtStatus wrapper_dtNavMeshQuery_findRandomPoint(
    const dtNavMeshQuery* query,
    const dtQueryFilter* filter,
    RandomFunc frand,
    dtPolyRef* randomRef,
    float* randomPt
) {
    if (!query || !filter || !frand || !randomRef || !randomPt) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->findRandomPoint(filter, frand, randomRef, randomPt);
}

dtStatus wrapper_dtNavMeshQuery_findRandomPointAroundCircle(
    const dtNavMeshQuery* query,
    dtPolyRef startRef,
    const float* centerPos,
    float maxRadius,
    const dtQueryFilter* filter,
    RandomFunc frand,
    dtPolyRef* randomRef,
    float* randomPt
) {
    if (!query || !centerPos || !filter || !frand || !randomRef || !randomPt) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->findRandomPointAroundCircle(
        startRef, centerPos, maxRadius, filter, frand, randomRef, randomPt
    );
}

// =============================================================================
// NavMeshQuery - Height Queries
// =============================================================================

dtStatus wrapper_dtNavMeshQuery_getPolyHeight(
    const dtNavMeshQuery* query,
    dtPolyRef ref,
    const float* pos,
    float* height
) {
    if (!query || !pos || !height) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->getPolyHeight(ref, pos, height);
}

dtStatus wrapper_dtNavMeshQuery_closestPointOnPoly(
    const dtNavMeshQuery* query,
    dtPolyRef ref,
    const float* pos,
    float* closest,
    bool* posOverPoly
) {
    if (!query || !pos || !closest) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->closestPointOnPoly(ref, pos, closest, posOverPoly);
}

// =============================================================================
// QueryFilter Allocation and Configuration
// =============================================================================

dtQueryFilter* wrapper_dtAllocQueryFilter(void) {
    return new (std::nothrow) dtQueryFilter();
}

void wrapper_dtFreeQueryFilter(dtQueryFilter* filter) {
    delete filter;
}

void wrapper_dtQueryFilter_setAreaCost(dtQueryFilter* filter, int area, float cost) {
    if (filter && area >= 0 && area < DT_MAX_AREAS) {
        filter->setAreaCost(area, cost);
    }
}

float wrapper_dtQueryFilter_getAreaCost(const dtQueryFilter* filter, int area) {
    if (filter && area >= 0 && area < DT_MAX_AREAS) {
        return filter->getAreaCost(area);
    }
    return 1.0f; // Default cost
}

void wrapper_dtQueryFilter_setIncludeFlags(dtQueryFilter* filter, unsigned short flags) {
    if (filter) {
        filter->setIncludeFlags(flags);
    }
}

unsigned short wrapper_dtQueryFilter_getIncludeFlags(const dtQueryFilter* filter) {
    if (filter) {
        return filter->getIncludeFlags();
    }
    return 0xffff; // Default: include all
}

void wrapper_dtQueryFilter_setExcludeFlags(dtQueryFilter* filter, unsigned short flags) {
    if (filter) {
        filter->setExcludeFlags(flags);
    }
}

unsigned short wrapper_dtQueryFilter_getExcludeFlags(const dtQueryFilter* filter) {
    if (filter) {
        return filter->getExcludeFlags();
    }
    return 0; // Default: exclude none
}

// =============================================================================
// NavMesh - Polygon Queries
// =============================================================================

dtStatus wrapper_dtNavMesh_getPolyFlags(
    const dtNavMesh* nav,
    dtPolyRef ref,
    unsigned short* flags
) {
    if (!nav || !flags) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return nav->getPolyFlags(ref, flags);
}

dtStatus wrapper_dtNavMesh_getPolyArea(
    const dtNavMesh* nav,
    dtPolyRef ref,
    unsigned char* area
) {
    if (!nav || !area) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return nav->getPolyArea(ref, area);
}

dtStatus wrapper_dtNavMesh_setPolyArea(
    dtNavMesh* nav,
    dtPolyRef ref,
    unsigned char area
) {
    if (!nav) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return nav->setPolyArea(ref, area);
}

// =============================================================================
// NavMeshQuery - Polygon Search
// =============================================================================

dtStatus wrapper_dtNavMeshQuery_queryPolygons(
    const dtNavMeshQuery* query,
    const float* center,
    const float* halfExtents,
    const dtQueryFilter* filter,
    dtPolyRef* polys,
    int* polyCount,
    int maxPolys
) {
    if (!query || !center || !halfExtents || !filter || !polys || !polyCount) {
        return DT_FAILURE | DT_INVALID_PARAM;
    }
    return query->queryPolygons(center, halfExtents, filter, polys, polyCount, maxPolys);
}

} // extern "C"
