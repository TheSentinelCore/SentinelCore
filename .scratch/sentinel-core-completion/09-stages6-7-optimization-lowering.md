---
id: 9
title: "Stages 6+7 — Optimization + Lowering"
state: open
labels: ["enhancement", "ready-for-agent", "size:large"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 09 — Stages 6+7: Optimization + Lowering

**What to build:** Implement the final two compiler stages — cross-operation optimization that merges and reorders actions, then lowering to the immutable RuntimeProfile that the Lua execution engine consumes.

**Blocked by:** #7, #8 (Stages 3, 4, 5 must complete — this is the final pipeline stage)

**Acceptance criteria:**

**Stage 6 — Cross-Operation Optimization:**
- [ ] Walk adjacent Operations in the compile order from Stage 4
- [ ] Merge trailing Vendor + leading GoTo when both targets are within configurable merge distance
- [ ] Collapse adjacent Vendor + Repair into a single interaction if same NPC serves both roles
- [ ] Drop redundant GoTo actions (current position already matches target, or previous GoTo has same destination)
- [ ] Reorder actions within an Operation when `allow_reordering: true` — minimize travel by querying QueryServer for route distances between action targets
- [ ] Optimization never breaks goal coverage: re-validate Stage 5 goals after each rewrite
- [ ] Error codes `C-6xxx` for: optimization that would break goal coverage (should not happen but defensive)

**Stage 7 — Lowering:**
- [ ] Convert optimized IR → `RuntimeProfile`:
  ```
  RuntimeProfile { schema_version, compiled_at, compiler_version, source_profile_id, source_profile_hash, operations: Vec<RuntimeOperation> }
  RuntimeOperation { id, name, entry_conditions, exit_conditions, goals, actions: Vec<RuntimeAction> }
  RuntimeAction { id, payload: ResolvedActionPayload, retry_policy, timeout_ms, generated_from }
  ```
- [ ] `ResolvedActionPayload` contains only fully-resolved data (no UUID references remaining)
- [ ] `CompileCache`: keyed on `source_profile_hash` — if hash unchanged, skip entire pipeline
- [ ] Error codes `C-7xxx` for: lowering failure (unexpected IR state)
- [ ] End-to-end test: compile the `northshire_example.json` from #2 → verify RuntimeProfile has correct Operations in correct order, all actions resolved, no Blueprint references remain
- [ ] `cargo test -p sentinel-compiler` passes with all stages green
