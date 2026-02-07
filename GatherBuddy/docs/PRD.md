# GatherBuddy - Product Requirements Document (PRD)

**Version:** 1.0  
**Date:** January 31, 2025  
**Author:** Alex  
**Status:** Draft  

---

## 1. Executive Summary

GatherBuddy is an automated gathering bot for World of Warcraft that collects herbs and mining nodes along predefined routes. It operates using the Sylvannas API framework and integrates with an existing Rust-based navigation service for pathfinding.

### 1.1 Problem Statement

Manual gathering in WoW is time-consuming and repetitive. Players spend hours running circuits collecting resources for crafting or auction house sales. This tedious gameplay loop can be automated while maintaining human-like behavior to avoid detection.

### 1.2 Solution

An intelligent gathering bot that:
- Follows customizable routes defined in JSON profiles
- Detects and collects herbs and mining nodes automatically
- Navigates using server-side pathfinding for accurate movement
- Exhibits human-like behavior patterns to avoid detection
- Handles edge cases (combat, death, stuck situations) gracefully

### 1.3 Target Users

- Primary: Players who want to gather resources while AFK
- Secondary: Multi-boxers managing gathering alts
- Tertiary: Gold farmers optimizing resource collection

---

## 2. Goals & Success Metrics

### 2.1 Business Goals

| Goal | Description | Priority |
|------|-------------|----------|
| G1 | Automate herb/ore gathering with minimal user intervention | P0 |
| G2 | Maintain undetectable behavior patterns | P0 |
| G3 | Support multiple zones via profile system | P1 |
| G4 | Achieve 90%+ uptime during gathering sessions | P1 |
| G5 | Integrate seamlessly with existing navigation service | P0 |

### 2.2 Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Nodes gathered per hour | 60-100 (zone dependent) | Statistics module |
| Uptime without intervention | >4 hours | Session logging |
| Stuck recovery rate | >95% | Stuck events resolved |
| Death recovery rate | 100% | Corpse run completion |
| Profile load success | 100% for valid JSON | Validation errors |

### 2.3 Non-Goals (Out of Scope for v1.0)

- Combat rotation / killing mobs
- Fishing automation
- Auction house integration
- Multi-character coordination
- Flying mount 3D pathfinding (ground only for v1.0)
- Quest automation
- Dungeon/raid content

---

## 3. User Stories

### 3.1 Core User Stories

| ID | As a... | I want to... | So that... | Priority |
|----|---------|--------------|------------|----------|
| US1 | Player | Load a gathering profile for my zone | I can start gathering automatically | P0 |
| US2 | Player | Start/stop the bot with a single button | I have easy control | P0 |
| US3 | Player | See what the bot is currently doing | I can monitor progress | P0 |
| US4 | Player | Have the bot gather herbs and ore it finds | Resources are collected | P0 |
| US5 | Player | Have the bot use my mount for travel | Movement is efficient | P1 |
| US6 | Player | Have the bot handle my death | Sessions aren't interrupted | P0 |
| US7 | Player | Have the bot avoid enemies when possible | I don't die unnecessarily | P1 |
| US8 | Player | See statistics about my gathering session | I can evaluate efficiency | P2 |
| US9 | Player | Create custom profiles for my routes | I can optimize for my needs | P2 |
| US10 | Player | Have the bot behave like a human | I avoid detection | P0 |

### 3.2 User Story Details

#### US1: Load Gathering Profile
**Acceptance Criteria:**
- User can select from available profiles in a dropdown
- Profiles are loaded from `scripts_data/gatherbuddy/profiles/`
- Invalid profiles show clear error messages
- Profile metadata (name, zone, estimated time) displayed before loading

#### US4: Gather Nodes
**Acceptance Criteria:**
- Bot detects herbs within configured radius (default 80 yards)
- Bot detects ore veins within configured radius
- Bot approaches node and interacts
- Bot loots all items from gathering
- Bot blacklists depleted nodes temporarily
- Bot resumes route after gathering

