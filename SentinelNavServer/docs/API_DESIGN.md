# API Design Document

## AmeisenNav-RS HTTP API Specification

**Version:** 1.0.0  
**Base URL:** `http://localhost:3000`  
**Last Updated:** 2026-02-02

---

## 1. Overview

AmeisenNav-RS exposes a RESTful HTTP API for navigation mesh pathfinding operations. All endpoints use HTTP GET method with query parameters, designed for compatibility with Lua clients that only support `core.http_get`.

### 1.1 Design Principles

- **GET-only**: All operations use HTTP GET for Lua client compatibility
- **Query Parameters**: All inputs passed as URL query parameters
- **JSON Responses**: All responses are JSON-encoded
- **Idempotent**: All operations are read-only and idempotent
- **Stateless**: No session state between requests

### 1.2 Common Headers

**Request Headers:**
```
Accept: application/json
```

**Response Headers:**
```
Content-Type: application/json
X-Compute-Time-Ms: <milliseconds>
```

---

## 2. Common Data Types

### 2.1 Vec3 (Position)

A 3D world coordinate represented as an array of three floats:

```json
[x, y, z]
```

| Field | Type | Description |
|-------|------|-------------|
| x | float | X coordinate (east-west) |
| y | float | Y coordinate (height) |
| z | float | Z coordinate (north-south) |

### 2.2 Path

An array of Vec3 waypoints:

```json
[[x1, y1, z1], [x2, y2, z2], ...]
```

### 2.3 Smoothing Algorithm

| Value | Description |
|-------|-------------|
| `none` | No smoothing (raw Detour path) |
| `chaikin` | Chaikin curve subdivision |
| `catmull_rom` | Catmull-Rom spline interpolation |
| `bezier` | Bezier curve smoothing |

---

## 3. API Endpoints

### 3.1 Find Path

Find the optimal path between two world positions.

**Endpoint:** `GET /api/v1/path`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| map_id | integer | Yes | WoW map ID (0=Eastern Kingdoms, 1=Kalimdor, etc.) |
| start_x | float | Yes | Start X coordinate |
| start_y | float | Yes | Start Y coordinate |
| start_z | float | Yes | Start Z coordinate |
| end_x | float | Yes | End X coordinate |
| end_y | float | Yes | End Y coordinate |
| end_z | float | Yes | End Z coordinate |
| smoothing | string | No | Smoothing algorithm (default: none) |

**Example Request:**
```
GET /api/v1/path?map_id=0&start_x=-8949.95&start_y=-132.493&start_z=83.5312&end_x=-8898.3&end_y=-161.27&end_z=81.97&smoothing=catmull_rom
```

**Success Response (200 OK):**
```json
{
  "success": true,
  "path": [
    [-8949.95, -132.493, 83.5312],
    [-8930.12, -145.67, 82.45],
    [-8915.45, -155.23, 81.89],
    [-8898.3, -161.27, 81.97]
  ],
  "distance": 68.42,
  "compute_time_ms": 1.23,
  "partial": false,
  "error": null
}
```

