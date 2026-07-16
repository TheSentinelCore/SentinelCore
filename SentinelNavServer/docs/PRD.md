# Product Requirements Document (PRD)

## AmeisenNav-RS: Rust Navigation Mesh Server

**Version:** 1.0.0  
**Last Updated:** 2026-02-02  
**Status:** Draft  
**Author:** Alex (Team Lead)

---

## 1. Executive Summary

AmeisenNav-RS is a high-performance navigation mesh server that provides pathfinding services for World of Warcraft bot automation. It replaces the existing C++ AmeisenNavigation implementation with a Rust-based HTTP service, offering improved performance, memory safety, and easier integration with the Sylvannas bot framework.

### 1.1 Problem Statement

The current WoW bot automation stack requires navigation mesh pathfinding capabilities. The existing AmeisenNavigation C++ server works but has limitations:

- Tight coupling requires embedded integration
- Limited concurrent request handling
- Memory safety concerns in multi-threaded scenarios
- Difficult to deploy and maintain

### 1.2 Solution Overview

Build a standalone Rust HTTP service that:
- Loads TrinityCore-generated navigation meshes
- Exposes pathfinding via simple HTTP GET endpoints
- Handles concurrent requests from multiple bot instances
- Provides path smoothing for human-like movement

---

## 2. Goals and Non-Goals

### 2.1 Goals

| ID | Goal | Priority |
|----|------|----------|
| G1 | Full compatibility with TrinityCore mmap format | P0 |
| G2 | HTTP API accessible from Lua clients (GET only) | P0 |
| G3 | Sub-5ms latency for typical pathfinding requests | P0 |
| G4 | Support concurrent requests from 10+ bot instances | P1 |
| G5 | Path smoothing algorithms for human-like movement | P1 |
| G6 | Lazy tile loading with intelligent caching | P1 |
| G7 | Docker containerization for easy deployment | P2 |
| G8 | Configurable via TOML config file | P2 |

### 2.2 Non-Goals

| ID | Non-Goal | Rationale |
|----|----------|-----------|
| NG1 | Real-time navmesh generation | Use pre-generated TrinityCore mmaps |
| NG2 | Dynamic obstacle avoidance | Static navmesh only |
| NG3 | Flying/swimming path generation | Ground-based paths only (v1) |
| NG4 | Embedded library mode | HTTP service only |
| NG5 | GUI/visualization | Command-line server only |

---

## 3. User Stories

### 3.1 Bot Developer (Primary User)

> As a bot developer, I want to request paths between two world coordinates so that my bot can navigate autonomously.

**Acceptance Criteria:**
- Can request path via HTTP GET with coordinates
- Receives array of waypoints in response
- Response includes path distance and computation time
- Works with existing Sylvannas Lua API

### 3.2 System Administrator

> As a system administrator, I want to configure the server via file so that I can tune performance for my hardware.

**Acceptance Criteria:**
- Configuration via TOML file
- Can specify mmap path, port, thread count
- Can preload specific maps at startup
- Health check endpoint for monitoring

### 3.3 Multi-Bot Operator

> As an operator running multiple bots, I want the server to handle concurrent requests so that all bots can navigate simultaneously.

**Acceptance Criteria:**
- No request blocking or queuing under normal load
- Consistent latency across concurrent requests
- Graceful degradation under heavy load

---

## 4. Functional Requirements

### 4.1 Core Pathfinding (FR-PATH)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-PATH-001 | Find optimal path between two 3D world coordinates | P0 |
| FR-PATH-002 | Return path as array of 3D waypoints | P0 |
| FR-PATH-003 | Support path distance calculation | P0 |
| FR-PATH-004 | Handle unreachable destinations gracefully | P0 |
| FR-PATH-005 | Support constrained movement (moveAlongSurface) | P1 |
| FR-PATH-006 | Support line-of-sight raycast queries | P1 |

### 4.2 Random Point Generation (FR-RAND)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-RAND-001 | Generate random navigable point on map | P1 |
| FR-RAND-002 | Generate random point within radius of position | P1 |

### 4.3 Path Smoothing (FR-SMOOTH)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-SMOOTH-001 | Implement Chaikin curve subdivision | P1 |
| FR-SMOOTH-002 | Implement Catmull-Rom spline interpolation | P1 |
| FR-SMOOTH-003 | Implement Bezier curve smoothing | P2 |
| FR-SMOOTH-004 | Allow smoothing algorithm selection per request | P1 |

### 4.4 Map Loading (FR-MAP)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-MAP-001 | Load TrinityCore .mmap metadata files | P0 |
| FR-MAP-002 | Load TrinityCore .mmtile data files | P0 |
| FR-MAP-003 | Support lazy tile loading on demand | P1 |
| FR-MAP-004 | Support map preloading at startup | P1 |
| FR-MAP-005 | Implement tile caching with LRU eviction | P2 |

### 4.5 HTTP API (FR-API)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-API-001 | All endpoints use HTTP GET method | P0 |
| FR-API-002 | Parameters passed via query string | P0 |
| FR-API-003 | Responses in JSON format | P0 |
| FR-API-004 | Health check endpoint at /health | P1 |
| FR-API-005 | Include timing metrics in responses | P2 |

---

## 5. Non-Functional Requirements

### 5.1 Performance (NFR-PERF)

| ID | Requirement | Target | Priority |
|----|-------------|--------|----------|
| NFR-PERF-001 | Short path latency (<50m) | <1ms | P0 |
| NFR-PERF-002 | Medium path latency (50-200m) | <5ms | P0 |
| NFR-PERF-003 | Long path latency (200m+) | <20ms | P1 |
| NFR-PERF-004 | Tile load latency | <10ms | P1 |
| NFR-PERF-005 | Concurrent request throughput | >100 req/s | P1 |
| NFR-PERF-006 | Memory usage (continent loaded) | <2GB | P1 |

