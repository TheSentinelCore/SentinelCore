---
id: 11
title: "Query Client + Profile Manager (Lua)"
state: open
labels: ["enhancement", "ready-for-agent", "size:medium"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 11 — Query Client + Profile Manager (Lua)

**What to build:** Lua-side HTTP client for the QueryServer and a Profile Manager that handles loading, saving, validating, and activating authoring profiles. This is the first runtime engine ticket — it does NOT depend on the Rust compiler being done.

**Blocked by:** #1, #4 (QueryServer must be running and configurable)

**Acceptance criteria:**

**Query Client:**
- [ ] New module at `sentinel/runtime/query_client.lua`
- [ ] Wraps `core.http_get` for all QueryServer GET endpoints (quests, NPCs, creatures, vendors, trainers, routes, areas, hubs, validation, search)
- [ ] Response parsing via existing `lib/JSON.lua`
- [ ] Local response cache: keyed on endpoint + params, avoids redundant network calls within a configurable TTL (default 5 minutes)
- [ ] Graceful error handling: QueryServer unreachable → return nil + error message, log warning
- [ ] All methods return: `data, error` pattern (nil on failure)

**Profile Manager:**
- [ ] New module at `sentinel/runtime/profile_manager.lua`
- [ ] `load(path)` — Read JSON file from disk, deserialize into Lua table matching sentinel-schema Profile shape, validate basic structure
- [ ] `save(path)` — Serialize profile table to JSON, write to file. Include metadata: `created_at`, `updated_at`, `compiler_version`
- [ ] `validate(profile)` — Run structural validation (duplicate IDs, missing required fields). Return list of errors/warnings.
- [ ] `compile(profile)` — Placeholder for compiler integration (returns profile as-is for now, will connect to Rust compiler in #18)
- [ ] `activate(profile_id)` — Store active profile reference in blackboard at `module.runtime.active_profile`
- [ ] `deactivate()` — Clear active profile from blackboard
- [ ] Dirty tracking: `mark_dirty()` / `is_dirty()` / `clear_dirty()` on the active profile
- [ ] Profiles stored in Sylvannas `scripts_data/sentinel/profiles/` directory
- [ ] Unit tests (using offline harness from #3): load valid profile → success, load invalid JSON → error, save then load → round-trip equality, validate catches duplicate IDs
