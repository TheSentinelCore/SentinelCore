# Sentinel Rebrand Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebrand every project in the workspace from *Buddy/*Lib names to the Sentinel brand, including directories, code identifiers, log prefixes, UI labels, Cargo crate names, and documentation.

**Architecture:** All directory renames happen first (single commit, preserves git history). Then each project's code references are updated in dedicated commits. Cross-project references and docs updated last. Verification sweep ensures no stale names remain.

**Tech Stack:** Lua (Sylvannas plugins), Rust (NavBuddy server), Git

**Reference:** See [sentinel-naming-design.md](2026-02-16-sentinel-naming-design.md) for the full naming map.

---

### Task 1: Rename All Directories + Update .gitignore

**Files:**
- Rename: `NavLib/` → `SentinelNavClient/`
- Rename: `NavBuddy/` → `SentinelNavServer/`
- Rename: `GatherBuddy/` → `SentinelGather/`
- Rename: `HeightQuery/` → `SentinelHeightQuery/` (gitignored, filesystem only)
- Rename: `debug_cursor/` → `SentinelDebugCursor/` (gitignored, filesystem only)
- Modify: `.gitignore`

**Step 1: git mv tracked directories**
```bash
git mv NavLib SentinelNavClient
git mv NavBuddy SentinelNavServer
git mv GatherBuddy SentinelGather
```

**Step 2: Filesystem rename gitignored directories**
```bash
mv HeightQuery SentinelHeightQuery
mv debug_cursor SentinelDebugCursor
```

**Step 3: Update .gitignore**
```
# Line 2: NavBuddy/reference → SentinelNavServer/reference
# Line 15: debug_cursor → SentinelDebugCursor
# Line 19: HeightQuery → SentinelHeightQuery
```

**Step 4: Commit**
```bash
git add .gitignore
git commit -m "refactor: rename all project directories for Sentinel rebrand"
```

---

### Task 2: SentinelNavClient — Core Identity (header, init, main)

**Files:**
- Modify: `SentinelNavClient/header.lua`
- Modify: `SentinelNavClient/init.lua`
- Modify: `SentinelNavClient/main.lua`

**Changes:**

`header.lua`:
- `plugin["name"] = "NavLib"` → `"Sentinel Navigation Client"`

`init.lua` — rename class `NavLibPlugin` → `SentinelNavClient` throughout:
- Comments: `NavLib` → `SentinelNavClient`
- `@class NavLibPlugin` → `@class SentinelNavClient`
- `local NavLibPlugin = {}` → `local SentinelNavClient = {}`
- `NavLibPlugin.__index = NavLibPlugin` → `SentinelNavClient.__index = SentinelNavClient`
- `NavLibPlugin.VERSION` → `SentinelNavClient.VERSION`
- `NavLibPlugin.NAME = "Sentinel Navigation"` → `"Sentinel Navigation Client"`
- All `function NavLibPlugin:*()` → `function SentinelNavClient:*()`
- All `NavLibPlugin.VERSION` refs → `SentinelNavClient.VERSION`
- Log prefixes `[NavLib]` → `[SentinelNavClient]`
- `return NavLibPlugin` → `return SentinelNavClient`

`main.lua` — rename local var and global:
- `local NavLibPlugin = require("init")` → `local SentinelNavClient = require("init")`
- All `NavLibPlugin:` calls → `SentinelNavClient:`
- `_G.NavLib = {` → `_G.SentinelNavClient = {`
- `setmetatable(_G.NavLib,` → `setmetatable(_G.SentinelNavClient,`
- `_G.NavLib = nil` → `_G.SentinelNavClient = nil`
- Log prefixes `[NavLib]` → `[SentinelNavClient]`
- `name = "NavLib"` → `name = "SentinelNavClient"`
- Menu label `"Sentinel Navigation"` → `"Sentinel Navigation Client"` (line 73)
- Comments: `NavLib` → `SentinelNavClient`

**WARNING:** Do NOT rename menu element string IDs (e.g. `"navlib_open"`) — these are persisted storage keys.

**Commit:** `"refactor(sentinel-nav-client): rebrand core identity files"`

---

### Task 3: SentinelNavClient — Facade + Core Modules

**Files:**
- Modify: `SentinelNavClient/Facade.lua`
- Modify: `SentinelNavClient/core/Defaults.lua`
- Modify: `SentinelNavClient/core/Movement.lua`
- Modify: `SentinelNavClient/core/Navigation.lua`
- Modify: `SentinelNavClient/core/Obstacle.lua`
- Modify: `SentinelNavClient/core/Visualizer.lua`

