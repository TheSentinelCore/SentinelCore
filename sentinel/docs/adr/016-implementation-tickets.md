---
id: 16
title: Implementation Tickets — Sentinel Questing Importer
type: Tracking
status: In Progress
---

## Waves (Per-Phase)

### Wave 1 — Core Parser ✅ Complete

| Issue | Description | Status |
|-------|-------------|--------|
| 1 | GuideSplitter — extract `RegisterGuide([[...]])` block | ✅ Done |
| 2 | Lexer — tokenize guide into tokens | ✅ Done |
| 3 | StepBuilder — build Step AST nodes | ✅ Done |
| 4 | LabelGraph — resolve label references | ✅ Done |

### Wave 2 — Project Builder ✅ Complete

| Issue | Description | Status |
|-------|-------------|--------|
| 5 | MapperState — entity resolution state (NPC/quest caching) | ✅ Done |
| 6 | resolve_npc_by_entry — cache-resolved NPC lookup | ✅ Done |
| 7 | resolve_npc_by_name — name-based NPC resolution | ✅ Done |
| 8 | resolve_quest — quest + giver/finisher resolution | ✅ Done |
| 9 | operation_name — derive op name from label or goto | ✅ Done |
| 10 | build_step_actions — map commands to ActionPayload | ✅ Done |
| 11 | Command mappings: accept, turnin, goto, vendor, train, fly, hs, abandon, fp, equip | ✅ Done |
| 12 | Command mappings: mob, collect, item, use, waypoint, trainer, complete, skill | ✅ Done |
| 13 | diagnostics — unresolved entities as warnings | ✅ Done |
| 14 | Tests: 13 integration tests covering all command types | ✅ Done |

### Wave 3 — Name Hint Resolution ✅ Complete

| Issue | Description | Status |
|-------|-------------|--------|
| 34 | Extract NPC names from `|cRXP_FRIENDLY_Name|r` patterns | ✅ Done |
| 35 | Fallback NPC resolution using name hints | ✅ Done |
| 36 | Name hints tests (3 unit tests) | ✅ Done |

### Wave 4 — Corpus Validation ✅ Complete

| Issue | Description | Status |
|-------|-------------|--------|
| 42 | Validate full TBC alliance guide corpus imports | ✅ Done |

## Test Result: 888 steps parsed across 6 alliance guides, 1275 diagnostics (unresolved entities).

### Phase 5 — Validator ✅ Complete

| Issue | Description | Status |
|-------|-------------|--------|
| 20 | validator crate setup | ✅ Done |
| 21 | Duplicate NPC detection | ✅ Done |
| 22 | Duplicate Quest detection | ✅ Done |
| 23 | Broken NPC reference detection | ✅ Done |
| 24 | Unresolved Quest detection | ✅ Done |
| 25 | Circular condition detection | ⏳ (postponed - needs expression parsing) |
| 26 | Unused variable detection | ⏳ (postponed - needs expression parsing) |

---

### Phase 6 — Compiler ✅ Complete

| Issue | Description | Status |
|-------|-------------|--------|
| 30 | Compiler crate setup | ✅ Done |
| 31 | Reference Resolver (UUID → entry) | ✅ Done |
| 32 | AuthorAction → RuntimeAction lowering | ✅ Done |
| 33 | RuntimeProfile generation | ✅ Done |
| 34 | Compiler tests | ✅ Done (2 tests) |

---

### Phase 7 — Runtime Loader (Complete)

| Issue | Description | Status |
|-------|-------------|--------|
| 40 | Runtime crate setup | ✅ Done |
| 41 | RuntimeState management | ✅ Done |

---

## Test Coverage

- 14 mapper tests (13 command + 1 corpus)
- 3 validator tests + 2 unit tests
- 2 compiler tests
- 3 name hints tests
- 7 parser tests
- 4 model tests
- 6 query client tests

**Total: 35 tests passing**

## Total Progress

- **Phase 1**: Shared Models ✅
- **Phase 2**: QueryClient ✅
- **Phase 3**: ProjectLoader - (skipped - using direct Project access)
- **Phase 4**: Importer ✅ (Waves 1-4 complete)
- **Phase 5**: Validator ✅ (core checks complete)
- **Phase 6**: Compiler ✅ (reference resolver complete)
- **Phase 7**: Runtime Loader ✅