### 5.2 Reliability (NFR-REL)

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-REL-001 | No crashes on invalid input | P0 |
| NFR-REL-002 | Graceful handling of missing tiles | P0 |
| NFR-REL-003 | Timeout protection on long queries | P1 |
| NFR-REL-004 | Memory leak free operation | P0 |

### 5.3 Compatibility (NFR-COMPAT)

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-COMPAT-001 | TrinityCore 3.3.5a mmap format | P0 |
| NFR-COMPAT-002 | Sylvannas core.http_get API | P0 |
| NFR-COMPAT-003 | Linux (Ubuntu 22.04+) | P0 |
| NFR-COMPAT-004 | Windows 10+ | P1 |

### 5.4 Maintainability (NFR-MAINT)

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-MAINT-001 | Comprehensive logging | P1 |
| NFR-MAINT-002 | Unit test coverage >80% | P1 |
| NFR-MAINT-003 | Integration tests with real mmaps | P1 |
| NFR-MAINT-004 | Documentation for all public APIs | P1 |

---

## 6. Technical Constraints

### 6.1 FFI Constraints

- **C++ Interop**: Must use custom FFI bindings via bindgen
- **No Third-Party Wrappers**: Cannot use divert or other Rust Detour crates
- **C Wrapper Layer**: Required because bindgen cannot bind C++ class methods directly

### 6.2 HTTP Constraints

- **GET Only**: Sylvannas Lua API only supports core.http_get
- **Query Parameters**: All inputs must be URL query parameters
- **JSON Response**: Responses must be parseable by Lua json.decode

### 6.3 Memory Constraints

- **Thread Safety**: dtNavMeshQuery is NOT thread-safe, must use query pool
- **Tile Ownership**: DT_TILE_FREE_DATA flag transfers memory ownership to Detour
- **Large NavMeshes**: Must enable DT_POLYREF64 for WoW-scale worlds

---

## 7. Success Metrics

### 7.1 Performance KPIs

| Metric | Target | Measurement |
|--------|--------|-------------|
| P50 Latency | <2ms | Request timing logs |
| P99 Latency | <10ms | Request timing logs |
| Throughput | >100 req/s | Load testing |
| Memory Usage | <2GB | Process monitoring |

### 7.2 Quality KPIs

| Metric | Target | Measurement |
|--------|--------|-------------|
| Test Coverage | >80% | cargo tarpaulin |
| Build Time | <2min | CI pipeline |
| Error Rate | <0.1% | Error logging |

### 7.3 Adoption KPIs

| Metric | Target | Measurement |
|--------|--------|-------------|
| Bot Integration | 1 week | Development time |
| Path Accuracy | 100% match with AmeisenNav | Comparison testing |

---

## 8. Timeline and Milestones

### Phase 1: FFI Foundation (Week 1-2)
- [ ] Set up project structure
- [ ] Create C wrapper layer (wrapper.h/wrapper.cpp)
- [ ] Configure bindgen build
- [ ] Verify bindings compile and link

### Phase 2: Safe Wrappers (Week 2-3)
- [ ] Implement NavMesh wrapper with RAII
- [ ] Implement NavMeshQuery wrapper
- [ ] Implement QueryFilter wrapper
- [ ] Error types and status handling

### Phase 3: TrinityCore Loader (Week 3-4)
- [ ] Implement mmap/mmtile parsing
- [ ] Build MmapLoader with lazy loading
- [ ] Multi-map manager
- [ ] Test with real TC files

### Phase 4: HTTP Service (Week 4-5)
- [ ] Set up Axum router
- [ ] Implement pathfinding endpoint
- [ ] Implement spatial query endpoints
- [ ] Concurrent request handling

### Phase 5: Path Smoothing (Week 5)
- [ ] Implement Chaikin algorithm
- [ ] Implement Catmull-Rom splines
- [ ] Add smoothing parameter to API

### Phase 6: Production Hardening (Week 6)
- [ ] Comprehensive logging
- [ ] Configuration system
- [ ] Docker containerization
- [ ] Performance optimization

---

## 9. Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| FFI binding complexity | High | Medium | Start with minimal API surface |
| Memory safety in FFI | High | Medium | Extensive testing, address sanitizer |
| Performance regression | Medium | Low | Benchmark against AmeisenNav |
| TrinityCore format changes | Low | Low | Version detection in loader |

---

## 10. Dependencies

### 10.1 External Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Recast/Detour | 1.6+ | Navigation mesh library |
| Axum | 0.7+ | HTTP framework |
| Tokio | 1.35+ | Async runtime |
| bindgen | 0.69+ | FFI generation |
| cc | 1.0+ | C++ compilation |

### 10.2 Internal Dependencies

| Dependency | Purpose |
|------------|---------|
| Sylvannas core.lua | Lua HTTP client API |
| TrinityCore mmaps | Pre-generated navigation meshes |

---

## 11. Appendix

### A. Glossary

| Term | Definition |
|------|------------|
| mmap | Memory-mapped navigation mesh file |
| mmtile | Individual tile within navigation mesh |
| NavMesh | Data structure representing walkable areas |
| NavMeshQuery | Object for performing pathfinding queries |
| dtPolyRef | Reference handle to polygon in navmesh |

### B. Related Documents

- [TDD.md](TDD.md) - Technical Design Document
- [API_DESIGN.md](API_DESIGN.md) - API Specification
- [ARCHITECTURE.md](ARCHITECTURE.md) - System Architecture
- [TICKETS.md](TICKETS.md) - Implementation Tasks