**Changes — all are comment/log prefix updates:**

`Facade.lua`: Comments `NavLib` → `SentinelNavClient`, log prefix `[NavLib]` → `[SentinelNavClient]`

`core/Defaults.lua`: Comments `NavLib` → `SentinelNavClient`

`core/Movement.lua`: Comment `NavBuddy` → `SentinelNavServer`

`core/Navigation.lua`: 5 comments `NavBuddy` → `SentinelNavServer`

`core/Obstacle.lua`: Comment `NavBuddy` → `SentinelNavServer`

`core/Visualizer.lua`: Comments `NavLib` → `SentinelNavClient`

**Commit:** `"refactor(sentinel-nav-client): rebrand facade and core modules"`

---

### Task 4: SentinelNavClient — UI Files

**Files:**
- Modify: `SentinelNavClient/ui/window.lua`
- Modify: `SentinelNavClient/ui/tabs/debug_tab.lua`
- Modify: `SentinelNavClient/ui/tabs/pathfinding_tab.lua`

**Changes:**

`ui/window.lua`:
- Comments `NavLib` → `SentinelNavClient`
- `title = "NavLib"` → `"Sentinel Navigation Client"`
- Log prefix `[NavLib]` → `[SentinelNavClient]`

`ui/tabs/debug_tab.lua` (12 log messages):
- All `[NavLib Debug]` → `[SentinelNavClient Debug]`
- All `[NavLib]` → `[SentinelNavClient]`

`ui/tabs/pathfinding_tab.lua`:
- Comment `NavBuddy` → `SentinelNavServer`

**Commit:** `"refactor(sentinel-nav-client): rebrand UI files"`

---

### Task 5: SentinelNavClient — Documentation

**Files:**
- Modify: `SentinelNavClient/docs/README.md`
- Modify: `SentinelNavClient/docs/API.md`

**Changes:** Global find-replace in both files:
- `NavLib` → `SentinelNavClient`
- `NavBuddy` → `SentinelNavServer`
- `_G.NavLib` → `_G.SentinelNavClient`

**Commit:** `"docs(sentinel-nav-client): rebrand documentation"`

---

### Task 6: SentinelNavServer — Cargo.toml + Rust Source

**Files:**
- Modify: `SentinelNavServer/Cargo.toml`
- Modify: `SentinelNavServer/src/main.rs`
- Modify: `SentinelNavServer/src/lib.rs`
- Modify: `SentinelNavServer/src/pipeline.rs`
- Modify: `SentinelNavServer/src/routes/health.rs`
- Modify: `SentinelNavServer/tests/integration_tests.rs`
- Modify: `SentinelNavServer/config.toml`

**Changes:**

`Cargo.toml`:
- `authors = ["NavBuddy Contributors"]` → `["Sentinel Contributors"]`
- `repository` URL — update or remove
- `name = "navbuddy"` → `"sentinel-nav-server"` (package, lib, and bin sections)

`src/main.rs`:
- Doc comment `NavBuddy` → `Sentinel Navigation Server`
- `"navbuddy=info"` → `"sentinel_nav_server=info"` (tracing directive)
- `"NavBuddy v{}"` → `"Sentinel Navigation Server v{}"`

`src/lib.rs`: Doc comments `NavBuddy` → `Sentinel Navigation Server`

`src/pipeline.rs`: Comment `NavBuddy` → `SentinelNavServer`

`src/routes/health.rs`: Comment `NavBuddy` → `Sentinel Navigation Server`

`tests/integration_tests.rs`:
- Comment `NavBuddy` → `Sentinel Navigation Server`
- `use navbuddy::` → `use sentinel_nav_server::` (critical — hyphens become underscores in Rust)

`config.toml`: Comments `NavBuddy` → `Sentinel Navigation Server`

**Step: Verify Rust build**
```bash
cd SentinelNavServer && cargo check
```

**Commit:** `"refactor(sentinel-nav-server): rebrand NavBuddy to Sentinel Navigation Server"`

---

### Task 7: SentinelNavServer — CLAUDE.md

**Files:**
- Modify: `SentinelNavServer/CLAUDE.md`

**Changes:** Global find-replace:
- `NavBuddy` → `Sentinel Navigation Server` (in prose) / `SentinelNavServer` (in paths/code)
- `navbuddy` → `sentinel-nav-server` (crate refs) / `sentinel_nav_server` (Rust code refs)