**Error Response (404 Not Found):**
```json
{
  "success": false,
  "path": [],
  "distance": 0,
  "compute_time_ms": 0.45,
  "partial": false,
  "error": "Start position not on navmesh"
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| success | boolean | Whether pathfinding succeeded |
| path | array | Array of [x, y, z] waypoints |
| distance | float | Total path distance in yards |
| compute_time_ms | float | Computation time in milliseconds |
| partial | boolean | True if only partial path found |
| error | string? | Error message if failed |

---

### 3.2 Move Along Surface

Perform constrained movement along the navmesh surface. Useful for short-distance movement that stays on the mesh.

**Endpoint:** `GET /api/v1/move`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| map_id | integer | Yes | WoW map ID |
| start_x | float | Yes | Start X coordinate |
| start_y | float | Yes | Start Y coordinate |
| start_z | float | Yes | Start Z coordinate |
| end_x | float | Yes | Desired end X coordinate |
| end_y | float | Yes | Desired end Y coordinate |
| end_z | float | Yes | Desired end Z coordinate |

**Example Request:**
```
GET /api/v1/move?map_id=0&start_x=100&start_y=200&start_z=50&end_x=105&end_y=205&end_z=50
```

**Success Response (200 OK):**
```json
{
  "success": true,
  "result_position": [104.8, 204.2, 50.1],
  "compute_time_ms": 0.15,
  "error": null
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| success | boolean | Whether operation succeeded |
| result_position | array | Actual position after move [x, y, z] |
| compute_time_ms | float | Computation time in milliseconds |
| error | string? | Error message if failed |

---

### 3.3 Raycast

Perform a raycast to check line-of-sight and find obstacles.

**Endpoint:** `GET /api/v1/raycast`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| map_id | integer | Yes | WoW map ID |
| start_x | float | Yes | Start X coordinate |
| start_y | float | Yes | Start Y coordinate |
| start_z | float | Yes | Start Z coordinate |
| end_x | float | Yes | End X coordinate |
| end_y | float | Yes | End Y coordinate |
| end_z | float | Yes | End Z coordinate |

**Example Request:**
```
GET /api/v1/raycast?map_id=0&start_x=100&start_y=200&start_z=50&end_x=150&end_y=250&end_z=55
```

**Success Response (200 OK) - Clear Path:**
```json
{
  "success": true,
  "hit": false,
  "t": 1.0,
  "hit_point": null,
  "hit_normal": null,
  "compute_time_ms": 0.08,
  "error": null
}
```

**Success Response (200 OK) - Obstacle Hit:**
```json
{
  "success": true,
  "hit": true,
  "t": 0.65,
  "hit_point": [132.5, 232.5, 52.8],
  "hit_normal": [0.707, 0, 0.707],
  "compute_time_ms": 0.12,
  "error": null
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| success | boolean | Whether operation succeeded |
| hit | boolean | Whether ray hit an obstacle |
| t | float | Parameter along ray where hit occurred (0-1) |
| hit_point | array? | Position where ray hit [x, y, z] |
| hit_normal | array? | Normal at hit point [x, y, z] |
| compute_time_ms | float | Computation time in milliseconds |
| error | string? | Error message if failed |

---

### 3.4 Random Point

Find a random navigable point on the map.

**Endpoint:** `GET /api/v1/random`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| map_id | integer | Yes | WoW map ID |

**Example Request:**
```
GET /api/v1/random?map_id=0
```

**Success Response (200 OK):**
```json
{
  "success": true,
  "position": [-8734.21, -256.89, 78.45],
  "compute_time_ms": 0.05,
  "error": null
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| success | boolean | Whether operation succeeded |
| position | array | Random navigable position [x, y, z] |
| compute_time_ms | float | Computation time in milliseconds |
| error | string? | Error message if failed |

---

### 3.5 Random Point in Circle

Find a random navigable point within a radius of a center position.

**Endpoint:** `GET /api/v1/random-circle`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| map_id | integer | Yes | WoW map ID |
| center_x | float | Yes | Center X coordinate |
| center_y | float | Yes | Center Y coordinate |
| center_z | float | Yes | Center Z coordinate |
| radius | float | Yes | Maximum radius in yards |

**Example Request:**
```
GET /api/v1/random-circle?map_id=0&center_x=100&center_y=200&center_z=50&radius=30
```

**Success Response (200 OK):**
```json
{
  "success": true,
  "position": [115.67, 212.34, 51.23],
  "distance_from_center": 18.45,
  "compute_time_ms": 0.07,
  "error": null
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| success | boolean | Whether operation succeeded |
| position | array | Random navigable position [x, y, z] |
| distance_from_center | float | Actual distance from center |
| compute_time_ms | float | Computation time in milliseconds |
| error | string? | Error message if failed |

---

### 3.6 Get Height

Get the navmesh height at a position (useful for determining ground level).

**Endpoint:** `GET /api/v1/height`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| map_id | integer | Yes | WoW map ID |
| x | float | Yes | X coordinate |
| y | float | Yes | Y coordinate (approximate height) |
| z | float | Yes | Z coordinate |

**Example Request:**
```
GET /api/v1/height?map_id=0&x=100&y=200&z=50
```

**Success Response (200 OK):**
```json
{
  "success": true,
  "height": 52.34,
  "compute_time_ms": 0.03,
  "error": null
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| success | boolean | Whether operation succeeded |
| height | float | Navmesh height at position |
| compute_time_ms | float | Computation time in milliseconds |
| error | string? | Error message if failed |

---

### 3.7 Health Check

Check server health and status.

**Endpoint:** `GET /health`

**Example Request:**
```
GET /health
```

**Success Response (200 OK):**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "uptime_seconds": 3600,
  "loaded_maps": [0, 1, 530],
  "total_tiles_loaded": 1234,
  "memory_usage_mb": 856.4
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| status | string | Server status ("healthy" or "degraded") |
| version | string | Server version |
| uptime_seconds | integer | Seconds since server start |
| loaded_maps | array | List of loaded map IDs |
| total_tiles_loaded | integer | Total tiles in memory |
| memory_usage_mb | float | Memory usage in megabytes |

---

### 3.8 Map Info

Get information about a specific map.

**Endpoint:** `GET /api/v1/map`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| map_id | integer | Yes | WoW map ID |

**Example Request:**
```
GET /api/v1/map?map_id=0
```

**Success Response (200 OK):**
```json
{
  "success": true,
  "map_id": 0,
  "name": "Eastern Kingdoms",
  "loaded": true,
  "tiles_loaded": 456,
  "tiles_available": 1024,
  "bounds": {
    "min": [-11000, -500, -11000],
    "max": [3000, 1000, 4000]
  },
  "error": null
}
```

---

## 4. Error Handling

### 4.1 HTTP Status Codes

| Status Code | Description |
|-------------|-------------|
| 200 | Success (check `success` field for operation result) |
| 400 | Bad Request (invalid parameters) |
| 404 | Not Found (map not available) |
| 500 | Internal Server Error |
| 503 | Service Unavailable (server overloaded) |

### 4.2 Error Response Format

All error responses follow the same structure as success responses but with `success: false`:

```json
{
  "success": false,
  "error": "Detailed error message",
  "compute_time_ms": 0.0,
  // Other fields with default/empty values
}
```

### 4.3 Common Error Messages

| Error | Description |
|-------|-------------|
| "Start position not on navmesh" | Start coordinates are outside walkable area |
| "End position not on navmesh" | End coordinates are outside walkable area |
| "No path found between positions" | Positions are on disconnected mesh areas |
| "Map {id} not available" | Map files not found for given ID |
| "Invalid parameters" | Missing or malformed query parameters |
| "Server overloaded" | Too many concurrent requests |

---

## 5. Rate Limiting

The server implements basic rate limiting to prevent overload:

| Limit | Value |
|-------|-------|
| Max concurrent requests | 100 |
| Request timeout | 30 seconds |
| Max path length | 2048 waypoints |

When rate limited, the server returns `503 Service Unavailable`.

---

## 6. Client Integration

### 6.1 Lua Client Example (Sylvannas)

```lua
local NavigationClient = {}
NavigationClient.__index = NavigationClient

function NavigationClient:new(base_url)
    local self = setmetatable({}, NavigationClient)
    self.base_url = base_url or "http://localhost:3000"
    return self
end

function NavigationClient:find_path(map_id, start_pos, end_pos, smoothing, callback)
    local url = string.format(
        "%s/api/v1/path?map_id=%d&start_x=%.2f&start_y=%.2f&start_z=%.2f&end_x=%.2f&end_y=%.2f&end_z=%.2f&smoothing=%s",
        self.base_url,
        map_id,
        start_pos.x, start_pos.y, start_pos.z,
        end_pos.x, end_pos.y, end_pos.z,
        smoothing or "none"
    )
    
    core.http_get(url, function(response)
        if not response then
            callback(nil, "HTTP request failed")
            return
        end
        
        local data = json.decode(response)
        if not data.success then
            callback(nil, data.error)
            return
        end
        
        -- Convert path arrays to vec3 objects
        local path = {}
        for i, point in ipairs(data.path) do
            path[i] = vec3.new(point[1], point[2], point[3])
        end
        
        callback(path, nil, data.distance)
    end)
end

function NavigationClient:raycast(map_id, start_pos, end_pos, callback)
    local url = string.format(
        "%s/api/v1/raycast?map_id=%d&start_x=%.2f&start_y=%.2f&start_z=%.2f&end_x=%.2f&end_y=%.2f&end_z=%.2f",
        self.base_url,
        map_id,
        start_pos.x, start_pos.y, start_pos.z,
        end_pos.x, end_pos.y, end_pos.z
    )
    
    core.http_get(url, function(response)
        if not response then
            callback(nil, "HTTP request failed")
            return
        end
        
        local data = json.decode(response)
        if not data.success then
            callback(nil, data.error)
            return
        end
        
        callback({
            hit = data.hit,
            t = data.t,
            hit_point = data.hit_point and vec3.new(data.hit_point[1], data.hit_point[2], data.hit_point[3]),
            hit_normal = data.hit_normal and vec3.new(data.hit_normal[1], data.hit_normal[2], data.hit_normal[3])
        })
    end)
end

function NavigationClient:get_random_point(map_id, callback)
    local url = string.format("%s/api/v1/random?map_id=%d", self.base_url, map_id)
    
    core.http_get(url, function(response)
        if not response then
            callback(nil, "HTTP request failed")
            return
        end
        
        local data = json.decode(response)
        if not data.success then
            callback(nil, data.error)
            return
        end
        
        callback(vec3.new(data.position[1], data.position[2], data.position[3]))
    end)
end

return NavigationClient
```

### 6.2 Usage Example

```lua
local NavigationClient = require("navigation_client")

local nav = NavigationClient:new("http://localhost:3000")
local map_id = core.get_map_id()
local player_pos = player:get_position()
local target_pos = vec3.new(1000, 2000, 100)

-- Find path with Catmull-Rom smoothing
nav:find_path(map_id, player_pos, target_pos, "catmull_rom", function(path, error, distance)
    if error then
        core.log_error("Navigation error: " .. error)
        return
    end
    
    core.log(string.format("Found path: %d waypoints, %.1f yards", #path, distance))
    
    -- Start navigating
    movement:navigate(path)
end)
```

---

## 7. Performance Considerations

### 7.1 Response Time Expectations

| Operation | Expected Time |
|-----------|---------------|
| Short path (<50m) | <1ms |
| Medium path (50-200m) | 1-5ms |
| Long path (200m+) | 5-20ms |
| Raycast | <0.5ms |
| Random point | <0.1ms |
| Height query | <0.1ms |

### 7.2 Optimization Tips

1. **Batch Requests**: If possible, batch multiple queries
2. **Cache Results**: Cache frequently-used paths on the client
3. **Use Smoothing Wisely**: Catmull-Rom adds overhead but improves quality
4. **Preload Maps**: Configure server to preload frequently-used maps

---

## 8. Versioning

The API uses URL path versioning. Current version is `v1`.

Future versions will be available at `/api/v2/...` etc., while `v1` will remain available for backwards compatibility.

---

## 9. Changelog

### v1.0.0 (2026-02-02)
- Initial API release
- Pathfinding with smoothing
- Raycast, random point, height queries
- Health check endpoint
