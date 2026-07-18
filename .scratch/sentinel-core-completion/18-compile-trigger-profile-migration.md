---
id: 18
title: "Compile Trigger + Profile Migration"
state: open
labels: ["enhancement", "ready-for-agent", "size:medium"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 18 — Compile Trigger + Profile Migration

**What to build:** Wire the Rust compiler into the Lua runtime so the IDE's "Compile" button triggers a full compilation pipeline, and implement schema version migration for forward-compatible profile evolution.

**Blocked by:** #9 (Stages 6+7 — compiler must produce RuntimeProfile), #11 (Query Client — Lua needs HTTP to reach QueryServer), #15 (IDE — Compile button lives in the toolbar)

**Acceptance criteria:**

**Compile Trigger:**
- [ ] Toolbar "Compile" button (from #15) invokes the compile pipeline
- [ ] Flow: serialize active Profile to JSON → POST to QueryServer compile endpoint (or invoke Rust compiler binary directly) → receive RuntimeProfile JSON → deserialize into Lua runtime tables
- [ ] QueryServer exposes `POST /api/v1/compile` that accepts Profile JSON and returns RuntimeProfile JSON (new endpoint, or fallback: compiler runs as separate process reading/writing files)
- [ ] On compile success: RuntimeProfile swapped into active execution. Previous execution (if any) is cleanly stopped.
- [ ] On compile failure: diagnostics displayed in Validation Panel and Console. Profile remains in authoring state. No execution change.
- [ ] Compile progress: stages displayed in Console Panel as they complete (stage name, duration)
- [ ] Hot-reload: watch profile file for changes → auto-recompile → swap if successful
- [ ] End-to-end test: create a profile in the IDE → capture an NPC → add a GoTo action → Compile → verify RuntimeProfile is loaded and scheduler sees the operation

**Profile Migration:**
- [ ] Migration registry: ordered list of `(from_version, to_version, migration_fn)` tuples
- [ ] Migrations run before Stage 1 of compilation
- [ ] Each migration function transforms the profile Lua table from one schema version to the next
- [ ] Built-in migration: v0 → v1 (add `metadata.compiler_version` field if missing, default to "0.0.0")
- [ ] Error codes `M-xxxx` for: migration not found for version jump, migration function failed, version downgrade detected
- [ ] Migration logs displayed in Console Panel
- [ ] If migration fails: compilation aborted, error shown in Validation Panel
- [ ] Test: load a v0 profile → compile → verify metadata added → RuntimeProfile produced
- [ ] Test: load a profile with unknown version → compile → error with clear message