**Commit:** `"docs(sentinel-nav-server): rebrand CLAUDE.md"`

---

### Task 8: SentinelGather — Core Identity (header, init, main)

**Files:**
- Modify: `SentinelGather/header.lua`
- Modify: `SentinelGather/init.lua`
- Modify: `SentinelGather/main.lua`

**Changes:**

`header.lua`:
- `plugin["name"] = "GatherBuddy"` → `"Sentinel Gather"`

`init.lua` — rename class `GatherBuddy` → `SentinelGather` throughout:
- `@class GatherBuddy` → `@class SentinelGather`
- `local GatherBuddy = {}` → `local SentinelGather = {}`
- `GatherBuddy.__index` → `SentinelGather.__index`
- `GatherBuddy.VERSION`, `GatherBuddy.NAME` → `SentinelGather.*`
- `GatherBuddy.NAME = "GatherBuddy"` → `"Sentinel Gather"`
- All `function GatherBuddy:*()` → `function SentinelGather:*()`
- All `core.log("[GatherBuddy]` → `core.log("[SentinelGather]`
- Comments `GatherBuddy` → `SentinelGather`
- `return GatherBuddy` → `return SentinelGather`

`main.lua`:
- `local GatherBuddy = require("init")` → `local SentinelGather = require("init")`
- All `GatherBuddy:` calls → `SentinelGather:`
- Button label `"GatherBuddy"` → `"Sentinel Gather"`
- `name = "GatherBuddy"` → `"SentinelGather"`
- Log prefixes `[GatherBuddy]` → `[SentinelGather]`

**WARNING:** Do NOT rename menu element string IDs (e.g. `"gb_gather_herbs"`) — these are persisted storage keys.

**Commit:** `"refactor(sentinel-gather): rebrand core identity files"`

---

### Task 9: SentinelGather — BotManager (Cross-Project References)

**Files:**
- Modify: `SentinelGather/core/BotManager.lua`

**Changes — this is the critical cross-project integration point:**
- `_G.NavLib and _G.NavLib.facade` → `_G.SentinelNavClient and _G.SentinelNavClient.facade`
- `self._navlib = _G.NavLib.facade` → `self._navlib = _G.SentinelNavClient.facade`
- Log: `"Using NavLib shared facade"` → `"Using SentinelNavClient shared facade"`
- Error: `"NavLib plugin not loaded. Load NavLib before GatherBuddy"` → `"SentinelNavClient plugin not loaded. Load SentinelNavClient before SentinelGather"`
- Comments: `NavLib` → `SentinelNavClient`, `GatherBuddy` → `SentinelGather`

