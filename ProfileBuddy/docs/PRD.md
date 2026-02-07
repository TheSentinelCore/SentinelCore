# ProfileBuddy - Product Requirements Document

## Executive Summary

ProfileBuddy is a command-line tool that generates optimized gathering profiles for GatherBuddy bot from GatherMate2 addon data. It enables users to create unique, efficient gathering routes for World of Warcraft.

## Problem Statement

Creating gathering profiles manually is tedious and produces suboptimal routes. GatherMate2 contains 60,000+ crowdsourced node locations but no way to convert this data into usable bot profiles.

## Target Users

- GatherBuddy users who want automated profile generation
- Players who want optimized gathering routes
- Bot operators who need unique profiles to avoid detection patterns

## Core Requirements

### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1 | Parse GatherMate2_Data Lua files (Era + TBC) | Must Have |
| FR-2 | Display available zones with node counts | Must Have |
| FR-3 | Allow selection of specific herbs/ores | Must Have |
| FR-4 | Generate optimized routes using TSP algorithm | Must Have |
| FR-5 | Generate optimized routes using Cluster algorithm | Should Have |
| FR-6 | Generate optimized routes using Density algorithm | Should Have |
| FR-7 | Apply randomization for unique profiles | Must Have |
| FR-8 | Output GatherBuddy-compatible JSON profiles | Must Have |
| FR-9 | Preview route before generation | Should Have |
| FR-10 | Support multiple game versions | Must Have |

### Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | Parse all GatherMate2 data in < 5 seconds | Performance |
| NFR-2 | Generate profile in < 2 seconds | Performance |
| NFR-3 | Run on Windows, Linux, macOS | Compatibility |
| NFR-4 | No external runtime dependencies | Deployment |
| NFR-5 | Single binary distribution | Deployment |

## User Stories

### US-1: Zone Selection
As a user, I want to select a zone from a list so that I can generate profiles for specific areas.

**Acceptance Criteria:**
- Zones are listed with name and node count
- Zones are grouped by continent
- User can filter by game version (Era/TBC)

### US-2: Node Filtering
As a user, I want to select specific herbs and ores so that I only gather what I need.

**Acceptance Criteria:**
- All available node types for selected zone are shown
- User can check/uncheck individual node types
- "Select All" and "Clear All" options available

### US-3: Route Generation
As a user, I want to generate an optimized route so that I can gather efficiently.

**Acceptance Criteria:**
- Route minimizes total travel distance
- Hotspots are placed at node-dense areas
- Profile is immediately usable by GatherBuddy

### US-4: Unique Profiles
As a user, I want each generated profile to be unique so that I avoid detection patterns.

**Acceptance Criteria:**
- No two generated profiles are identical
- Randomization options are configurable
- Route still maintains optimization

## Out of Scope (v1.0)

- GUI application (future version)
- Real-time route editing
- Profile import/merge functionality
- Multi-zone routes
- Flying routes

## Success Metrics

| Metric | Target |
|--------|--------|
| Profile generation success rate | 100% |
| Route efficiency vs manual | >90% |
| GatherBuddy compatibility | 100% |
| User satisfaction | >4/5 stars |
