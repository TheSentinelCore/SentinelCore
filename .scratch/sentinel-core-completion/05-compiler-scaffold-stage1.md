---
id: 5
title: "Compiler Scaffold + Stage 1 Structural Validation"
state: open
labels: ["enhancement", "ready-for-agent", "size:large"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 05 — Compiler Scaffold + Stage 1 Structural Validation

**What to build:** Create the `sentinel-compiler` crate with the public `compile()` API and implement Stage 1 (Structural Validation) — the first stage of the 7-stage pipeline from ADR 008.

**Blocked by:** #1, #2 (QueryServer running + schema types proven)

**Acceptance criteria:**

- [ ] `sentinel-compiler` crate added to workspace with dependencies: `sentinel-schema`, `serde`, `serde_json`, `uuid`, `anyhow`, `thiserror`
- [ ] Public API: `pub fn compile(profile: Profile, query_client: &dyn QueryClient) -> Result<RuntimeProfile, Vec<Diagnostic>>`
- [ ] `QueryClient` trait defined with methods matching QueryServer endpoints (GET quests, NPCs, creatures, vendors, trainers, routes, etc.)
- [ ] `RuntimeProfile`, `RuntimeOperation`, `RuntimeAction`, `ResolvedActionPayload` types defined
- [ ] `Diagnostic` type: severity (Error/Warning/Info), error code, stage, message, entity reference, optional suggested fix
- [ ] Stage 1 (structural validation) implemented with checks:
  - Duplicate Action IDs within an Operation
  - Duplicate Operation IDs within a Profile
  - Dangling UUID references (Action→Variable, Blueprint→NPC, Action→Quest, Action→NPC)
  - TurnInQuest action with no matching PickupQuest in the same Operation or profile
  - Polygon with fewer than 3 vertices
  - Schema version mismatch
- [ ] Error codes namespaced as `C-1xxx` (e.g., `C-1001` for duplicate action ID)
- [ ] Unit tests for each Stage 1 check: construct a malformed Profile → compile → assert correct diagnostics returned
- [ ] `cargo test -p sentinel-compiler` passes