**Note:** Internal field names like `self._navlib`, `self._navlib_available` etc. can optionally stay as-is (they're private implementation details) or be renamed for consistency. Recommend keeping them to minimize diff noise.

**Commit:** `"refactor(sentinel-gather): update cross-project NavLib references to SentinelNavClient"`

---

### Task 10: SentinelGather — UI Files

**Files:**
- Modify: `SentinelGather/ui/window.lua`
- Modify: `SentinelGather/ui/SettingsSync.lua`
- Modify: `SentinelGather/ui/tabs/gather_tab.lua`
- Modify: `SentinelGather/ui/tabs/profile_tab.lua`
- Modify: `SentinelGather/ui/tabs/safety_tab.lua`
- Modify: `SentinelGather/ui/tabs/stats_tab.lua`

**Changes:**

`ui/window.lua`:
- Comments `GatherBuddy` → `SentinelGather`
- `title = "GatherBuddy"` → `"Sentinel Gather"`

`ui/SettingsSync.lua`: Comments `GatherBuddy` → `SentinelGather`

All tab files:
- `local GatherBuddy = require("init")` → `local SentinelGather = require("init")`
- All `GatherBuddy:` method calls → `SentinelGather:`
- Log prefixes `[GatherBuddy]` → `[SentinelGather]`
- Comments `GatherBuddy` → `SentinelGather`

**Commit:** `"refactor(sentinel-gather): rebrand UI files"`

---

### Task 11: SentinelGather — Remaining Modules + Lib

**Files:**
- Modify: `SentinelGather/lib/Logger.lua`
- Modify: `SentinelGather/core/Constants.lua`
- Modify: `SentinelGather/core/ModuleFactory.lua`
- Modify: `SentinelGather/core/StateMachine.lua`
- Modify: `SentinelGather/core/Settings.lua`
- Modify: `SentinelGather/modules/Gather.lua`
- Modify: `SentinelGather/modules/Mount.lua`
- Modify: `SentinelGather/modules/NodeScanner.lua`
- Modify: `SentinelGather/modules/Inventory.lua`
- Modify: `SentinelGather/modules/Safety.lua`
- Modify: `SentinelGather/modules/Statistics.lua`
- Modify: `SentinelGather/modules/ProfileManager.lua`

**Changes:**

`lib/Logger.lua`: Default name `"GatherBuddy"` → `"SentinelGather"`

`core/Constants.lua`: Comment `NavBuddy` → `SentinelNavServer`, comment `GatherBuddy` → `SentinelGather`

All other files: Comments `"in GatherBuddy folder"` → `"in SentinelGather folder"`

`modules/ProfileManager.lua`: JSON template `"author": "GatherBuddy"` → `"SentinelGather"`

**Commit:** `"refactor(sentinel-gather): rebrand remaining modules"`

---

### Task 12: SentinelGather — Documentation

**Files:**
- Modify: `SentinelGather/docs/*.md` (7 files)
- Modify: `SentinelGather/docs/implementation/*.md` (5 files)
- Optional rename: `GATHERBUDDY_DESIGN.md` → `SENTINEL_GATHER_DESIGN.md`

**Changes:** Global find-replace across all doc files:
- `GatherBuddy` → `SentinelGather` / `Sentinel Gather`
- `NavBuddy` → `SentinelNavServer`
- `NavLib` → `SentinelNavClient`

**Commit:** `"docs(sentinel-gather): rebrand documentation"`

---

### Task 13: SentinelHeightQuery + SentinelDebugCursor (Gitignored)

**Files:**
- Modify: `SentinelHeightQuery/header.lua`
- Modify: `SentinelHeightQuery/main.lua`
- Modify: `SentinelDebugCursor/header.lua`
- Modify: `SentinelDebugCursor/main.lua`

**Changes:**

SentinelHeightQuery:
- `plugin["name"] = "Height Query"` → `"Sentinel Height Query"`
- `_G.NavLib` → `_G.SentinelNavClient` (all occurrences)
- `"NavBuddy: "` → `"SentinelNavServer: "`
- `"NavLib: not loaded"` → `"SentinelNavClient: not loaded"`
- `[HeightQuery]` log prefix → `[SentinelHeightQuery]`
- Comment `NavBuddy HeightEntry` → `SentinelNavServer HeightEntry`

SentinelDebugCursor:
- `plugin["name"] = "Debug Cursor"` → `"Sentinel Debug Cursor"`
- `[DebugCursor]` log prefix → `[SentinelDebugCursor]`

**No commit** (these are gitignored).

---

### Task 14: Root CLAUDE.md + MEMORY.md

**Files:**
- Modify: `CLAUDE.md` (gitignored but critical for Claude context)
- Modify: `MEMORY.md` (at `C:\Users\Levi\.claude\projects\...\memory\MEMORY.md`)

**Changes:**

`CLAUDE.md`: Full rebrand of all project references:
- Projects table: directory names, descriptions
- Cross-project integration diagram
- Build commands: `cd NavBuddy` → `cd SentinelNavServer`, etc.
- GatherBuddy Structure section → SentinelGather
- All prose references

`MEMORY.md`: Update remaining old-name references in MMap section:
- `NavBuddy mmaps` → `SentinelNavServer mmaps`
- `### NavBuddy` → `### SentinelNavServer`

**No commit** (both gitignored).

---

### Task 15: Verification Sweep

**Step 1: Grep for stale references in tracked files**
```bash
git grep -l "NavLib" -- ':!docs/plans/'
git grep -l "NavBuddy" -- ':!docs/plans/'
git grep -l "GatherBuddy" -- ':!docs/plans/'
git grep -l "navbuddy" -- ':!docs/plans/'
```

**Step 2: Check untracked plugin files**
```bash
grep -r "NavLib\|NavBuddy\|GatherBuddy" SentinelHeightQuery/ SentinelDebugCursor/
```

**Step 3: Verify Rust builds**
```bash
cd SentinelNavServer && cargo check
```

**Step 4: Fix any remaining references found**

**Step 5: Final commit if needed**
```bash
git commit -m "refactor: fix remaining stale name references"
```
