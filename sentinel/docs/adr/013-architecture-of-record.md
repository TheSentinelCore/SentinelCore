# SentinelCore — Architecture of Record

Version: 1.0
Status: Accepted
Date: 2026-07-19

Supersedes the implicit "Rust/Cargo workspace" assumption in ADR 012
(Implementation Tickets), which lists ten Rust crates implementing every
subsystem. This volume records the architecture the project actually
adopted and ratifies it as the source of truth for all future work.

---

# 1. The Decision

> **Lua owns all botting logic. Rust owns only the QueryServer — the
> database-backed query layer over the Mangos DB.**

## 1.1 What Lua owns (canonical runtime + compiler)

Everything that executes inside or against the Sylvanas runtime:

- Runtime execution engine (Phase 8): profile manager, operation manager,
  scheduler, action executor, event dispatcher, variable store, runtime
  context, dry-run, failure recovery, hot reload.
- The compiler (Phase 6): all seven stages, orchestrated in Lua.
- Profiles, storage, blueprints, operation logic (Phases 2, 4, 5).
- The Sylvanas bridge (Phase 7): quest/addons clients, event bridge,
  render surface, versioning.
- Editor behavior (Phase 10): panels, capture, timeline, inspector, etc.

Implementation lives in `sentinel/runtime/`, `sentinel/modules/`,
`sentinel/integrations/`, `sentinel/ui/`. The measure of done is
`luajit tests/run_offline.lua` (the offline harness).

## 1.2 What Rust owns (canonical QueryServer only)

- `sentinel-compiler/crates/sentinel-queryserver/` — the axum service over
  the Mangos DB (ADR 004). This is the one Rust subsystem that is
  canonical, because it is a standalone database service, not in-game
  logic.

## 1.3 What Rust does NOT own (demoted, secondary)

- `sentinel-compiler/crates/sentinel-schema` — earlier Rust mirror of the
  canonical schema. **Secondary / offline tooling. Do not add runtime
  logic here.**
- `sentinel-compiler/crates/sentinel-compiler` — earlier Rust mirror of the
  compiler. **Secondary / offline tooling. The Lua compiler is canonical.**

These crates are kept for reference and any offline tooling, but they are
not the deliverable described by ADR 012's Phase 1/4/6 tickets. New
runtime behavior goes in Lua.

---

# 2. Approved Divergences From the ADRs

The ADRs remain authoritative for *what* the system does. This volume
records where the *implementation* diverges by ratified decision:

- **Storage format (ADR 011 §2):** JSON on disk, not YAML. The structural
  properties ADR 011 cares about — one file per Operation, Tier1→Tier2
  resolution, atomic writes, dirty-tracked partial saves, per-file schema
  migration — are honored. The on-disk serialization format is JSON. No
  rewrite planned.
- **Tier1→Tier2 resolution timing (ADR 011 §8/§10):** resolved at compile
  time in Lua (`stage_reference_resolution.lua`), not as a separate
  load-time storage step. Functionally equivalent; differs only in phase.
- **Shared library files (ADR 011 §7):** no separate
  `npc_library/quest_library/vendor_library.yaml`; references resolved via
  QueryServer at compile time.
- **Language split:** Phases 2/4/5/6/7/8/10 are specified as Rust in the
  ADRs but implemented in Lua. This is the central fact this volume
  records.

---

# 3. Why

- The runtime must run inside Sylvanas (Lua). A Rust runtime would require
  a separate FFI/seam that adds no value for in-game logic.
- The QueryServer is a standalone DB service; Rust + axum + SQLite is the
  right tool and is decoupled from the game client by design (ADR 004).
- Rebuilding the substantial existing Lua engine as Rust would discard
  working, tested software. The ADRs describe behavior; Lua is how this
  project expresses it.

---

# 4. Consequences for Future Work

- When triaging ADR 012 tickets, map Rust-phase tickets to their Lua
  equivalents. "Done" means green in the Lua harness (or `cargo test -p
  sentinel-queryserver` for Phase 3).
- Do not start new Rust crates for runtime/compiler/blueprint/operation
  logic. Extend the Lua modules.
- Phase 9 (Analytics) remains deferred by MVP §17 (ADR 012 §17), independent
  of this decision.
- SENT-7.8 / SENT-11.6 are RESOLVED — ADR 009 §16 was verified against the
  in-repo `Documentation - Project Sylvannas/dev/api/`.

---

End of Volume 13
