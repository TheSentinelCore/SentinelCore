# Sentinel Branding — Naming Convention Design

## Context

The workspace is being rebranded under the "Sentinel" name. This is a **full rebrand**: display names, directory names, package names, Lua globals, log prefixes — everything. Each Lua plugin needs its own flat top-level directory (required by Sylvannas loader). Code identifiers use short forms for brevity.

## Naming Map

| Old Name | Display Name | Short Form | Directory | Package Name |
|----------|-------------|------------|-----------|-------------|
| NavLib | Sentinel Navigation Client | `SentinelNavClient` | `SentinelNavClient/` | — |
| NavBuddy | Sentinel Navigation Server | `SentinelNavServer` | `SentinelNavServer/` | `sentinel-nav-server` |
| GatherBuddy | Sentinel Gather | `SentinelGather` | `SentinelGather/` | — |
| *(new)* | Sentinel Quest | `SentinelQuest` | `SentinelQuest/` | — |
| HeightQuery | Sentinel Height Query | `SentinelHeightQuery` | `SentinelHeightQuery/` | — |
| Debug Cursor | Sentinel Debug Cursor | `SentinelDebugCursor` | `SentinelDebugCursor/` | — |

## Identifier Conventions

| Context | Format | Example |
|---------|--------|---------|
| Lua global | PascalCase short | `_G.SentinelNavClient` |
| Log prefix | `[ShortForm]` | `[SentinelNavClient]` |
| plugin["name"] | Full display name | `"Sentinel Navigation Client"` |
| Rust crate name | kebab-case | `sentinel-nav-server` |
| Rust binary | kebab-case | `sentinel-nav-server` |
| Directory | PascalCase short | `SentinelNavClient/` |
| Internal class names | PascalCase | `SentinelNavClient`, `SentinelGather` |

## Scope of Changes Per Project

### SentinelNavClient (was NavLib)
- `header.lua`: plugin["name"] → "Sentinel Navigation Client"
- `init.lua`: NAME, VERSION, _G export (`_G.SentinelNavClient`), log prefixes
- `main.lua`: menu rendering, references
- All module files: log prefixes, internal references
- Directory: `NavLib/` → `SentinelNavClient/`

### SentinelNavServer (was NavBuddy)
- `Cargo.toml`: workspace name, package name, authors, repo URL
- `src/main.rs`: version string, startup banner, logging
- `config.toml`: comments
- Sub-crate names remain unchanged (detour, detour-sys, tc-mmap, etc. — they're generic)
- Directory: `NavBuddy/` → `SentinelNavServer/`

### SentinelGather (was GatherBuddy)
- `header.lua`: plugin["name"] → "Sentinel Gather"
- `init.lua`: NAME, all references, _G export
- `main.lua`: menu rendering, description
- All module files: log prefixes, class references
- `NavigationClient.lua`: references to NavBuddy → SentinelNavServer
- Directory: `GatherBuddy/` → `SentinelGather/`

### SentinelHeightQuery (was HeightQuery)
- `header.lua`: plugin["name"] → "Sentinel Height Query"
- `main.lua`: references to NavBuddy/NavLib → Sentinel equivalents
- Directory: `HeightQuery/` → `SentinelHeightQuery/`

### SentinelDebugCursor (was Debug Cursor)
- `header.lua`: plugin["name"] → "Sentinel Debug Cursor"
- Directory: `Debug Cursor/` → `SentinelDebugCursor/`

### Docs & Config
- `CLAUDE.md`: All project references updated
- `MEMORY.md`: NavBuddy/NavLib references updated
- Any cross-references between projects