#### US6: Death Handling
**Acceptance Criteria:**
- Bot detects player death within 1 second
- Bot releases spirit automatically (configurable delay)
- Bot navigates ghost to corpse
- Bot resurrects at corpse
- Bot resumes previous activity after resurrection

#### US10: Human-like Behavior
**Acceptance Criteria:**
- Action delays follow gaussian distribution, not uniform
- Path following includes 5-15% deviation from optimal
- Random pauses occur every 30-90 seconds of movement
- Occasional jumps while moving (1 per 30-90 seconds)
- Node gathering order is not always nearest-first

---

## 4. Feature Requirements

### 4.1 Feature List

| ID | Feature | Description | Priority | Dependency |
|----|---------|-------------|----------|------------|
| F1 | Profile System | JSON-based route definitions | P0 | - |
| F2 | Node Detection | Find herbs/ore via object manager | P0 | - |
| F3 | Gathering Logic | Interact with nodes, handle loot | P0 | F2 |
| F4 | Movement System | Navigate waypoints via nav service | P0 | - |
| F5 | Mount Management | Auto mount/dismount | P1 | F4 |
| F6 | Safety System | Enemy detection, combat handling | P1 | - |
| F7 | Death Recovery | Spirit release, corpse run | P0 | F4 |
| F8 | Stuck Recovery | Detect and resolve stuck situations | P1 | F4 |
| F9 | Control UI | Start/stop/status panel | P0 | - |
| F10 | Statistics | Session tracking and display | P2 | - |
| F11 | Settings | Configurable behavior options | P1 | - |
| F12 | Anti-Detection | Human-like behavior patterns | P0 | - |

### 4.2 Feature Specifications

#### F1: Profile System

**Requirements:**
- REQ-F1-01: Load profiles from `scripts_data/gatherbuddy/profiles/`
- REQ-F1-02: Validate JSON schema on load
- REQ-F1-03: Support waypoint types: path, hotspot, vendor, mailbox, safe
- REQ-F1-04: Support blackspot definitions (areas to avoid)
- REQ-F1-05: Store profile-specific settings (search radius, mount threshold)
- REQ-F1-06: Support route looping
- REQ-F1-07: Track current waypoint index across states

**Profile Schema Requirements:**
```
- version: string (semver)
- metadata: name, author, description, game_version, estimated_time
- requirements: min_skill, zone, map_id, requires_flying
- settings: loop, node_search_radius, waypoint_tolerance, mount_threshold
- waypoints[]: id, x, y, z, type, radius?, linger_time?
- blackspots[]: x, y, z, radius, reason?
```

#### F2: Node Detection

**Requirements:**
- REQ-F2-01: Scan all visible game objects each tick
- REQ-F2-02: Filter objects by `can_be_looted()` or `can_be_used()`
- REQ-F2-03: Match object names against herb/ore patterns
- REQ-F2-04: Filter by distance (configurable search radius)
- REQ-F2-05: Filter by blackspot (exclude nodes in blackspots)
- REQ-F2-06: Maintain temporary blacklist for recently gathered nodes
- REQ-F2-07: Sort candidates by priority (distance, value)
- REQ-F2-08: Publish NODE_DETECTED event with node details

#### F3: Gathering Logic

**Requirements:**
- REQ-F3-01: Face node before interacting (`core.input.look_at`)
- REQ-F3-02: Dismount if mounted before gathering
- REQ-F3-03: Interact with node (`core.input.use_object`)
- REQ-F3-04: Detect gathering cast start/completion
- REQ-F3-05: Handle loot window (`get_loot_item_count`, `loot_item`)
- REQ-F3-06: Close loot window after looting all items
- REQ-F3-07: Add gathered node to temporary blacklist
- REQ-F3-08: Handle gather interruption (move away, retry later)
- REQ-F3-09: Timeout after configurable duration (default 10s)

#### F4: Movement System

**Requirements:**
- REQ-F4-01: Use `simple_movement` module exclusively
- REQ-F4-02: Request paths from navigation service via HTTP
- REQ-F4-03: Follow waypoints with configurable tolerance
- REQ-F4-04: Handle hotspot waypoints (linger and scan)
- REQ-F4-05: Support path deviation for human-like movement
- REQ-F4-06: Track movement progress for stuck detection
- REQ-F4-07: Publish movement events (started, progress, completed)

#### F6: Safety System

**Requirements:**
- REQ-F6-01: Scan for enemies within detection radius
- REQ-F6-02: Calculate threat level (0=safe, 1=caution, 2=danger, 3=combat)
- REQ-F6-03: Skip node gathering if enemies too close (configurable)
- REQ-F6-04: Detect combat state change
- REQ-F6-05: Support flee behavior (run to safe waypoint)
- REQ-F6-06: Track player health for emergency actions

#### F12: Anti-Detection

**Requirements:**
- REQ-F12-01: Use gaussian distribution for all random delays
- REQ-F12-02: Add path deviation (5-15% offset from optimal)
- REQ-F12-03: Insert random pauses during movement
- REQ-F12-04: Add occasional jumps while moving
- REQ-F12-05: Vary gathering order (not always nearest)
- REQ-F12-06: Skip contested nodes when other players present
- REQ-F12-07: All timing constants should be configurable

---

## 5. Technical Constraints

### 5.1 Platform Constraints

| Constraint | Description |
|------------|-------------|
| TC1 | Must use Sylvannas API exclusively - no WoW Lua API |
| TC2 | Movement must use `simple_movement` module |
| TC3 | File I/O limited to `scripts_data/` directory |
| TC4 | HTTP requests via `core.http_get` only |
| TC5 | No access to WoW addon saved variables |

### 5.2 Performance Constraints

| Constraint | Target |
|------------|--------|
| Tick processing time | <5ms per tick |
| Memory usage | <50MB Lua heap |
| HTTP request latency | Handle async, don't block |
| Object scan frequency | Every tick (but cache results) |

### 5.3 Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Navigation Service | 1.0 | Pathfinding via HTTP |
| Sylvannas Core | Latest | Game object access |
| simple_movement | Latest | Movement control |
| unit_helper | Latest | Enemy detection |

---

## 6. Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Detection by Blizzard | Medium | High | Human-like behavior, configurable patterns |
| Navigation service downtime | Low | High | Fallback to direct movement, retry logic |
| Node spawn changes | Low | Medium | Pattern-based detection, easy to update |
| API changes in Sylvannas | Low | High | Abstraction layer, version checks |
| Stuck in geometry | Medium | Medium | Multi-strategy unstuck system |

---

## 7. Timeline

### 7.1 Development Phases

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Phase 1: Foundation | 2 days | Utils, EventBus, Constants, StateMachine |
| Phase 2: Core Systems | 3 days | BotManager, ProfileManager, Settings |
| Phase 3: Movement | 2 days | MovementModule, NavigationClient |
| Phase 4: Gathering | 3 days | NodeScanner, GatherModule, MountModule |
| Phase 5: Safety | 2 days | SafetyModule, death handling, stuck recovery |
| Phase 6: Polish | 2 days | UI, Statistics, testing, documentation |

**Total Estimated Time: 14 days**

### 7.2 Milestones

| Milestone | Date | Criteria |
|-----------|------|----------|
| M1: Core Loop | Day 5 | Bot can load profile and follow waypoints |
| M2: Gathering | Day 10 | Bot can detect and gather nodes |
| M3: Production Ready | Day 14 | All P0/P1 features complete, tested |

---

## 8. Appendix

### 8.1 Glossary

| Term | Definition |
|------|------------|
| Node | A gatherable object (herb or ore vein) |
| Hotspot | A waypoint where the bot lingers to scan for nodes |
| Blackspot | An area the bot should avoid |
| Profile | A JSON file defining a gathering route |
| Waypoint | A coordinate the bot navigates to |

### 8.2 References

- GATHERBUDDY_DESIGN.md - Architecture design document
- CLAUDE.md - Technical reference for Claude Code
- combined_documentation.md - Sylvannas API reference

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-31 | Alex | Initial draft |
